//
//  DataBrokerProfileQueryOperationManager.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

enum OperationsError: Error {
    case idsMissingForBrokerOrProfileQuery
}

protocol OperationsManager {

    // We want to refactor this to return a NSOperation in the future
    // so we have more control of stopping/starting the queue
    // for the time being, shouldRunNextStep: @escaping () -> Bool is being used
    func runOperation(operationData: BrokerJobData,
                      brokerProfileQueryData: BrokerProfileQueryData,
                      database: DataBrokerProtectionRepository,
                      notificationCenter: NotificationCenter,
                      runner: WebJobRunner,
                      pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                      showWebView: Bool,
                      isImmediateOperation: Bool,
                      eventsHandler: EventMapping<OperationEvent>,
                      shouldRunNextStep: @escaping () -> Bool) async throws
}

struct DataBrokerProfileQueryOperationManager: OperationsManager {
    private let vpnBypassService: VPNBypassFeatureProvider?

    init(vpnBypassService: VPNBypassFeatureProvider?) {
        vpnBypassService?.setUp()
        self.vpnBypassService = vpnBypassService
    }

    private var vpnConnectionState: String {
        vpnBypassService?.connectionStatus ?? "unknown"
    }

    private var vpnBypassStatus: String {
        vpnBypassService?.bypassStatus.rawValue ?? "unknown"
    }

    internal func runOperation(operationData: BrokerJobData,
                               brokerProfileQueryData: BrokerProfileQueryData,
                               database: DataBrokerProtectionRepository,
                               notificationCenter: NotificationCenter = NotificationCenter.default,
                               runner: WebJobRunner,
                               pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                               showWebView: Bool = false,
                               isImmediateOperation: Bool = false,
                               eventsHandler: EventMapping<OperationEvent>,
                               shouldRunNextStep: @escaping () -> Bool) async throws {

        if operationData as? ScanJobData != nil {
            try await runScanOperation(on: runner,
                                       brokerProfileQueryData: brokerProfileQueryData,
                                       database: database,
                                       notificationCenter: notificationCenter,
                                       pixelHandler: pixelHandler,
                                       showWebView: showWebView,
                                       isManual: isImmediateOperation,
                                       eventsHandler: eventsHandler,
                                       shouldRunNextStep: shouldRunNextStep)
        } else if let optOutJobData = operationData as? OptOutJobData {
            try await runOptOutOperation(for: optOutJobData.extractedProfile,
                                         on: runner,
                                         brokerProfileQueryData: brokerProfileQueryData,
                                         database: database,
                                         notificationCenter: notificationCenter,
                                         pixelHandler: pixelHandler,
                                         showWebView: showWebView,
                                         eventsHandler: eventsHandler,
                                         shouldRunNextStep: shouldRunNextStep)
        }
    }

    // MARK: - Scan Jobs

