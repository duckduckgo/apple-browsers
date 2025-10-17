//
//  BrokerProfileOptOutSubJob.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import Common
import BrowserServicesKit
import PixelKit
import os.log

struct BrokerProfileOptOutSubJob {
    struct OptOutIdentifiers {
        let brokerId: Int64
        let profileQueryId: Int64
        let extractedProfileId: Int64
    }

    struct StageDurationContext {
        let stageDurationCalculator: DataBrokerProtectionStageDurationCalculator
        let wideEventRecorder: OptOutSubmissionWideEventRecording?
    }

    private let dependencies: BrokerProfileJobDependencyProviding

    init(dependencies: BrokerProfileJobDependencyProviding) {
        dependencies.vpnBypassService?.setUp()
        self.dependencies = dependencies
    }

    private var vpnConnectionState: String {
        dependencies.vpnBypassService?.connectionStatus ?? "unknown"
    }

    private var vpnBypassStatus: String {
        dependencies.vpnBypassService?.bypassStatus.rawValue ?? "unknown"
    }

    // MARK: - Opt-Out Jobs

    /// Returns: `true` if the opt-out was executed, `false` if it was skipped due to:
    ///   - Profile already being removed
    ///   - Broker performing opt-outs within parent
    ///   - Profile manually removed by user
    public func runOptOut(for extractedProfile: ExtractedProfile,
                          brokerProfileQueryData: BrokerProfileQueryData,
                          showWebView: Bool,
                          shouldRunNextStep: @escaping () -> Bool) async throws -> Bool {
        guard let identifiers = try validateOptOutPreconditions(for: extractedProfile,
                                                                brokerProfileQueryData: brokerProfileQueryData,
                                                                database: dependencies.database) else {
            return false
        }

        let stageDurationContext = createStageDurationContext(for: brokerProfileQueryData,
                                                              identifiers: identifiers,
                                                              database: dependencies.database,
                                                              wideEvent: dependencies.wideEvent,
                                                              pixelHandler: dependencies.pixelHandler,
                                                              vpnConnectionState: vpnConnectionState,
                                                              vpnBypassStatus: vpnBypassStatus)

        // Set up a defer block to report opt-out job completion regardless of its success:
        defer {
            reportOptOutJobCompletion(
                brokerProfileQueryData: brokerProfileQueryData,
                extractedProfileId: identifiers.extractedProfileId,
                brokerId: identifiers.brokerId,
                profileQueryId: identifiers.profileQueryId,
                database: dependencies.database,
                notificationCenter: dependencies.notificationCenter
            )
        }

        do {
            try markOptOutStarted(identifiers: identifiers,
                                  database: dependencies.database)

            let runner = makeOptOutRunner(brokerProfileQueryData: brokerProfileQueryData,
                                          stageDurationCalculator: stageDurationContext.stageDurationCalculator,
                                          shouldRunNextStep: shouldRunNextStep,
                                          runnerFactory: dependencies.createOptOutRunner)

            try await executeOptOut(on: runner,
                                    brokerProfileQueryData: brokerProfileQueryData,
                                    extractedProfile: extractedProfile,
                                    showWebView: showWebView,
                                    shouldRunNextStep: shouldRunNextStep)

            if dependencies.featureFlagger.isEmailConfirmationDecouplingFeatureOn,
               brokerProfileQueryData.dataBroker.requiresEmailConfirmationDuringOptOut() {
                try handleEmailConfirmationDecoupling(database: dependencies.database,
                                                      pixelHandler: dependencies.pixelHandler,
                                                      brokerProfileQueryData: brokerProfileQueryData,
                                                      identifiers: identifiers,
                                                      stageDurationCalculator: stageDurationContext.stageDurationCalculator)
            } else {
                try finalizeOptOut(database: dependencies.database,
                                   brokerProfileQueryData: brokerProfileQueryData,
                                   identifiers: identifiers,
                                   stageDurationCalculator: stageDurationContext.stageDurationCalculator)
            }
        } catch {
            recordOptOutFailure(error: error,
                                brokerProfileQueryData: brokerProfileQueryData,
                                database: dependencies.database,
                                wideEvent: dependencies.wideEvent,
                                wideEventRecorder: stageDurationContext.wideEventRecorder,
                                schedulingConfig: brokerProfileQueryData.dataBroker.schedulingConfig,
                                identifiers: identifiers,
                                stageDurationCalculator: stageDurationContext.stageDurationCalculator)

            throw error
        }

        return true
    }

