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
import BrowserServicesKit
import PixelKit
import os.log

struct BrokerProfileScanSubJob {
    struct ScanIdentifiers {
        let brokerId: Int64
        let profileQueryId: Int64
    }

    struct ScanStageContext {
        let eventPixels: DataBrokerProtectionEventPixels
        let stageCalculator: DataBrokerProtectionStageDurationCalculator
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

    // MARK: - Scan Jobs

    /// Returns: `true` if the scan was executed, `false` if it was skipped
    public func runScan(brokerProfileQueryData: BrokerProfileQueryData,
                        showWebView: Bool,
                        isManual: Bool,
                        shouldRunNextStep: @escaping () -> Bool) async throws -> Bool {
        Logger.dataBrokerProtection.log("Running scan operation: \(brokerProfileQueryData.dataBroker.name, privacy: .public)")

        guard let identifiers = try validateScanPreconditions(brokerProfileQueryData: brokerProfileQueryData) else {
            return false
        }
        let brokerId = identifiers.brokerId
        let profileQueryId = identifiers.profileQueryId

        defer {
            reportScanCompletion(database: dependencies.database,
                                 notificationCenter: dependencies.notificationCenter,
                                 brokerProfileQueryData: brokerProfileQueryData,
                                 identifiers: identifiers)
        }

        let scanContext = createScanStageContext(brokerProfileQueryData: brokerProfileQueryData,
                                                 isManual: isManual,
                                                 database: dependencies.database,
                                                 pixelHandler: dependencies.pixelHandler,
                                                 parentURL: brokerProfileQueryData.dataBroker.parent,
                                                 vpnConnectionState: vpnConnectionState,
                                                 vpnBypassStatus: vpnBypassStatus)
        let eventPixels = scanContext.eventPixels
        let stageCalculator = scanContext.stageCalculator

        let metadata = ScanWideEventRecorder.Metadata(
            from: brokerProfileQueryData.scanJobData,
            referenceDate: stageCalculator.startTime
        )
        let scanWideEventRecorder = ScanWideEventRecorder.startIfPossible(
            wideEvent: dependencies.wideEvent,
            attemptID: stageCalculator.attemptId,
            dataBrokerURL: brokerProfileQueryData.dataBroker.url,
            dataBrokerVersion: brokerProfileQueryData.dataBroker.version,
            metadata: metadata
        )

        do {
            try markScanStarted(brokerId: brokerId,
                                profileQueryId: profileQueryId,
                                stageCalculator: stageCalculator,
                                database: dependencies.database)

            let runner = makeScanRunner(brokerProfileQueryData: brokerProfileQueryData,
                                        stageCalculator: stageCalculator,
                                        shouldRunNextStep: shouldRunNextStep,
                                        runnerFactory: dependencies.createScanRunner)

            let profilesFoundDuringCurrentScanJob = try await executeScan(runner: runner,
                                                                          brokerProfileQueryData: brokerProfileQueryData,
                                                                          showWebView: showWebView,
                                                                          shouldRunNextStep: shouldRunNextStep)

            Logger.dataBrokerProtection.log("OperationManager found profiles: \(profilesFoundDuringCurrentScanJob, privacy: .public)")

            if !profilesFoundDuringCurrentScanJob.isEmpty {
                try handleScanMatches(matches: profilesFoundDuringCurrentScanJob,
                                      brokerId: brokerId,
                                      profileQueryId: profileQueryId,
                                      brokerProfileQueryData: brokerProfileQueryData,
                                      database: dependencies.database,
                                      eventPixels: eventPixels,
                                      stageCalculator: stageCalculator,
                                      scheduleOptOuts: scheduleOptOutsForExtractedProfiles)
            } else {
                try handleScanWithNoMatches(brokerId: brokerId,
                                            profileQueryId: profileQueryId,
                                            database: dependencies.database,
                                            stageCalculator: stageCalculator,
                                            storeNoMatchesEvent: storeScanWithNoMatchesEvent)
            }

            let removedProfiles = detectRemovedProfiles(previouslyExtractedProfiles: brokerProfileQueryData.extractedProfiles,
                                                        currentScanProfiles: profilesFoundDuringCurrentScanJob)

            if !removedProfiles.isEmpty {
                try handleRemovedProfiles(removedProfiles: removedProfiles,
                                          brokerId: brokerId,
                                          profileQueryId: profileQueryId,
                                          brokerProfileQueryData: brokerProfileQueryData,
                                          database: dependencies.database,
                                          pixelHandler: dependencies.pixelHandler,
                                          eventsHandler: dependencies.eventsHandler,
                                          markRemovedAndNotify: markSavedProfilesAsRemovedAndNotifyUser)
            } else {
                try updateDatesAfterNoRemovals(brokerId: brokerId,
                                               profileQueryId: profileQueryId,
                                               brokerProfileQueryData: brokerProfileQueryData,
                                               database: dependencies.database,
                                               updateOperationDates: updateOperationDataDates)
            }
        } catch {
            throw handleScanFailure(error: error,
                                    brokerId: brokerId,
                                    profileQueryId: profileQueryId,
                                    brokerProfileQueryData: brokerProfileQueryData,
                                    stageCalculator: stageCalculator,
                                    database: dependencies.database,
                                    schedulingConfig: brokerProfileQueryData.dataBroker.schedulingConfig,
                                    scanWideEventRecorder: scanWideEventRecorder,
                                    handleError: handleOperationError)
        }

        scanWideEventRecorder?.complete(status: .success, endDate: Date(), error: nil)

        return true
    }