    internal func runScanOperation(on runner: WebJobRunner,
                                   brokerProfileQueryData: BrokerProfileQueryData,
                                   database: DataBrokerProtectionRepository,
                                   notificationCenter: NotificationCenter,
                                   pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                                   showWebView: Bool = false,
                                   isManual: Bool = false,
                                   eventsHandler: EventMapping<OperationEvent>,
                                   shouldRunNextStep: @escaping () -> Bool) async throws {
        Logger.dataBrokerProtection.log("Running scan operation: \(brokerProfileQueryData.dataBroker.name, privacy: .public)")

        // 1. Validate that the broker and profile query data objects each have an ID:
        guard let brokerId = brokerProfileQueryData.dataBroker.id,
              let profileQueryId = brokerProfileQueryData.profileQuery.id else {
            // Maybe send pixel?
            throw OperationsError.idsMissingForBrokerOrProfileQuery
        }

        defer {
            try? database.updateLastRunDate(Date(), brokerId: brokerId, profileQueryId: profileQueryId)
            notificationCenter.post(name: DataBrokerProtectionNotifications.didFinishScan, object: brokerProfileQueryData.dataBroker.name)
            Logger.dataBrokerProtection.log("Finished scan operation: \(brokerProfileQueryData.dataBroker.name, privacy: .public)")
        }

        // 2. Set up dependencies used to report the status of the scan job:
        let eventPixels = DataBrokerProtectionEventPixels(database: database, handler: pixelHandler)
        let stageCalculator = DataBrokerProtectionStageDurationCalculator(
            dataBroker: brokerProfileQueryData.dataBroker.name,
            dataBrokerVersion: brokerProfileQueryData.dataBroker.version,
            handler: pixelHandler,
            isImmediateOperation: isManual,
            vpnConnectionState: vpnConnectionState,
            vpnBypassStatus: vpnBypassStatus
        )

        do {
            // 3. Record the start of the scan job:
            let event = HistoryEvent(brokerId: brokerId, profileQueryId: profileQueryId, type: .scanStarted)
            try database.add(event)

            // 4. Get extracted profiles from the runner:
            let profilesFoundDuringCurrentScanJob = try await runner.scan(
                brokerProfileQueryData,
                stageCalculator: stageCalculator,
                pixelHandler: pixelHandler,
                showWebView: showWebView,
                shouldRunNextStep: shouldRunNextStep
            )

            Logger.dataBrokerProtection.log("OperationManager found profiles: \(profilesFoundDuringCurrentScanJob, privacy: .public)")

            // 5. Handle the extracted profiles reported by the runner:
            if !profilesFoundDuringCurrentScanJob.isEmpty {
                // 5a. Send observability signals to indicate that the scan found matches:
                stageCalculator.fireScanSuccess(matchesFound: profilesFoundDuringCurrentScanJob.count)
                let event = HistoryEvent(
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    type: .matchesFound(count: profilesFoundDuringCurrentScanJob.count)
                )
                try database.add(event)

                // 5b. Iterate over found profiles and process them:
                try scheduleOptOutsForExtractedProfiles(extractedProfiles: profilesFoundDuringCurrentScanJob,
                                                        brokerProfileQueryData: brokerProfileQueryData,
                                                        brokerId: brokerId,
                                                        profileQueryId: profileQueryId,
                                                        database: database,
                                                        eventPixels: eventPixels,
                                                        stageCalculator: stageCalculator)
            } else {
                // 5c. Report the status of the scan, which found no matches:
                try storeScanWithNoMatchesEvent(
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    database: database,
                    stageCalculator: stageCalculator
                )
            }

            // 6. Check for removed profiles by comparing the set of saved profiles to those just found via scan:
            let removedProfiles = brokerProfileQueryData.extractedProfiles.filter { savedProfile in
                !profilesFoundDuringCurrentScanJob.contains { recentlyFoundProfile in
                    recentlyFoundProfile.identifier == savedProfile.identifier
                }
            }

            // 7. Handle removed profiles:
            if !removedProfiles.isEmpty {
                // 7a. If there were removed profiles, update their state and notify the user:
                try markSavedProfilesAsRemovedAndNotifyUser(
                    removedProfiles: removedProfiles,
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    brokerProfileQueryData: brokerProfileQueryData,
                    database: database,
                    pixelHandler: pixelHandler,
                    eventsHandler: eventsHandler
                )
            } else {
                // 7b. If there were no removed profiles, update the date entries:
                try updateOperationDataDates(
                    origin: .scan,
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    extractedProfileId: nil,
                    schedulingConfig: brokerProfileQueryData.dataBroker.schedulingConfig,
                    database: database
                )
            }
        } catch {
            // 8. Process errors returned by the scan job:
            stageCalculator.fireScanError(error: error)
            handleOperationError(origin: .scan,
                                 brokerId: brokerId,
                                 profileQueryId: profileQueryId,
                                 extractedProfileId: nil,
                                 error: error,
                                 database: database,
                                 schedulingConfig: brokerProfileQueryData.dataBroker.schedulingConfig)
            throw error
        }
    }