    internal func validateOptOutPreconditions(for extractedProfile: ExtractedProfile,
                                              brokerProfileQueryData: BrokerProfileQueryData,
                                              database: DataBrokerProtectionRepository) throws -> OptOutIdentifiers? {
        // 1. Validate that the broker and profile query data objects each have an ID:
        guard let brokerId = brokerProfileQueryData.dataBroker.id,
              let profileQueryId = brokerProfileQueryData.profileQuery.id,
              let extractedProfileId = extractedProfile.id else {
            // Maybe send pixel?
            throw BrokerProfileSubJobError.idsMissingForBrokerOrProfileQuery
        }

        // 2. Validate that profile hasn't already been opted-out:
        guard extractedProfile.removedDate == nil else {
            Logger.dataBrokerProtection.log("Profile already removed, skipping...")
            return nil
        }

        // 3. Validate that profile is eligible to be opted-out now:
        guard !brokerProfileQueryData.dataBroker.performsOptOutWithinParent() else {
            Logger.dataBrokerProtection.log("Broker opts out in parent, skipping...")
            return nil
        }

        // 4. Validate that profile isn't manually removed by user (using "This isn't me")
        guard let events = try? database.fetchOptOutHistoryEvents(brokerId: brokerId,
                                                                  profileQueryId: profileQueryId,
                                                                  extractedProfileId: extractedProfileId),
              !events.doesBelongToUserRemovedRecord else {
            Logger.dataBrokerProtection.log("Manually removed by user, skipping...")
            return nil
        }

        return OptOutIdentifiers(brokerId: brokerId,
                                 profileQueryId: profileQueryId,
                                 extractedProfileId: extractedProfileId)
    }

    internal func createStageDurationContext(for brokerProfileQueryData: BrokerProfileQueryData,
                                             identifiers: OptOutIdentifiers,
                                             database: DataBrokerProtectionRepository,
                                             wideEvent: WideEventManaging?,
                                             pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                                             vpnConnectionState: String,
                                             vpnBypassStatus: String) -> StageDurationContext {
        // 5. Set up dependencies used to report the status of the opt-out job:
        let stageDurationCalculator = DataBrokerProtectionStageDurationCalculator(
            dataBrokerURL: brokerProfileQueryData.dataBroker.url,
            dataBrokerVersion: brokerProfileQueryData.dataBroker.version,
            handler: pixelHandler,
            vpnConnectionState: vpnConnectionState,
            vpnBypassStatus: vpnBypassStatus
        )

        let recordFoundDate = RecordFoundDateResolver.resolve(brokerQueryProfileData: brokerProfileQueryData,
                                                              repository: database,
                                                              brokerId: identifiers.brokerId,
                                                              profileQueryId: identifiers.profileQueryId,
                                                              extractedProfileId: identifiers.extractedProfileId)
        let wideEventRecorder = OptOutSubmissionWideEventRecorder.makeIfPossible(
            wideEvent: wideEvent,
            attemptID: stageDurationCalculator.attemptId,
            dataBrokerURL: brokerProfileQueryData.dataBroker.url,
            dataBrokerVersion: brokerProfileQueryData.dataBroker.version,
            recordFoundDate: recordFoundDate
        )
        stageDurationCalculator.attachWideEventRecorder(wideEventRecorder)

        // 6. Record the start of the opt-out job:
        stageDurationCalculator.fireOptOutStart()
        Logger.dataBrokerProtection.log("Running opt-out operation: \(brokerProfileQueryData.dataBroker.name, privacy: .public)")

        return StageDurationContext(stageDurationCalculator: stageDurationCalculator,
                                    wideEventRecorder: wideEventRecorder)
    }