    internal func validateScanPreconditions(brokerProfileQueryData: BrokerProfileQueryData) throws -> ScanIdentifiers? {
        // 1. Validate that the broker and profile query data objects each have an ID:
        guard let brokerId = brokerProfileQueryData.dataBroker.id,
              let profileQueryId = brokerProfileQueryData.profileQuery.id else {
            throw BrokerProfileSubJobError.idsMissingForBrokerOrProfileQuery
        }

        return ScanIdentifiers(brokerId: brokerId, profileQueryId: profileQueryId)
    }

    internal func reportScanCompletion(database: DataBrokerProtectionRepository,
                                       notificationCenter: NotificationCenter,
                                       brokerProfileQueryData: BrokerProfileQueryData,
                                       identifiers: ScanIdentifiers) {
        try? database.updateLastRunDate(Date(),
                                        brokerId: identifiers.brokerId,
                                        profileQueryId: identifiers.profileQueryId)
        notificationCenter.post(name: DataBrokerProtectionNotifications.didFinishScan,
                                object: brokerProfileQueryData.dataBroker.name)
        Logger.dataBrokerProtection.log("Finished scan operation: \(brokerProfileQueryData.dataBroker.name, privacy: .public)")
    }

    internal func createScanStageContext(brokerProfileQueryData: BrokerProfileQueryData,
                                         isManual: Bool,
                                         database: DataBrokerProtectionRepository,
                                         pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                                         parentURL: String?,
                                         vpnConnectionState: String,
                                         vpnBypassStatus: String) -> ScanStageContext {
        // 2. Set up dependencies used to report the status of the scan job:
        let eventPixels = DataBrokerProtectionEventPixels(database: database,
                                                          handler: pixelHandler)
        let stageCalculator = DataBrokerProtectionStageDurationCalculator(
            dataBrokerURL: brokerProfileQueryData.dataBroker.url,
            dataBrokerVersion: brokerProfileQueryData.dataBroker.version,
            handler: pixelHandler,
            isImmediateOperation: isManual,
            parentURL: parentURL,
            vpnConnectionState: vpnConnectionState,
            vpnBypassStatus: vpnBypassStatus
        )

        return ScanStageContext(eventPixels: eventPixels, stageCalculator: stageCalculator)
    }

    internal func markScanStarted(brokerId: Int64,
                                  profileQueryId: Int64,
                                  stageCalculator: DataBrokerProtectionStageDurationCalculator,
                                  database: DataBrokerProtectionRepository) throws {
        // 3. Record the start of the scan job:
        let event = HistoryEvent(brokerId: brokerId,
                                 profileQueryId: profileQueryId,
                                 type: .scanStarted)
        try database.add(event)

#if os(iOS)
        stageCalculator.fireScanStarted()
#endif
    }

    internal func makeScanRunner(brokerProfileQueryData: BrokerProfileQueryData,
                                 stageCalculator: StageDurationCalculator,
                                 shouldRunNextStep: @escaping () -> Bool,
                                 runnerFactory: (BrokerProfileQueryData,
                                                 StageDurationCalculator,
                                                 @escaping () -> Bool) -> BrokerProfileScanSubJobWebRunning) -> BrokerProfileScanSubJobWebRunning {
        // 4a. Create scan runner:
        runnerFactory(brokerProfileQueryData, stageCalculator, shouldRunNextStep)
    }