    private func scheduleOptOutsForExtractedProfiles(extractedProfiles: [ExtractedProfile],
                                                     brokerProfileQueryData: BrokerProfileQueryData,
                                                     brokerId: Int64,
                                                     profileQueryId: Int64,
                                                     database: DataBrokerProtectionRepository,
                                                     eventPixels: DataBrokerProtectionEventPixels,
                                                     stageCalculator: DataBrokerProtectionStageDurationCalculator) throws {
        // Fetch the profiles already stored for the broker.
        let existingProfiles = try database.fetchExtractedProfiles(for: brokerId)

        for extractedProfile in extractedProfiles {
            if let existingProfile = existingProfiles.first(where: { $0.identifier == extractedProfile.identifier }),
               let id = existingProfile.id {
                // If the profile was previously removed but now reappeared, reset the removal date.
                if existingProfile.removedDate != nil {
                    let reAppearanceEvent = HistoryEvent(extractedProfileId: extractedProfile.id,
                                                         brokerId: brokerId,
                                                         profileQueryId: profileQueryId,
                                                         type: .reAppearence)
                    eventPixels.fireReappeareanceEventPixel()
                    try database.add(reAppearanceEvent)
                    try database.updateRemovedDate(nil, on: id)
                }
                Logger.dataBrokerProtection.log("Extracted profile already exists in database: \(id.description)")
            } else {
                try scheduleNewOptOutJob(from: extractedProfile,
                                         brokerProfileQueryData: brokerProfileQueryData,
                                         brokerId: brokerId,
                                         profileQueryId: profileQueryId,
                                         database: database,
                                         eventPixels: eventPixels)
            }
        }
    }

    private func scheduleNewOptOutJob(from extractedProfile: ExtractedProfile,
                                      brokerProfileQueryData: BrokerProfileQueryData,
                                      brokerId: Int64,
                                      profileQueryId: Int64,
                                      database: DataBrokerProtectionRepository,
                                      eventPixels: DataBrokerProtectionEventPixels) throws {
        // If it's a new found profile, we'd like to opt-out ASAP
        // If this broker has a parent opt out, we set the preferred date to nil, as we will only perform the operation
        // within the parent.
        eventPixels.fireNewMatchEventPixel()
        let broker = brokerProfileQueryData.dataBroker
        let preferredRunOperation: Date? = broker.performsOptOutWithinParent() ? nil : Date()

        // If profile does not exist we insert the new profile and we create the opt-out operation
        //
        // This is done inside a transaction on the database side. We insert the extracted profile and then
        // we insert the opt-out operation, we do not want to do things separately in case creating an opt-out fails
        // causing the extracted profile to be orphan.
        let optOutJobData = OptOutJobData(
            brokerId: brokerId,
            profileQueryId: profileQueryId,
            createdDate: Date(),
            preferredRunDate: preferredRunOperation,
            historyEvents: [],
            attemptCount: 0,
            submittedSuccessfullyDate: nil,
            extractedProfile: extractedProfile,
            sevenDaysConfirmationPixelFired: false,
            fourteenDaysConfirmationPixelFired: false,
            twentyOneDaysConfirmationPixelFired: false
        )

        try database.saveOptOutJob(optOut: optOutJobData, extractedProfile: extractedProfile)
        Logger.dataBrokerProtection.log("Creating new opt-out operation data for: \(String(describing: extractedProfile.name))")
    }

    private func storeScanWithNoMatchesEvent(brokerId: Int64,
                                             profileQueryId: Int64,
                                             database: DataBrokerProtectionRepository,
                                             stageCalculator: DataBrokerProtectionStageDurationCalculator) throws {
        stageCalculator.fireScanFailed()
        let event = HistoryEvent(brokerId: brokerId, profileQueryId: profileQueryId, type: .noMatchFound)
        try database.add(event)
    }