    internal func markOptOutStarted(identifiers: OptOutIdentifiers,
                                    database: DataBrokerProtectionRepository) throws {
        // 8a. Mark the profile as having its opt-out job started:
        try database.add(.init(extractedProfileId: identifiers.extractedProfileId,
                               brokerId: identifiers.brokerId,
                               profileQueryId: identifiers.profileQueryId,
                               type: .optOutStarted))
    }

    internal func makeOptOutRunner(brokerProfileQueryData: BrokerProfileQueryData,
                                   stageDurationCalculator: DataBrokerProtectionStageDurationCalculator,
                                   shouldRunNextStep: @escaping () -> Bool,
                                   runnerFactory: (BrokerProfileQueryData,
                                                   StageDurationCalculator,
                                                   @escaping () -> Bool) -> BrokerProfileOptOutSubJobWebRunning) -> BrokerProfileOptOutSubJobWebRunning {
        // 8b. Make the opt-out runner:
        return runnerFactory(brokerProfileQueryData,
                             stageDurationCalculator,
                             shouldRunNextStep)
    }

    internal func executeOptOut(on runner: BrokerProfileOptOutSubJobWebRunning,
                                brokerProfileQueryData: BrokerProfileQueryData,
                                extractedProfile: ExtractedProfile,
                                showWebView: Bool,
                                shouldRunNextStep: @escaping () -> Bool) async throws {
        // 8c. Perform the opt-out itself:
        try await runner.optOut(profileQuery: brokerProfileQueryData,
                                extractedProfile: extractedProfile,
                                showWebView: showWebView,
                                shouldRunNextStep: shouldRunNextStep)
    }

    internal func handleEmailConfirmationDecoupling(database: DataBrokerProtectionRepository,
                                                    pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                                                    brokerProfileQueryData: BrokerProfileQueryData,
                                                    identifiers: OptOutIdentifiers,
                                                    stageDurationCalculator: DataBrokerProtectionStageDurationCalculator) throws {
        // Halt the opt-out process
        // The EmailConfirmationJob will handle obtaining and clicking the confirmation link,
        // then resume the opt-out from this point
        Logger.dataBrokerProtection.log("✉️ Opt-out halting for email confirmation - broker: \(brokerProfileQueryData.dataBroker.name, privacy: .public), profile: \(identifiers.extractedProfileId, privacy: .public)")
        try database.add(.init(
            extractedProfileId: identifiers.extractedProfileId,
            brokerId: identifiers.brokerId,
            profileQueryId: identifiers.profileQueryId,
            type: .optOutSubmittedAndAwaitingEmailConfirmation
        ))
        pixelHandler.fire(
            .optOutStageSubmitAwaitingEmailConfirmation(
                dataBrokerURL: brokerProfileQueryData.dataBroker.url,
                brokerVersion: brokerProfileQueryData.dataBroker.version,
                attemptId: stageDurationCalculator.attemptId,
                actionId: stageDurationCalculator.actionID ?? "unknown",
                duration: stageDurationCalculator.durationSinceLastStage(),
                tries: stageDurationCalculator.tries
            )
        )
        stageDurationCalculator.setStage(.emailConfirmHalted)
        Logger.dataBrokerProtection.log("✉️ Opt-out status changed to awaiting email confirmation")
    }

