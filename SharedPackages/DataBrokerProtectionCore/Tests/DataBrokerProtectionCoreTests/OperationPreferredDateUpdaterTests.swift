//
//  OperationPreferredDateUpdaterTests.swift
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

import XCTest
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class OperationPreferredDateUpdaterTests: XCTestCase {

    private let databaseMock = MockDatabase()
    private let disabledFeatureFlagger = DisabledOptOutRetryErrorFeatureFlagger()

    override func tearDown() {
        databaseMock.clear()
    }

    func testWhenParentBrokerHasChildSites_thenThoseSitesScanPreferredRunDateIsUpdatedWithConfirm() {
        let sut = OperationPreferredDateUpdater(database: databaseMock, featureFlagger: disabledFeatureFlagger)
        let confirmOptOutScanHours = 48
        let profileQueryId: Int64 = 11
        let expectedDate = Date().addingTimeInterval(confirmOptOutScanHours.hoursToSeconds)
        let childBroker = DataBroker(
            id: 1,
            name: "Child broker",
            url: "childbroker.com",
            steps: [Step](),
            version: "1.0",
            schedulingConfig: DataBrokerScheduleConfig(
                retryError: 1,
                confirmOptOutScan: confirmOptOutScanHours,
                maintenanceScan: 1,
                maxAttempts: -1
            ),
            optOutUrl: "",
            eTag: "",
            removedAt: nil
        )
        databaseMock.childBrokers = [childBroker]

        XCTAssertNoThrow(try sut.updateChildrenBrokerForParentBroker(.mock, profileQueryId: profileQueryId))

        XCTAssertTrue(databaseMock.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertEqual(databaseMock.lastParentBrokerWhereChildSitesWhereFetched, "Test broker")
        XCTAssertEqual(databaseMock.lastProfileQueryIdOnScanUpdatePreferredRunDate, profileQueryId)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: expectedDate, date2: databaseMock.lastPreferredRunDateOnScan))
    }

    func testWhenParentBrokerHasNoChildsites_thenNoCallsToTheDatabaseAreDone() {
        let sut = OperationPreferredDateUpdater(database: databaseMock, featureFlagger: disabledFeatureFlagger)

        XCTAssertNoThrow(try sut.updateChildrenBrokerForParentBroker(.mock, profileQueryId: 1))

        XCTAssertFalse(databaseMock.wasDatabaseCalled)
    }

    func testWhenOptOutSubmitted_thenSubmittedSuccessfullyDateIsUpdated() {
        // Given
        let extractedProfileId: Int64 = 1
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 11
        let createdDate = Date()
        let submittedDate = Date()

        let lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested, date: submittedDate)
        databaseMock.lastHistoryEventToReturn = lastHistoryEventToReturn

        let scanJobData = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, historyEvents: [lastHistoryEventToReturn])
        let optOutJobData = OptOutJobData(brokerId: brokerId, profileQueryId: profileQueryId, createdDate: createdDate, historyEvents: [lastHistoryEventToReturn], attemptCount: 0, extractedProfile: .mockWithoutRemovedDate)
        databaseMock.brokerProfileQueryDataToReturn = [
            BrokerProfileQueryData(dataBroker: .mock, profileQuery: .mock, scanJobData: scanJobData, optOutJobData: [optOutJobData])
        ]
        let sut = OperationPreferredDateUpdater(database: databaseMock, featureFlagger: disabledFeatureFlagger)

        // When
        XCTAssertNoThrow(try sut.updateOperationDataDates(origin: .optOut, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: DataBrokerScheduleConfig.mock))

        // Then
        XCTAssertTrue(databaseMock.wasUpdateSubmittedSuccessfullyDateForOptOutCalled)
        let date = databaseMock.submittedSuccessfullyDate!
        XCTAssertTrue(date >= submittedDate)
    }

    func testWhenSubittedSuccessfullyDateIsAlreadySaved_thenSubittedSuccessfullyDateDoesNotChange() {
        // Given
        let extractedProfileId: Int64 = 1
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 11
        let createdDate = Date()
        let submittedDate = Date()

        let lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested, date: submittedDate)
        databaseMock.lastHistoryEventToReturn = lastHistoryEventToReturn

        let scanJobData = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, historyEvents: [lastHistoryEventToReturn])
        let optOutJobData = OptOutJobData(brokerId: brokerId, profileQueryId: profileQueryId, createdDate: createdDate, historyEvents: [lastHistoryEventToReturn], attemptCount: 0, submittedSuccessfullyDate: submittedDate, extractedProfile: .mockWithoutRemovedDate)
        databaseMock.brokerProfileQueryDataToReturn = [
            BrokerProfileQueryData(dataBroker: .mock, profileQuery: .mock, scanJobData: scanJobData, optOutJobData: [optOutJobData])
        ]
        let sut = OperationPreferredDateUpdater(database: databaseMock, featureFlagger: disabledFeatureFlagger)

        // When
        XCTAssertNoThrow(try sut.updateOperationDataDates(origin: .optOut, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: DataBrokerScheduleConfig.mock))

        // Then
        XCTAssertFalse(databaseMock.wasUpdateSubmittedSuccessfullyDateForOptOutCalled)
    }

    func testWhenOptOutRetryErrorFeatureIsOff_thenOptOutErrorRetryUsesSchedulingConfig() throws {
        let extractedProfileId: Int64 = 1
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 11
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 48, confirmOptOutScan: 72, maintenanceScan: 120, maxAttempts: -1)
        databaseMock.brokerProfileQueryDataToReturn = [
            makeBrokerProfileQueryDataWithErrorOptOut(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
        ]
        let sut = OperationPreferredDateUpdater(database: databaseMock, featureFlagger: MockDBPFeatureFlagger(isOptOutRetryErrorFrequencyExperimentOn: false))

        try sut.updateOperationDataDates(origin: .optOut,
                                         brokerId: brokerId,
                                         profileQueryId: profileQueryId,
                                         extractedProfileId: extractedProfileId,
                                         schedulingConfig: schedulingConfig)

        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: Date().addingTimeInterval(schedulingConfig.retryError.hoursToSeconds),
                                                   date2: databaseMock.lastPreferredRunDateOnOptOut))
    }

    func testWhenOptOutRetryErrorFeatureIsOn_thenOptOutErrorRetryUsesFeatureOverride() throws {
        let extractedProfileId: Int64 = 1
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 11
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 48, confirmOptOutScan: 72, maintenanceScan: 120, maxAttempts: -1)
        databaseMock.brokerProfileQueryDataToReturn = [
            makeBrokerProfileQueryDataWithErrorOptOut(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
        ]
        let sut = OperationPreferredDateUpdater(database: databaseMock, featureFlagger: MockDBPFeatureFlagger(isOptOutRetryErrorFrequencyExperimentOn: true))

        try sut.updateOperationDataDates(origin: .optOut,
                                         brokerId: brokerId,
                                         profileQueryId: profileQueryId,
                                         extractedProfileId: extractedProfileId,
                                         schedulingConfig: schedulingConfig)

        let defaultRetryDate = Date().addingTimeInterval(schedulingConfig.retryError.hoursToSeconds)
        let preferredRunDate = try XCTUnwrap(databaseMock.lastPreferredRunDateOnOptOut)
        XCTAssertGreaterThan(preferredRunDate, defaultRetryDate)
    }

    func testWhenOptOutRetryErrorFeatureIsOnForScanOrigin_thenOptOutErrorRetryUsesSchedulingConfig() throws {
        let extractedProfileId: Int64 = 1
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 11
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 48, confirmOptOutScan: 72, maintenanceScan: 120, maxAttempts: -1)
        databaseMock.brokerProfileQueryDataToReturn = [
            makeBrokerProfileQueryDataWithErrorOptOut(brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId)
        ]
        let sut = OperationPreferredDateUpdater(database: databaseMock, featureFlagger: MockDBPFeatureFlagger(isOptOutRetryErrorFrequencyExperimentOn: true))

        try sut.updateOperationDataDates(origin: .scan,
                                         brokerId: brokerId,
                                         profileQueryId: profileQueryId,
                                         extractedProfileId: extractedProfileId,
                                         schedulingConfig: schedulingConfig)

        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: Date().addingTimeInterval(schedulingConfig.retryError.hoursToSeconds),
                                                   date2: databaseMock.lastPreferredRunDateOnOptOut))
    }

    // MARK: - PreferredRunDateNilMigration

    private func makeIsolatedSettings() -> DataBrokerProtectionSettings {
        DataBrokerProtectionSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    func testWhenPreferredRunDateMigrationAlreadyCompleted_thenDatabaseIsNotQueried() {
        let settings = makeIsolatedSettings()
        settings.hasPerformedPreferredRunDateMigration = true
        let sut = OperationPreferredDateUpdater(database: databaseMock, featureFlagger: disabledFeatureFlagger)

        sut.runPreferredRunDateNilMigrationIfNeeded(settings: settings)

        XCTAssertFalse(databaseMock.wasFetchAllBrokerProfileQueryDataCalled)
    }

    func testWhenPreferredRunDateMigrationRunsWithScanNilPreferredRunDate_thenScanIsUpdatedAndFlagSet() {
        let settings = makeIsolatedSettings()
        let scanJobData = ScanJobData(brokerId: 1, profileQueryId: 1, preferredRunDate: nil, historyEvents: [])
        let queryData = BrokerProfileQueryData(dataBroker: .mock, profileQuery: .mock, scanJobData: scanJobData, optOutJobData: [])
        databaseMock.brokerProfileQueryDataToReturn = [queryData]
        let sut = OperationPreferredDateUpdater(database: databaseMock, featureFlagger: disabledFeatureFlagger)

        sut.runPreferredRunDateNilMigrationIfNeeded(settings: settings)

        XCTAssertTrue(databaseMock.wasFetchAllBrokerProfileQueryDataCalled)
        XCTAssertTrue(databaseMock.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertTrue(settings.hasPerformedPreferredRunDateMigration)
    }

    func testWhenPreferredRunDateMigrationRunsWithOptOutNilPreferredRunDate_thenOptOutIsUpdatedAndFlagSet() {
        let settings = makeIsolatedSettings()
        let optOutJobData = BrokerProfileQueryData.createOptOutJobData(extractedProfileId: 1, brokerId: 1, profileQueryId: 1, preferredRunDate: nil)
        let scanJobData = ScanJobData(brokerId: 1, profileQueryId: 1, preferredRunDate: Date(), historyEvents: [])
        let queryData = BrokerProfileQueryData(dataBroker: .mock, profileQuery: .mock, scanJobData: scanJobData, optOutJobData: [optOutJobData])
        databaseMock.brokerProfileQueryDataToReturn = [queryData]
        let sut = OperationPreferredDateUpdater(database: databaseMock, featureFlagger: disabledFeatureFlagger)

        sut.runPreferredRunDateNilMigrationIfNeeded(settings: settings)

        XCTAssertTrue(databaseMock.wasFetchAllBrokerProfileQueryDataCalled)
        XCTAssertTrue(databaseMock.wasUpdatedPreferredRunDateForOptOutCalled)
        XCTAssertTrue(settings.hasPerformedPreferredRunDateMigration)
    }

    // MARK: - History-event ordering (regression: #4269 iOS / #4270 & #4283 macOS)

    /// The preferred-date calculator keys the next run date off the *last* history event, so events
    /// must be sorted earliest-first before being handed to it. If they are passed in raw (unsorted)
    /// order, an earlier `.error` event that happens to sit last in the array is mistaken for the most
    /// recent event and a much sooner (wrong) run date is scheduled. Reverting the sort makes this fail.
    func testWhenOptOutHistoryEventsAreOutOfOrder_thenPreferredRunDateReflectsChronologicallyLatestEvent() throws {
        // Given
        let extractedProfileId: Int64 = 1
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 11
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 48, confirmOptOutScan: 72, maintenanceScan: 120, maxAttempts: -1)

        // The chronologically-latest event is `.optOutRequested`; an earlier event is an `.error`.
        // They are stored out of order (latest first) so the raw array's `.last` is the earlier error.
        let latestRequestedEvent = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested, date: Date())
        let earlierErrorEvent = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .error(error: .unknown("error")), date: Date().addingTimeInterval(-10_000))

        let scanJobData = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, historyEvents: [])
        let optOutJobData = OptOutJobData(brokerId: brokerId,
                                          profileQueryId: profileQueryId,
                                          createdDate: Date(),
                                          historyEvents: [latestRequestedEvent, earlierErrorEvent],
                                          attemptCount: 0,
                                          extractedProfile: .mockWithoutRemovedDate)
        databaseMock.brokerProfileQueryDataToReturn = [
            BrokerProfileQueryData(dataBroker: .mock, profileQuery: .mock, scanJobData: scanJobData, optOutJobData: [optOutJobData])
        ]
        let sut = OperationPreferredDateUpdater(database: databaseMock, featureFlagger: disabledFeatureFlagger)

        // When
        try sut.updateOperationDataDates(origin: .optOut,
                                         brokerId: brokerId,
                                         profileQueryId: profileQueryId,
                                         extractedProfileId: extractedProfileId,
                                         schedulingConfig: schedulingConfig)

        // Then
        // Sorted → last event is `.optOutRequested` → run date is now + hoursUntilNextOptOutAttempt (== maintenanceScan, 120h).
        let expectedSortedDate = Date().addingTimeInterval(schedulingConfig.maintenanceScan.hoursToSeconds)
        // Unsorted (bug) → last event is the earlier `.error` (single past try) → run date would be now + 2h.
        let buggyErrorDate = Date().addingTimeInterval(2.hoursToSeconds)

        let actual = try XCTUnwrap(databaseMock.lastPreferredRunDateOnOptOut)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: expectedSortedDate, date2: actual),
                      "Opt-out run date should be derived from the chronologically-latest (.optOutRequested) event")
        XCTAssertFalse(areDatesEqualIgnoringSeconds(date1: buggyErrorDate, date2: actual),
                       "Run date must not be derived from the earlier .error event — events were not sorted")
    }

    func testOptOutJobDataHistoryEventsSortedEarliestFirst_returnsEventsInChronologicalOrder() {
        let base = Date()
        let events = [
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: base.addingTimeInterval(300)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: base.addingTimeInterval(100)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: base.addingTimeInterval(200))
        ]
        let optOut = OptOutJobData(brokerId: 1, profileQueryId: 1, createdDate: base, historyEvents: events, attemptCount: 0, extractedProfile: .mockWithoutRemovedDate)

        let sortedDates = optOut.historyEventsSortedEarliestFirst.map(\.date)

        XCTAssertEqual(sortedDates, [base.addingTimeInterval(100), base.addingTimeInterval(200), base.addingTimeInterval(300)])
    }

    func testBrokerProfileQueryDataHistorySortHelpers_returnEventsInChronologicalOrder() {
        let base = Date()
        let scanEvents = [
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: base.addingTimeInterval(200)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: base.addingTimeInterval(50))
        ]
        let optOutEvents = [
            HistoryEvent(extractedProfileId: 1, brokerId: 1, profileQueryId: 1, type: .optOutRequested, date: base.addingTimeInterval(400)),
            HistoryEvent(extractedProfileId: 1, brokerId: 1, profileQueryId: 1, type: .error(error: .unknown("error")), date: base.addingTimeInterval(100))
        ]
        let scanJobData = ScanJobData(brokerId: 1, profileQueryId: 1, historyEvents: scanEvents)
        let optOutJobData = OptOutJobData(brokerId: 1, profileQueryId: 1, createdDate: base, historyEvents: optOutEvents, attemptCount: 0, extractedProfile: .mockWithoutRemovedDate)
        let queryData = BrokerProfileQueryData(dataBroker: .mock, profileQuery: .mock, scanJobData: scanJobData, optOutJobData: [optOutJobData])

        XCTAssertEqual(queryData.scanJobDataHistoryEventsSortedEarliestFirst.map(\.date),
                       [base.addingTimeInterval(50), base.addingTimeInterval(200)])
        XCTAssertEqual(queryData.optOutJobDataHistoryEventsSortedWithinOptOutEarliestFirst.map { $0.map(\.date) },
                       [[base.addingTimeInterval(100), base.addingTimeInterval(400)]])
    }

    private func makeBrokerProfileQueryDataWithErrorOptOut(brokerId: Int64,
                                                           profileQueryId: Int64,
                                                           extractedProfileId: Int64) -> BrokerProfileQueryData {
        let errorEvents = (0..<7).map { offset in
            HistoryEvent(extractedProfileId: extractedProfileId,
                         brokerId: brokerId,
                         profileQueryId: profileQueryId,
                         type: .error(error: .unknown("error")),
                         date: Date().addingTimeInterval(TimeInterval(offset)))
        }
        let scanJobData = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, historyEvents: [])
        let optOutJobData = OptOutJobData(brokerId: brokerId,
                                          profileQueryId: profileQueryId,
                                          createdDate: Date(),
                                          historyEvents: errorEvents,
                                          attemptCount: 0,
                                          extractedProfile: .mockWithoutRemovedDate)

        return BrokerProfileQueryData(dataBroker: .mock,
                                      profileQuery: .mock,
                                      scanJobData: scanJobData,
                                      optOutJobData: [optOutJobData])
    }
}