    private func markSavedProfilesAsRemovedAndNotifyUser(
        removedProfiles: [ExtractedProfile],
        brokerId: Int64,
        profileQueryId: Int64,
        brokerProfileQueryData: BrokerProfileQueryData,
        database: DataBrokerProtectionRepository,
        pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
        eventsHandler: EventMapping<OperationEvent>
    ) throws {
        var shouldSendProfileRemovedEvent = false
        for removedProfile in removedProfiles {
            if let extractedProfileId = removedProfile.id {
                let event = HistoryEvent(
                    extractedProfileId: extractedProfileId,
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    type: .optOutConfirmed
                )
                try database.add(event)
                try database.updateRemovedDate(Date(), on: extractedProfileId)
                shouldSendProfileRemovedEvent = true

                try updateOperationDataDates(
                    origin: .scan,
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    extractedProfileId: extractedProfileId,
                    schedulingConfig: brokerProfileQueryData.dataBroker.schedulingConfig,
                    database: database
                )

                Logger.dataBrokerProtection.log("Profile removed from optOutsData: \(String(describing: removedProfile))")

                if let attempt = try database.fetchAttemptInformation(for: extractedProfileId),
                   let attemptUUID = UUID(uuidString: attempt.attemptId) {
                    let now = Date()
                    let calculateDurationSinceLastStage = now.timeIntervalSince(attempt.lastStageDate) * 1000
                    let calculateDurationSinceStart = now.timeIntervalSince(attempt.startDate) * 1000
                    pixelHandler.fire(.optOutFinish(dataBroker: attempt.dataBroker, attemptId: attemptUUID, duration: calculateDurationSinceLastStage))
                    pixelHandler.fire(.optOutSuccess(dataBroker: attempt.dataBroker, attemptId: attemptUUID, duration: calculateDurationSinceStart,
                                                     brokerType: brokerProfileQueryData.dataBroker.type, vpnConnectionState: vpnConnectionState, vpnBypassStatus: vpnBypassStatus))
                }
            }
        }

        if shouldSendProfileRemovedEvent {
            sendProfilesRemovedEventIfNecessary(eventsHandler: eventsHandler, database: database)
        }
    }

    private func sendProfilesRemovedEventIfNecessary(eventsHandler: EventMapping<OperationEvent>,
                                                     database: DataBrokerProtectionRepository) {

        guard let savedExtractedProfiles = try? database.fetchAllBrokerProfileQueryData().flatMap({ $0.extractedProfiles }),
              savedExtractedProfiles.count > 0 else {
            return
        }

        if savedExtractedProfiles.count == 1 {
            eventsHandler.fire(.allProfilesRemoved)
        } else {
            if savedExtractedProfiles.allSatisfy({ $0.removedDate != nil }) {
                eventsHandler.fire(.allProfilesRemoved)
            } else {
                eventsHandler.fire(.firstProfileRemoved)
            }
        }
    }

    // MARK: - Opt-Out Jobs