    internal func finalizeOptOut(database: DataBrokerProtectionRepository,
                                 brokerProfileQueryData: BrokerProfileQueryData,
                                 identifiers: OptOutIdentifiers,
                                 stageDurationCalculator: DataBrokerProtectionStageDurationCalculator) throws {
        // Normal completion path - opt out was fully submitted
        // 8d. Update state to indicate that the opt-out has been requested, for a future scan to confirm:
        let tries = try fetchTotalNumberOfOptOutAttempts(database: database,
                                                         brokerId: identifiers.brokerId,
                                                         profileQueryId: identifiers.profileQueryId,
                                                         extractedProfileId: identifiers.extractedProfileId)
        stageDurationCalculator.fireOptOutValidate()
        stageDurationCalculator.fireOptOutSubmitSuccess(tries: tries)

        let updater = OperationPreferredDateUpdater(database: database)
        try updater.updateChildrenBrokerForParentBroker(brokerProfileQueryData.dataBroker,
                                                        profileQueryId: identifiers.profileQueryId)

        try database.addAttempt(extractedProfileId: identifiers.extractedProfileId,
                                attemptUUID: stageDurationCalculator.attemptId,
                                dataBroker: stageDurationCalculator.dataBrokerURL,
                                lastStageDate: stageDurationCalculator.lastStateTime,
                                startTime: stageDurationCalculator.startTime)
        try database.add(.init(extractedProfileId: identifiers.extractedProfileId,
                               brokerId: identifiers.brokerId,
                               profileQueryId: identifiers.profileQueryId,
                               type: .optOutRequested))
        try incrementOptOutAttemptCountIfNeeded(
            database: database,
            brokerId: identifiers.brokerId,
            profileQueryId: identifiers.profileQueryId,
            extractedProfileId: identifiers.extractedProfileId
        )
    }

    internal func recordOptOutFailure(error: Error,
                                      brokerProfileQueryData: BrokerProfileQueryData,
                                      database: DataBrokerProtectionRepository,
                                      wideEvent: WideEventManaging?,
                                      wideEventRecorder: OptOutSubmissionWideEventRecording?,
                                      schedulingConfig: DataBrokerScheduleConfig,
                                      identifiers: OptOutIdentifiers,
                                      stageDurationCalculator: DataBrokerProtectionStageDurationCalculator) {
        // 9. Records opt out failures caught on the main  orchestration function
        let tries = try? fetchTotalNumberOfOptOutAttempts(database: database,
                                                          brokerId: identifiers.brokerId,
                                                          profileQueryId: identifiers.profileQueryId,
                                                          extractedProfileId: identifiers.extractedProfileId)
        stageDurationCalculator.fireOptOutFailure(tries: tries ?? -1)
        switch error {
        case is TimeoutError:
            wideEventRecorder?.cancel(with: error)
            OptOutConfirmationWideEventEmitter.emitCancelled(
                wideEvent: wideEvent,
                attemptID: stageDurationCalculator.attemptId,
                dataBrokerURL: brokerProfileQueryData.dataBroker.url,
                dataBrokerVersion: brokerProfileQueryData.dataBroker.version,
                error: error
            )
        case let dbpError as DataBrokerProtectionError where dbpError == .jobTimeout:
            wideEventRecorder?.cancel(with: error)
            OptOutConfirmationWideEventEmitter.emitCancelled(
                wideEvent: wideEvent,
                attemptID: stageDurationCalculator.attemptId,
                dataBrokerURL: brokerProfileQueryData.dataBroker.url,
                dataBrokerVersion: brokerProfileQueryData.dataBroker.version,
                error: dbpError
            )
        default:
            wideEventRecorder?.complete(status: .failure, with: error)
            OptOutConfirmationWideEventEmitter.emitFailure(
                wideEvent: wideEvent,
                attemptID: stageDurationCalculator.attemptId,
                dataBrokerURL: brokerProfileQueryData.dataBroker.url,
                dataBrokerVersion: brokerProfileQueryData.dataBroker.version,
                error: error
            )
        }

        handleOperationError(
            origin: .optOut,
            brokerId: identifiers.brokerId,
            profileQueryId: identifiers.profileQueryId,
            extractedProfileId: identifiers.extractedProfileId,
            error: error,
            database: database,
            schedulingConfig: schedulingConfig
        )
    }