    internal func executeScan(runner: BrokerProfileScanSubJobWebRunning,
                              brokerProfileQueryData: BrokerProfileQueryData,
                              showWebView: Bool,
                              shouldRunNextStep: @escaping () -> Bool) async throws -> [ExtractedProfile] {
        // 4b. Get extracted profiles from the runner:
        try await runner.scan(brokerProfileQueryData,
                              showWebView: showWebView,
                              shouldRunNextStep: shouldRunNextStep)
    }

    internal func handleScanMatches(matches: [ExtractedProfile],
                                    brokerId: Int64,
                                    profileQueryId: Int64,
                                    brokerProfileQueryData: BrokerProfileQueryData,
                                    database: DataBrokerProtectionRepository,
                                    eventPixels: DataBrokerProtectionEventPixels,
                                    stageCalculator: DataBrokerProtectionStageDurationCalculator,
                                    scheduleOptOuts: ([ExtractedProfile],
                                                      BrokerProfileQueryData,
                                                      Int64,
                                                      Int64,
                                                      DataBrokerProtectionRepository,
                                                      DataBrokerProtectionEventPixels,
                                                      DataBrokerProtectionStageDurationCalculator) throws -> Void) throws {
        // 5a. Send observability signals to indicate that the scan found matches:
        stageCalculator.fireScanSuccess(matchesFound: matches.count)

        let event = HistoryEvent(brokerId: brokerId,
                                 profileQueryId: profileQueryId,
                                 type: .matchesFound(count: matches.count))
        try database.add(event)

        // 5b. Iterate over found profiles and process them:
        try scheduleOptOuts(matches,
                            brokerProfileQueryData,
                            brokerId,
                            profileQueryId,
                            database,
                            eventPixels,
                            stageCalculator)
    }

    internal func handleScanWithNoMatches(brokerId: Int64,
                                          profileQueryId: Int64,
                                          database: DataBrokerProtectionRepository,
                                          stageCalculator: DataBrokerProtectionStageDurationCalculator,
                                          storeNoMatchesEvent: (Int64,
                                                                Int64,
                                                                DataBrokerProtectionRepository,
                                                                DataBrokerProtectionStageDurationCalculator) throws -> Void) throws {
        // 5c. Report the status of the scan, which found no matches:
        try storeNoMatchesEvent(brokerId,
                                profileQueryId,
                                database,
                                stageCalculator)
    }

    internal func detectRemovedProfiles(previouslyExtractedProfiles: [ExtractedProfile],
                                        currentScanProfiles: [ExtractedProfile]) -> [ExtractedProfile] {
        // 6. Check for removed profiles by comparing the set of saved profiles to those just found via scan:
        previouslyExtractedProfiles.filter { savedProfile in
            !currentScanProfiles.contains { recentlyFoundProfile in
                recentlyFoundProfile.identifier == savedProfile.identifier
            }
        }
    }

    internal func handleRemovedProfiles(removedProfiles: [ExtractedProfile],
                                        brokerId: Int64,
                                        profileQueryId: Int64,
                                        brokerProfileQueryData: BrokerProfileQueryData,
                                        database: DataBrokerProtectionRepository,
                                        pixelHandler: EventMapping<DataBrokerProtectionSharedPixels>,
                                        eventsHandler: EventMapping<JobEvent>,
                                        markRemovedAndNotify: ([ExtractedProfile],
                                                               Int64,
                                                               Int64,
                                                               BrokerProfileQueryData,
                                                               DataBrokerProtectionRepository,
                                                               EventMapping<DataBrokerProtectionSharedPixels>,
                                                               EventMapping<JobEvent>) throws -> Void) throws {
        // 7a. If there were removed profiles, update their state and notify the user:
        try markRemovedAndNotify(removedProfiles,
                                 brokerId,
                                 profileQueryId,
                                 brokerProfileQueryData,
                                 database,
                                 pixelHandler,
                                 eventsHandler)
    }

    internal func updateDatesAfterNoRemovals(brokerId: Int64,
                                             profileQueryId: Int64,
                                             brokerProfileQueryData: BrokerProfileQueryData,
                                             database: DataBrokerProtectionRepository,
                                             updateOperationDates: (OperationPreferredDateUpdaterOrigin,
                                                                    Int64,
                                                                    Int64,
                                                                    Int64?,
                                                                    DataBrokerScheduleConfig,
                                                                    DataBrokerProtectionRepository) throws -> Void) throws {
        // 7b. If there were no removed profiles, update the date entries:
        try updateOperationDates(.scan,
                                 brokerId,
                                 profileQueryId,
                                 nil,
                                 brokerProfileQueryData.dataBroker.schedulingConfig,
                                 database)
    }