    internal func runOptOutOperation(for extractedProfile: ExtractedProfile,
                                     on runner: WebJobRunner,
                                     brokerProfileQueryData: BrokerProfileQueryData,
                                     database: DataBrokerProtectionRepository,
                                     notificationCenter: NotificationCenter,
                                     pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                                     showWebView: Bool = false,
                                     eventsHandler: EventMapping<OperationEvent>,
                                     shouldRunNextStep: @escaping () -> Bool) async throws {
        // 1. Validate that the broker and profile query data objects each have an ID:
        guard let brokerId = brokerProfileQueryData.dataBroker.id,
              let profileQueryId = brokerProfileQueryData.profileQuery.id,
              let extractedProfileId = extractedProfile.id else {
            // Maybe send pixel?
            throw OperationsError.idsMissingForBrokerOrProfileQuery
        }

        // 2. Validate that profile hasn't already been opted-out:
        guard extractedProfile.removedDate == nil else {
            Logger.dataBrokerProtection.log("Profile already removed, skipping...")
            return
        }

        // 3. Validate that profile is eligible to be opted-out now:
        guard !brokerProfileQueryData.dataBroker.performsOptOutWithinParent() else {
            Logger.dataBrokerProtection.log("Broker opts out in parent, skipping...")
            return
        }

        // 4. Set up dependencies used to report the status of the opt-out job:
        let stageDurationCalculator = DataBrokerProtectionStageDurationCalculator(
            dataBroker: brokerProfileQueryData.dataBroker.url,
            dataBrokerVersion: brokerProfileQueryData.dataBroker.version,
            handler: pixelHandler,
            vpnConnectionState: vpnConnectionState,
            vpnBypassStatus: vpnBypassStatus
        )

        // 5. Record the start of the opt-out job:
        stageDurationCalculator.fireOptOutStart()
        Logger.dataBrokerProtection.log("Running opt-out operation: \(brokerProfileQueryData.dataBroker.name, privacy: .public)")

        // 6. Set up a defer block to report opt-out job completion regardless of its success:
        defer {
            reportOptOutJobCompletion(
                brokerProfileQueryData: brokerProfileQueryData,
                extractedProfileId: extractedProfileId,
                brokerId: brokerId,
                profileQueryId: profileQueryId,
                database: database,
                notificationCenter: notificationCenter
            )
        }

        // 7. Perform the opt-out:
        do {
            // 7a. Mark the profile as having its opt-out job started:
            try database.add(.init(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutStarted))

            // 7b. Perform the opt-out itself:
            try await runner.optOut(profileQuery: brokerProfileQueryData,
                                    extractedProfile: extractedProfile,
                                    stageCalculator: stageDurationCalculator,
                                    pixelHandler: pixelHandler,
                                    showWebView: showWebView,
                                    shouldRunNextStep: shouldRunNextStep)

            // 7c. Update state to indicate that the opt-out has been requested, for a future scan to confirm:
            let tries = try fetchTotalNumberOfOptOutAttempts(database: database, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
            stageDurationCalculator.fireOptOutValidate()
            stageDurationCalculator.fireOptOutSubmitSuccess(tries: tries)

            let updater = OperationPreferredDateUpdaterUseCase(database: database)
            try updater.updateChildrenBrokerForParentBroker(brokerProfileQueryData.dataBroker, profileQueryId: profileQueryId)

            try database.addAttempt(extractedProfileId: extractedProfileId,
                                    attemptUUID: stageDurationCalculator.attemptId,
                                    dataBroker: stageDurationCalculator.dataBroker,
                                    lastStageDate: stageDurationCalculator.lastStateTime,
                                    startTime: stageDurationCalculator.startTime)
            try database.add(.init(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested))
            try incrementOptOutAttemptCountIfNeeded(
                database: database,
                brokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId
            )
        } catch {
            // 8. Catch errors from the opt-out job and report them:
            let tries = try? fetchTotalNumberOfOptOutAttempts(database: database, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
            stageDurationCalculator.fireOptOutFailure(tries: tries ?? -1)
            handleOperationError(
                origin: .optOut,
                brokerId: brokerId,
                profileQueryId: profileQueryId,
                extractedProfileId: extractedProfileId,
                error: error,
                database: database,
                schedulingConfig: brokerProfileQueryData.dataBroker.schedulingConfig
            )
            throw error
        }
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
        let dateUpdater = OperationPreferredDateUpdaterUseCase(database: database)
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

extension Bundle {
    struct Keys {
        static let vpnMenuAgentBundleId = "AGENT_BUNDLE_ID"
    }

    var vpnMenuAgentBundleId: String {
        guard let bundleID = object(forInfoDictionaryKey: Keys.vpnMenuAgentBundleId) as? String else {
            fatalError("Info.plist is missing \(Keys.vpnMenuAgentBundleId)")
        }
        return bundleID
    }
}