    private func reportOptOutJobCompletion(brokerProfileQueryData: BrokerProfileQueryData,
                                           extractedProfileId: Int64,
                                           brokerId: Int64,
                                           profileQueryId: Int64,
                                           database: DataBrokerProtectionRepository,
                                           notificationCenter: NotificationCenter) {
        Logger.dataBrokerProtection.log("Finished opt-out operation: \(brokerProfileQueryData.dataBroker.name, privacy: .public)")

        try? database.updateLastRunDate(Date(), brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
        do {
            try updateOperationDataDates(
                origin: .optOut,
                brokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId,
                schedulingConfig: brokerProfileQueryData.dataBroker.schedulingConfig,
                database: database
            )
        } catch {
            handleOperationError(
                origin: .optOut,
                brokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId,
                error: error,
                database: database,
                schedulingConfig: brokerProfileQueryData.dataBroker.schedulingConfig
            )
        }
        notificationCenter.post(name: DataBrokerProtectionNotifications.didFinishOptOut, object: brokerProfileQueryData.dataBroker.name)
    }

    private func incrementOptOutAttemptCountIfNeeded(database: DataBrokerProtectionRepository,
                                                     brokerId: Int64,
                                                     profileQueryId: Int64,
                                                     extractedProfileId: Int64) throws {
        guard let events = try? database.fetchOptOutHistoryEvents(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId),
              events.max(by: { $0.date < $1.date })?.type == .optOutRequested else {
            return
        }

        try database.incrementAttemptCount(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
    }

    private func fetchTotalNumberOfOptOutAttempts(database: DataBrokerProtectionRepository,
                                                  brokerId: Int64,
                                                  profileQueryId: Int64,
                                                  extractedProfileId: Int64) throws -> Int {
        let events = try database.fetchOptOutHistoryEvents(
            brokerId: brokerId,
            profileQueryId: profileQueryId,
            extractedProfileId: extractedProfileId
        )

        return events.filter { $0.type == .optOutStarted }.count
    }

    // MARK: - Generic Job Logic

    internal func updateOperationDataDates(origin: OperationPreferredDateUpdaterOrigin,
                                           brokerId: Int64,
                                           profileQueryId: Int64,
                                           extractedProfileId: Int64?,
                                           schedulingConfig: DataBrokerScheduleConfig,
                                           database: DataBrokerProtectionRepository) throws {
        let dateUpdater = OperationPreferredDateUpdater(database: database)
        try dateUpdater.updateOperationDataDates(origin: origin,
                                                 brokerId: brokerId,
                                                 profileQueryId: profileQueryId,
                                                 extractedProfileId: extractedProfileId,
                                                 schedulingConfig: schedulingConfig)
    }

    private func handleOperationError(origin: OperationPreferredDateUpdaterOrigin,
                                      brokerId: Int64,
                                      profileQueryId: Int64,
                                      extractedProfileId: Int64?,
                                      error: Error,
                                      database: DataBrokerProtectionRepository,
                                      schedulingConfig: DataBrokerScheduleConfig) {
        let event: HistoryEvent

        if let extractedProfileId = extractedProfileId {
            if let error = error as? DataBrokerProtectionError {
                event = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .error(error: error))
            } else {
                event = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .error(error: .unknown(error.localizedDescription)))
            }
        } else {
            if let error = error as? DataBrokerProtectionError {
                event = HistoryEvent(brokerId: brokerId, profileQueryId: profileQueryId, type: .error(error: error))
            } else {
                event = HistoryEvent(brokerId: brokerId, profileQueryId: profileQueryId, type: .error(error: .unknown(error.localizedDescription)))
            }
        }

        try? database.add(event)

        do {
            try updateOperationDataDates(
                origin: origin,
                brokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId,
                schedulingConfig: schedulingConfig,
                database: database
            )
        } catch {
            Logger.dataBrokerProtection.log("Can't update operation date after error")
        }

        Logger.dataBrokerProtection.error("Error on operation : \(error.localizedDescription, privacy: .public)")
    }

}
