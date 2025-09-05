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
import os.log

struct BrokerProfileOptOutSubJob {
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
            return false
        }

        // 3. Validate that profile is eligible to be opted-out now:
        guard !brokerProfileQueryData.dataBroker.performsOptOutWithinParent() else {
            Logger.dataBrokerProtection.log("Broker opts out in parent, skipping...")
            return false
        }

        // 4. Validate that profile isn't manually removed by user (using "This isn't me")
        guard let events = try? dependencies.database.fetchOptOutHistoryEvents(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId),
              !events.doesBelongToUserRemovedRecord else {
            Logger.dataBrokerProtection.log("Manually removed by user, skipping...")
            return false
        }

        // 5. Set up dependencies used to report the status of the opt-out job:
        let stageDurationCalculator = DataBrokerProtectionStageDurationCalculator(
            dataBroker: brokerProfileQueryData.dataBroker.url,
            dataBrokerVersion: brokerProfileQueryData.dataBroker.version,
            handler: dependencies.pixelHandler,
            vpnConnectionState: vpnConnectionState,
            vpnBypassStatus: vpnBypassStatus
        )

        // 6. Record the start of the opt-out job:
        stageDurationCalculator.fireOptOutStart()
        Logger.dataBrokerProtection.log("Running opt-out operation: \(brokerProfileQueryData.dataBroker.name, privacy: .public)")

        // 7. Set up a defer block to report opt-out job completion regardless of its success:
        defer {
            reportOptOutJobCompletion(
                brokerProfileQueryData: brokerProfileQueryData,
                extractedProfileId: extractedProfileId,
                brokerId: brokerId,
                profileQueryId: profileQueryId,
                database: dependencies.database,
                notificationCenter: dependencies.notificationCenter
            )
        }

        // 8. Perform the opt-out:
        do {
            // 8a. Mark the profile as having its opt-out job started:
            try dependencies.database.add(.init(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutStarted))

            // 8b. Perform the opt-out itself:
            let runner = dependencies.createOptOutRunner(
                profileQuery: brokerProfileQueryData,
                stageDurationCalculator: stageDurationCalculator,
                shouldRunNextStep: shouldRunNextStep
            )

            try await runner.optOut(profileQuery: brokerProfileQueryData,
                                    extractedProfile: extractedProfile,
                                    showWebView: showWebView,
                                    shouldRunNextStep: shouldRunNextStep)

            if dependencies.featureFlagger.isEmailConfirmationDecouplingFeatureOn,
               brokerProfileQueryData.dataBroker.requiresEmailConfirmationDuringOptOut() {
                // Halt the opt-out process
                // The EmailConfirmationJob will handle obtaining and clicking the confirmation link,
                // then resume the opt-out from this point
                Logger.dataBrokerProtection.log("✉️ Opt-out halting for email confirmation - broker: \(brokerProfileQueryData.dataBroker.name, privacy: .public), profile: \(extractedProfileId, privacy: .public)")
                try dependencies.database.add(.init(
                    extractedProfileId: extractedProfileId,
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    type: .optOutSubmittedAndAwaitingEmailConfirmation
                ))
                Logger.dataBrokerProtection.log("✉️ Opt-out status changed to awaiting email confirmation")
            } else {
                // Normal completion path - opt out was fully submitted
                // 8c. Update state to indicate that the opt-out has been requested, for a future scan to confirm:
                let tries = try fetchTotalNumberOfOptOutAttempts(database: dependencies.database, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
                stageDurationCalculator.fireOptOutValidate()
                stageDurationCalculator.fireOptOutSubmitSuccess(tries: tries)

                let updater = OperationPreferredDateUpdater(database: dependencies.database)
                try updater.updateChildrenBrokerForParentBroker(brokerProfileQueryData.dataBroker, profileQueryId: profileQueryId)

                try dependencies.database.addAttempt(extractedProfileId: extractedProfileId,
                                                     attemptUUID: stageDurationCalculator.attemptId,
                                                     dataBroker: stageDurationCalculator.dataBroker,
                                                     lastStageDate: stageDurationCalculator.lastStateTime,
                                                     startTime: stageDurationCalculator.startTime)
                try dependencies.database.add(.init(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested))
                try incrementOptOutAttemptCountIfNeeded(
                    database: dependencies.database,
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    extractedProfileId: extractedProfileId
                )
            }
        } catch {
            // 9. Catch errors from the opt-out job and report them:
            let tries = try? fetchTotalNumberOfOptOutAttempts(database: dependencies.database, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
            stageDurationCalculator.fireOptOutFailure(tries: tries ?? -1)
            handleOperationError(
                origin: .optOut,
                brokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId,
                error: error,
                database: dependencies.database,
                schedulingConfig: brokerProfileQueryData.dataBroker.schedulingConfig
            )
            throw error
        }

        return true
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
