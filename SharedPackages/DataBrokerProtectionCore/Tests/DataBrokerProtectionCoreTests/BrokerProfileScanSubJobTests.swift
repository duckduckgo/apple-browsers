//
//  BrokerProfileScanSubJobTests.swift
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

import XCTest
import BrowserServicesKit
import Common
import PixelKit
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class BrokerProfileScanSubJobTests: XCTestCase {
    var sut: BrokerProfileScanSubJob!

    var mockScanRunner: MockScanSubJobWebRunner!
    var mockOptOutRunner: MockOptOutSubJobWebRunner!
    var mockDatabase: MockDatabase!
    var mockEventsHandler: MockOperationEventsHandler!
    var mockDependencies: MockBrokerProfileJobDependencies!

    override func setUp() {
        super.setUp()
        mockScanRunner = MockScanSubJobWebRunner()
        mockOptOutRunner = MockOptOutSubJobWebRunner()
        mockDatabase = MockDatabase()
        mockEventsHandler = MockOperationEventsHandler()

        mockDependencies = MockBrokerProfileJobDependencies()
        mockDependencies.mockScanRunner = self.mockScanRunner
        mockDependencies.mockOptOutRunner = self.mockOptOutRunner
        mockDependencies.database = self.mockDatabase
        mockDependencies.eventsHandler = self.mockEventsHandler

        sut = BrokerProfileScanSubJob(dependencies: mockDependencies)
    }

    // MARK: - Notification tests

    func testWhenOnlyOneProfileIsFoundAndRemoved_thenAllInfoRemovedNotificationIsSent() async {
        do {
            let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

            let brokerId: Int64 = 1
            let profileQueryId: Int64 = 1
            let extractedProfileId: Int64 = 1
            let currentPreferredRunDate = Date()

            let mockDataBroker = DataBroker(name: "databroker",
                                            url: "databroker.com",
                                            steps: [Step](),
                                            version: "1.0",
                                            schedulingConfig: config,
                                            optOutUrl: "",
                                            eTag: "",
                                            removedAt: nil)
            let mockProfileQuery = ProfileQuery(id: profileQueryId, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1222)

            let historyEvents = [HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)]
            let mockScanOperation = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: currentPreferredRunDate, historyEvents: historyEvents)

            let extractedProfileSaved = ExtractedProfile(id: 1, name: "Some name", profileUrl: "abc")

            let optOutData = [OptOutJobData.mock(with: extractedProfileSaved)]

            let mockBrokerProfileQuery = BrokerProfileQueryData(dataBroker: mockDataBroker,
                                                                profileQuery: mockProfileQuery,
                                                                scanJobData: mockScanOperation,
                                                                optOutJobData: optOutData)
            mockDatabase.brokerProfileQueryDataToReturn = [mockBrokerProfileQuery]

            mockScanRunner.scanResults = []
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: extractedProfileSaved)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockEventsHandler.allProfilesRemovedFired)
            XCTAssertFalse(mockEventsHandler.firstProfileRemovedFired)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenManyProfilesAreFoundAndOnlyOneRemoved_thenFirstRemovedNotificationIsSent() async {
        do {

            let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

            let brokerId: Int64 = 1
            let profileQueryId: Int64 = 1
            let extractedProfileId: Int64 = 1
            let currentPreferredRunDate = Date()

            let mockDataBroker = DataBroker(name: "databroker",
                                            url: "databroker.com",
                                            steps: [Step](),
                                            version: "1.0",
                                            schedulingConfig: config,
                                            optOutUrl: "",
                                            eTag: "",
                                            removedAt: nil)
            let mockProfileQuery = ProfileQuery(id: profileQueryId, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1222)

            let historyEvents = [HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)]
            let mockScanOperation = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: currentPreferredRunDate, historyEvents: historyEvents)

            let extractedProfileSaved1 = ExtractedProfile(id: 1, name: "Some name", profileUrl: "abc", identifier: "abc")
            let extractedProfileSaved2 = ExtractedProfile(id: 1, name: "Some name", profileUrl: "zxz", identifier: "zxz")

            let optOutData = [OptOutJobData.mock(with: extractedProfileSaved1),
                              OptOutJobData.mock(with: extractedProfileSaved2)]

            let mockBrokerProfileQuery = BrokerProfileQueryData(dataBroker: mockDataBroker,
                                                                profileQuery: mockProfileQuery,
                                                                scanJobData: mockScanOperation,
                                                                optOutJobData: optOutData)
            mockDatabase.brokerProfileQueryDataToReturn = [mockBrokerProfileQuery]

            mockScanRunner.scanResults = [extractedProfileSaved1]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: extractedProfileSaved1),
                                    OptOutJobData.mock(with: extractedProfileSaved2)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertFalse(mockEventsHandler.allProfilesRemovedFired)
            XCTAssertTrue(mockEventsHandler.firstProfileRemovedFired)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenNoProfilesAreRemoved_thenNoNotificationsAreSent() async {
        do {

            let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

            let brokerId: Int64 = 1
            let profileQueryId: Int64 = 1
            let extractedProfileId: Int64 = 1
            let currentPreferredRunDate = Date()

            let mockDataBroker = DataBroker(name: "databroker",
                                            url: "databroker.com",
                                            steps: [Step](),
                                            version: "1.0",
                                            schedulingConfig: config,
                                            optOutUrl: "",
                                            eTag: "",
                                            removedAt: nil)
            let mockProfileQuery = ProfileQuery(id: profileQueryId, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1222)

            let historyEvents = [HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)]
            let mockScanOperation = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: currentPreferredRunDate, historyEvents: historyEvents)

            let extractedProfileSaved1 = ExtractedProfile(id: 1, name: "Some name", profileUrl: "abc")
            let extractedProfileSaved2 = ExtractedProfile(id: 1, name: "Some name", profileUrl: "zxz")

            let optOutData = [OptOutJobData.mock(with: extractedProfileSaved1),
                              OptOutJobData.mock(with: extractedProfileSaved2)]

            let mockBrokerProfileQuery = BrokerProfileQueryData(dataBroker: mockDataBroker,
                                                                profileQuery: mockProfileQuery,
                                                                scanJobData: mockScanOperation,
                                                                optOutJobData: optOutData)
            mockDatabase.brokerProfileQueryDataToReturn = [mockBrokerProfileQuery]

            mockScanRunner.scanResults = [extractedProfileSaved1, extractedProfileSaved2]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: extractedProfileSaved1),
                                    OptOutJobData.mock(with: extractedProfileSaved2)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertFalse(mockEventsHandler.allProfilesRemovedFired)
            XCTAssertFalse(mockEventsHandler.firstProfileRemovedFired)
        } catch {
            XCTFail("Should not throw")
        }
    }

    // MARK: - Run scan operation tests

    func testWhenProfileQueryIdIsNil_thenRunScanThrows() async {
        do {
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mockWithoutId,
                    scanJobData: .mock
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTFail("Scan should fail when brokerProfileQueryData has no id profile query")
        } catch {
            XCTAssertEqual(error as? BrokerProfileSubJobError, BrokerProfileSubJobError.idsMissingForBrokerOrProfileQuery)
            XCTAssertFalse(mockScanRunner.wasScanCalled)
        }
    }

    func testWhenBrokerIdIsNil_thenRunScanThrows() async {
        do {
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mockWithoutId,
                    profileQuery: .mock,
                    scanJobData: .mock
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTFail("Scan should fail when brokerProfileQueryData has no id for broker")
        } catch {
            XCTAssertEqual(error as? BrokerProfileSubJobError, BrokerProfileSubJobError.idsMissingForBrokerOrProfileQuery)
        }
    }

    func testWhenScanStarts_thenScanStartedEventIsAddedToTheDatabase() async {
        do {
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertEqual(mockDatabase.scanEvents.first?.type, .scanStarted)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenScanDoesNotFoundProfiles_thenNoMatchFoundEventIsAddedToTheDatabase() async {
        do {
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.scanEvents.contains(where: { $0.type == .noMatchFound }))
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenScannedProfileIsAlreadyInTheDatabase_noOptOutOperationIsCreated() async {
        do {
            mockDatabase.extractedProfilesFromBroker = [.mockWithoutRemovedDate]
            mockScanRunner.scanResults = [.mockWithoutRemovedDate]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertFalse(mockDatabase.wasUpdateRemoveDateCalled)
            XCTAssertNil(mockDatabase.extractedProfileRemovedDate)
            XCTAssertFalse(mockDatabase.wasSaveOptOutOperationCalled)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenScannedProfileIsAlreadyInTheDatabaseAndWasRemoved_thenTheRemovedDateIsSetBackToNil() async {
        do {
            mockDatabase.extractedProfilesFromBroker = [.mockWithRemovedDate]
            mockScanRunner.scanResults = [.mockWithRemovedDate]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.wasUpdateRemoveDateCalled)
            XCTAssertNil(mockDatabase.extractedProfileRemovedDate)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenScannedProfileIsAlreadyInTheDatabaseAndWasNotFoundInBroker_thenTheRemovedDateIsSet() async {
        do {
            mockScanRunner.scanResults = []
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.wasUpdateRemoveDateCalled)
            XCTAssertNotNil(mockDatabase.extractedProfileRemovedDate)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenNewExtractedProfileIsNotInDatabase_thenIsAddedToTheDatabaseAndOptOutOperationIsCreated() async {
        do {
            mockScanRunner.scanResults = [.mockWithoutId]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.wasSaveOptOutOperationCalled)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenRemovedProfileIsFound_thenOptOutConfirmedIsAddedRemoveDateIsUpdated() async {
        do {
            mockScanRunner.scanResults = [.mockWithoutId]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.optOutEvents.contains(where: { $0.type == .optOutConfirmed }))
            XCTAssertTrue(mockDatabase.wasUpdateRemoveDateCalled)
            XCTAssertNotNil(mockDatabase.extractedProfileRemovedDate)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenNoRemovedProfilesAreFound_thenNoOtherEventIsAdded() async {
        do {
            mockScanRunner.scanResults = [.mockWithoutRemovedDate]
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTAssertFalse(mockDatabase.optOutEvents.contains(where: { $0.type == .optOutConfirmed }))
            XCTAssertFalse(mockDatabase.wasUpdateRemoveDateCalled)
            XCTAssertNil(mockDatabase.extractedProfileRemovedDate)
            XCTAssertFalse(mockDatabase.wasUpdatedPreferredRunDateForOptOutCalled)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenErrorIsCaught_thenEventIsAddedToTheDatabase() async {
        do {
            mockScanRunner.shouldScanThrow = true
            _ = try await sut.runScan(
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                showWebView: false,
                isManual: false,
                shouldRunNextStep: { true }
            )
            XCTFail("Should throw!")
        } catch {
            XCTAssertTrue(mockDatabase.wasAddHistoryEventCalled)
            XCTAssertTrue(mockDatabase.scanEvents.contains(where: { $0.type == .error(error: .unknown("Test error")) }))
            XCTAssertFalse(mockDatabase.scanEvents.contains(where: { $0.type == .matchesFound(count: 1) }))
            XCTAssertFalse(mockDatabase.scanEvents.contains(where: { $0.type == .noMatchFound }))
            XCTAssertFalse(mockDatabase.wasSaveOptOutOperationCalled)
        }
    }

    func testWhenUpdatingDatesOnOptOutAndLastEventIsError_thenWeSetPreferredRunDateWithRetryErrorDate() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .error(error: .unknown("Test error")))
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 1, confirmOptOutScan: 0, maintenanceScan: 0, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForOptOutCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnOptOut, date2: Date().addingTimeInterval(schedulingConfig.retryError.hoursToSeconds)))
    }

    func testWhenUpdatingDatesOnScanAndLastEventIsError_thenWeSetPreferredRunDateWithRetryErrorDate() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: nil, brokerId: brokerId, profileQueryId: profileQueryId, type: .error(error: .unknown("Test error")))
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 1, confirmOptOutScan: 0, maintenanceScan: 0, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: nil, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnScan, date2: Date().addingTimeInterval(schedulingConfig.retryError.hoursToSeconds)))
    }

    func testWhenUpdatingDatesAndLastEventIsOptOutRequested_thenWeSetScanPreferredRunDateWithConfirmOptOutDate() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 0, confirmOptOutScan: 1, maintenanceScan: 0, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnScan, date2: Date().addingTimeInterval(schedulingConfig.confirmOptOutScan.hoursToSeconds)))
    }

    func testWhenUpdatingDatesAndLastEventIsOptOutRequested_thenWeSetOptOutPreferredRunDateToOptOutReattempt() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 0, confirmOptOutScan: 1, maintenanceScan: 0, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnOptOut, date2: Date().addingTimeInterval(schedulingConfig.hoursUntilNextOptOutAttempt.hoursToSeconds)))
    }

    func testWhenUpdatingDatesAndLastEventIsMatchesFound_thenWeSetScanPreferredDateToMaintenance() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .matchesFound(count: 0))
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 0, confirmOptOutScan: 0, maintenanceScan: 1, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnScan, date2: Date().addingTimeInterval(schedulingConfig.maintenanceScan.hoursToSeconds)))
    }

    func testWhenUpdatingDatesAndLastEventIsOptOutStarted_thenNothingHappens() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutStarted)
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 0, confirmOptOutScan: 0, maintenanceScan: 1, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertFalse(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertFalse(mockDatabase.wasUpdatedPreferredRunDateForOptOutCalled)
        XCTAssertNil(mockDatabase.lastPreferredRunDateOnScan)
        XCTAssertNil(mockDatabase.lastPreferredRunDateOnOptOut)
    }

    func testWhenUpdatingDatesAndLastEventIsScanStarted_thenNothingHappens() throws {
        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        mockDatabase.lastHistoryEventToReturn = HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .scanStarted)
        let schedulingConfig = DataBrokerScheduleConfig(retryError: 0, confirmOptOutScan: 0, maintenanceScan: 1, maxAttempts: -1)

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: schedulingConfig, database: mockDatabase)

        XCTAssertFalse(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertFalse(mockDatabase.wasUpdatedPreferredRunDateForOptOutCalled)
        XCTAssertNil(mockDatabase.lastPreferredRunDateOnScan)
        XCTAssertNil(mockDatabase.lastPreferredRunDateOnOptOut)
    }

    func testUpdatingScanDateFromOptOut_thenScanRespectMostRecentDate() throws {
        let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        let currentPreferredRunDate = Date()

        let mockDataBroker = DataBroker(name: "databroker",
                                        url: "databroker.com",
                                        steps: [Step](),
                                        version: "1.0",
                                        schedulingConfig: config,
                                        optOutUrl: "",
                                        eTag: "",
                                        removedAt: nil)
        let mockProfileQuery = ProfileQuery(id: profileQueryId, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1222)

        let historyEvents = [HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)]
        let mockScanOperation = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: currentPreferredRunDate, historyEvents: historyEvents)

        let mockBrokerProfileQuery = BrokerProfileQueryData(dataBroker: mockDataBroker, profileQuery: mockProfileQuery, scanJobData: mockScanOperation)
        mockDatabase.brokerProfileQueryDataToReturn = [mockBrokerProfileQuery]

        try sut.updateOperationDataDates(origin: .optOut, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: config, database: mockDatabase)

        // If the date is not going to be set, we don't call the database function
        XCTAssertFalse(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForOptOutCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnOptOut, date2: Date().addingTimeInterval(config.hoursUntilNextOptOutAttempt.hoursToSeconds)))
    }

    func testUpdatingScanDateFromScan_thenScanDoesNotRespectMostRecentDate() throws {
        let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        let currentPreferredRunDate = Date()
        let expectedPreferredRunDate = Date().addingTimeInterval(config.confirmOptOutScan.hoursToSeconds)

        let mockDataBroker = DataBroker(name: "databroker",
                                        url: "databroker.com",
                                        steps: [Step](),
                                        version: "1.0",
                                        schedulingConfig: config,
                                        optOutUrl: "",
                                        eTag: "",
                                        removedAt: nil)
        let mockProfileQuery = ProfileQuery(id: profileQueryId, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1222)

        let historyEvents = [HistoryEvent(extractedProfileId: extractedProfileId, brokerId: brokerId, profileQueryId: profileQueryId, type: .optOutRequested)]
        let mockScanOperation = ScanJobData(brokerId: brokerId, profileQueryId: profileQueryId, preferredRunDate: currentPreferredRunDate, historyEvents: historyEvents)

        let mockBrokerProfileQuery = BrokerProfileQueryData(dataBroker: mockDataBroker, profileQuery: mockProfileQuery, scanJobData: mockScanOperation)
        mockDatabase.brokerProfileQueryDataToReturn = [mockBrokerProfileQuery]

        try sut.updateOperationDataDates(origin: .scan, brokerId: brokerId, profileQueryId: profileQueryId, extractedProfileId: extractedProfileId, schedulingConfig: config, database: mockDatabase)

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForScanCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnScan, date2: expectedPreferredRunDate), "\(String(describing: mockDatabase.lastPreferredRunDateOnScan)) is not equal to \(expectedPreferredRunDate)")

        XCTAssertTrue(mockDatabase.wasUpdatedPreferredRunDateForOptOutCalled)
        XCTAssertTrue(areDatesEqualIgnoringSeconds(date1: mockDatabase.lastPreferredRunDateOnOptOut, date2: Date().addingTimeInterval(config.hoursUntilNextOptOutAttempt.hoursToSeconds)))
    }

    func testScanSubJob_whenExecutedSuccessfully_returnsTrue() async throws {
        // When
        let result = try await sut.runScan(
            brokerProfileQueryData: .init(
                dataBroker: .mock,
                profileQuery: .mock,
                scanJobData: .mock
            ),
            showWebView: false,
            isManual: false,
            shouldRunNextStep: { true }
        )

        // Then
        XCTAssertTrue(result)
    }

}