    internal func handleScanFailure(error: Error,
                                    brokerId: Int64,
                                    profileQueryId: Int64,
                                    brokerProfileQueryData: BrokerProfileQueryData,
                                    stageCalculator: DataBrokerProtectionStageDurationCalculator,
                                    database: DataBrokerProtectionRepository,
                                    schedulingConfig: DataBrokerScheduleConfig,
                                    scanWideEventRecorder: ScanWideEventRecorder?,
                                    handleError: (OperationPreferredDateUpdaterOrigin,
                                                  Int64,
                                                  Int64,
                                                  Int64?,
                                                  Error,
                                                  DataBrokerProtectionRepository,
                                                  DataBrokerScheduleConfig) -> Void) -> Error {
        // 8. Process errors returned by the scan job:
        stageCalculator.fireScanError(error: error)

        let wideEventCompletion = ScanWideEventData.completion(for: error)
        scanWideEventRecorder?.complete(status: wideEventCompletion.status, endDate: Date(), error: wideEventCompletion.error)

        handleError(.scan,
                    brokerId,
                    profileQueryId,
                    nil,
                    error,
                    database,
                    schedulingConfig)
        return error
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
        stageCalculator.fireScanNoResults()
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

                markConfirmationWideEventCompleted(
                    brokerProfileQueryData: brokerProfileQueryData,
                    database: database,
                    profileIdentifier: removedProfile.identifier,
                    brokerId: brokerId,
                    profileQueryId: profileQueryId,
                    extractedProfileId: extractedProfileId
                )

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
                    pixelHandler.fire(.optOutFinish(dataBroker: attempt.dataBroker,
                                                    attemptId: attemptUUID,
                                                    duration: calculateDurationSinceLastStage,
                                                    parent: brokerProfileQueryData.dataBroker.parent ?? ""))
                    pixelHandler.fire(.optOutSuccess(dataBroker: attempt.dataBroker,
                                                     attemptId: attemptUUID,
                                                     duration: calculateDurationSinceStart,
                                                     parent: brokerProfileQueryData.dataBroker.parent ?? "",
                                                     brokerType: brokerProfileQueryData.dataBroker.type,
                                                     vpnConnectionState: vpnConnectionState,
                                                     vpnBypassStatus: vpnBypassStatus))
                }
            }
        }

        if shouldSendProfileRemovedEvent {
            sendProfilesRemovedEventIfNecessary(eventsHandler: eventsHandler, database: database)
        }
    }

    private func markConfirmationWideEventCompleted(brokerProfileQueryData: BrokerProfileQueryData,
                                                    database: DataBrokerProtectionRepository,
                                                    profileIdentifier: String?,
                                                    brokerId: Int64,
                                                    profileQueryId: Int64,
                                                    extractedProfileId: Int64) {
        let recordFoundDate = RecordFoundDateResolver.resolve(repository: database,
                                                              brokerId: brokerId,
                                                              profileQueryId: profileQueryId,
                                                              extractedProfileId: extractedProfileId)
        let wideEventId = OptOutWideEventIdentifier(profileIdentifier: profileIdentifier,
                                                    brokerId: brokerId,
                                                    profileQueryId: profileQueryId,
                                                    extractedProfileId: extractedProfileId)
        OptOutConfirmationWideEventRecorder.startIfPossible(
            wideEvent: dependencies.wideEvent,
            identifier: wideEventId,
            dataBrokerURL: brokerProfileQueryData.dataBroker.url,
            dataBrokerVersion: brokerProfileQueryData.dataBroker.version,
            recordFoundDate: recordFoundDate
        )?.markCompleted(at: Date())
    }

    private func sendProfilesRemovedEventIfNecessary(eventsHandler: EventMapping<JobEvent>,
                                                     database: DataBrokerProtectionRepository) {

        // Jobs for removed brokers will already be prevented from being scheduled upstream
        guard let savedExtractedProfiles = try? database.fetchAllBrokerProfileQueryData(shouldFilterRemovedBrokers: false)
            .flatMap({ $0.extractedProfiles }),
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

extension ScanWideEventData {
    static func completion(for error: Error) -> (status: WideEventStatus, error: Error?) {
        if let dataBrokerError = error as? DataBrokerProtectionError {
            switch dataBrokerError {
            case .jobTimeout, .cancelled:
                return (.cancelled, error)
            case .httpError(let code) where code == 404:
                return (.success, nil)
            default:
                return (.failure, error)
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return (.cancelled, error)
        }

        return (.failure, error)
    }
}
