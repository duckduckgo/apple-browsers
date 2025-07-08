//
//  BrokerProfileScanSubJob.swift
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

struct BrokerProfileScanSubJob {
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

    // MARK: - Scan Jobs

    public func runScan(brokerProfileQueryData: BrokerProfileQueryData,
                        showWebView: Bool,
                        isManual: Bool,
                        shouldRunNextStep: @escaping () -> Bool) async throws {

        // 1. Validate that the broker and profile query data objects each have an ID:
        guard let brokerId = brokerProfileQueryData.dataBroker.id,
              let profileQueryId = brokerProfileQueryData.profileQuery.id else {
            // Maybe send pixel?
            throw BrokerProfileSubJobError.idsMissingForBrokerOrProfileQuery
        }

        defer {
            let lastRunDate = Date()
            try? dependencies.database.updateLastRunDate(lastRunDate, brokerId: brokerId, profileQueryId: profileQueryId)
            dependencies.notificationCenter.post(name: DataBrokerProtectionNotifications.didFinishScan, object: brokerProfileQueryData.dataBroker.name)
        }

        // 2. Set up dependencies used to report the status of the scan job:
        let eventPixels = DataBrokerProtectionEventPixels(database: dependencies.database, handler: dependencies.pixelHandler)
        let stageCalculator = DataBrokerProtectionStageDurationCalculator(
            dataBroker: brokerProfileQueryData.dataBroker.name,
            dataBrokerVersion: brokerProfileQueryData.dataBroker.version,
            handler: dependencies.pixelHandler,
            isImmediateOperation: isManual,
            vpnConnectionState: vpnConnectionState,
            vpnBypassStatus: vpnBypassStatus
        )

        do {
            // 3. Record the start of the scan job:
            let event = HistoryEvent(brokerId: brokerId, profileQueryId: profileQueryId, type: .scanStarted)
            try dependencies.database.add(event)

#if os(iOS)
            stageCalculator.fireScanStarted()
#endif

            // 4. Get extracted profiles from the runner:
            let runner = dependencies.createScanRunner(profileQuery: brokerProfileQueryData,
                                                       stageDurationCalculator: stageCalculator,
                                                       shouldRunNextStep: shouldRunNextStep)

            let profilesFoundDuringCurrentScanJob = try await runner.scan(brokerProfileQueryData,
                                                                          showWebView: showWebView,
                                                                          shouldRunNextStep: shouldRunNextStep)

            // 5. Handle the extracted profiles reported by the runner:
            if !profilesFoundDuringCurrentScanJob.isEmpty {
                // 5a. Send observability signals to indicate that the scan found matches:
                stageCalculator.fireScanSuccess(matchesFound: profilesFoundDuringCurrentScanJob.count)
                let event = HistoryEvent(
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    type: .matchesFound(count: profilesFoundDuringCurrentScanJob.count)
                )
                try dependencies.database.add(event)

                // 5b. Iterate over found profiles and process them:
                try scheduleOptOutsForExtractedProfiles(extractedProfiles: profilesFoundDuringCurrentScanJob,
                                                        brokerProfileQueryData: brokerProfileQueryData,
                                                        brokerId: brokerId,
                                                        profileQueryId: profileQueryId,
                                                        database: dependencies.database,
                                                        eventPixels: eventPixels,
                                                        stageCalculator: stageCalculator)
            } else {
                // 5c. Report the status of the scan, which found no matches:
                try storeScanWithNoMatchesEvent(
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    database: dependencies.database,
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
                    database: dependencies.database,
                    pixelHandler: dependencies.pixelHandler,
                    eventsHandler: dependencies.eventsHandler
                )
            } else {
                // 7b. If there were no removed profiles, update the date entries:
                try updateOperationDataDates(
                    origin: .scan,
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    extractedProfileId: nil,
                    schedulingConfig: brokerProfileQueryData.dataBroker.schedulingConfig,
                    database: dependencies.database
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
                                 database: dependencies.database,
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
        eventsHandler: EventMapping<JobEvent>
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

                if let attempt = try database.fetchAttemptInformation(for: extractedProfileId),
                   let attemptUUID = UUID(uuidString: attempt.attemptId) {
                    let now = Date()
                    let calculateDurationSinceLastStage = now.timeIntervalSince(attempt.lastStageDate) * 1000
                    let calculateDurationSinceStart = now.timeIntervalSince(attempt.startDate) * 1000
                    pixelHandler.fire(.optOutFinish(dataBroker: attempt.dataBroker, attemptId: attemptUUID, duration: calculateDurationSinceLastStage))

// This should never ever go to production and only exists for internal testing
#if os(iOS)
                    pixelHandler.fire(.optOutSuccess(dataBroker: attempt.dataBroker,
                                                     attemptId: attemptUUID,
                                                     duration: calculateDurationSinceStart,
                                                     brokerType: brokerProfileQueryData.dataBroker.type,
                                                     vpnConnectionState: vpnConnectionState,
                                                     vpnBypassStatus: vpnBypassStatus,
                                                     deviceID: DataBrokerProtectionSettings.deviceIdentifier))
#else
                    pixelHandler.fire(.optOutSuccess(dataBroker: attempt.dataBroker, attemptId: attemptUUID, duration: calculateDurationSinceStart,
                                                     brokerType: brokerProfileQueryData.dataBroker.type, vpnConnectionState: vpnConnectionState, vpnBypassStatus: vpnBypassStatus))
#endif
                }
            }
        }

        if shouldSendProfileRemovedEvent {
            sendProfilesRemovedEventIfNecessary(eventsHandler: eventsHandler, database: database)
        }
    }

    private func sendProfilesRemovedEventIfNecessary(eventsHandler: EventMapping<JobEvent>,
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

        Logger.dataBrokerProtection.error("Error on operation: \(error.localizedDescription, privacy: .public)")
    }

}
