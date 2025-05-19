//
//  BrokerProfileOptOutSubJobTests.swift
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

final class BrokerProfileOptOutSubJobTests: XCTestCase {
    var sut: BrokerProfileOptOutSubJob!

    var mockScanRunner: MockScanSubJobWebRunner!
    var mockOptOutRunner: MockOptOutSubJobWebRunner!
    var mockDatabase: MockDatabase!
    var mockEventsHandler: MockOperationEventsHandler!
    var mockPixelHandler: MockPixelHandler!
    var mockDependencies: MockBrokerProfileJobDependencies!

    override func setUp() {
        super.setUp()
        mockScanRunner = MockScanSubJobWebRunner()
        mockOptOutRunner = MockOptOutSubJobWebRunner()
        mockDatabase = MockDatabase()
        mockEventsHandler = MockOperationEventsHandler()
        mockPixelHandler = MockPixelHandler()

        mockDependencies = MockBrokerProfileJobDependencies()
        mockDependencies.mockScanRunner = self.mockScanRunner
        mockDependencies.mockOptOutRunner = self.mockOptOutRunner
        mockDependencies.database = self.mockDatabase
        mockDependencies.eventsHandler = self.mockEventsHandler
        mockDependencies.pixelHandler = self.mockPixelHandler

        sut = BrokerProfileOptOutSubJob(dependencies: mockDependencies)
    }

    // MARK: - Run opt-out operation tests

    func testWhenNoBrokerIdIsPresent_thenOptOutOperationThrows() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithoutRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mockWithoutId,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithRemovedDate)]
                ),
                shouldRunNextStep: { true }
            )
            XCTFail("Scan should fail when brokerProfileQueryData has no id profile query")
        } catch {
            XCTAssertEqual(error as? BrokerProfileSubJobError, BrokerProfileSubJobError.idsMissingForBrokerOrProfileQuery)
            XCTAssertFalse(mockOptOutRunner.wasOptOutCalled)
        }
    }

    func testWhenNoProfileQueryIdIsPresent_thenOptOutOperationThrows() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithoutRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mockWithoutId,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithRemovedDate)]
                ),
                shouldRunNextStep: { true }
            )
            XCTFail("Scan should fail when brokerProfileQueryData has no id profile query")
        } catch {
            XCTAssertEqual(error as? BrokerProfileSubJobError, BrokerProfileSubJobError.idsMissingForBrokerOrProfileQuery)
            XCTAssertFalse(mockOptOutRunner.wasOptOutCalled)
        }
    }

    func testWhenNoExtractedProfileIdIsPresent_thenOptOutOperationThrows() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithoutId,
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutId)]
                ),
                shouldRunNextStep: { true }
            )
            XCTFail("Scan should fail when brokerProfileQueryData has no id profile query")
        } catch {
            XCTAssertEqual(error as? BrokerProfileSubJobError, BrokerProfileSubJobError.idsMissingForBrokerOrProfileQuery)
            XCTAssertFalse(mockOptOutRunner.wasOptOutCalled)
        }
    }

    func testWhenExtractedProfileHasRemovedDate_thenNothingHappens() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithRemovedDate)]
                ),
                shouldRunNextStep: { true }
            )
            XCTAssertFalse(mockDatabase.wasDatabaseCalled)
            XCTAssertFalse(mockOptOutRunner.wasOptOutCalled)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testWhenBrokerHasParentOptOut_thenNothingHappens() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mockWithParentOptOut,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithRemovedDate)]
                ),
                shouldRunNextStep: { true }
            )
            XCTAssertFalse(mockDatabase.wasDatabaseCalled)
            XCTAssertFalse(mockOptOutRunner.wasOptOutCalled)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testOptOutStartedEventIsAdded_whenExtractedProfileOptOutStarts() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithoutRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.optOutEvents.contains(where: { $0.type == .optOutStarted }))
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testOptOutRequestedEventIsAdded_whenExtractedProfileOptOutFinishesWithoutError() async {
        do {
            _ = try await sut.runOptOut(
                for: .mockWithoutRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                shouldRunNextStep: { true }
            )
            XCTAssertTrue(mockDatabase.optOutEvents.contains(where: { $0.type == .optOutRequested }))
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testErrorEventIsAdded_whenWebRunnerFails() async {
        do {
            mockOptOutRunner.shouldOptOutThrow = true
            _ = try await sut.runOptOut(
                for: .mockWithoutRemovedDate,
                brokerProfileQueryData: .init(
                    dataBroker: .mock,
                    profileQuery: .mock,
                    scanJobData: .mock,
                    optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
                ),
                shouldRunNextStep: { true }
            )
            XCTFail("Should throw!")
        } catch {
            XCTAssertTrue(mockDatabase.optOutEvents.contains(where: { $0.type == .optOutStarted }))
            XCTAssertFalse(mockDatabase.optOutEvents.contains(where: { $0.type == .optOutRequested }))
            XCTAssertTrue(mockDatabase.optOutEvents.contains(where: { $0.type == .error(error: DataBrokerProtectionError.unknown("Test error")) }))
        }
    }

    private func runOptOut(shouldThrow: Bool = false) async throws {
        mockOptOutRunner.shouldOptOutThrow = shouldThrow
        _ = try await sut.runOptOut(
            for: .mockWithoutRemovedDate,
            brokerProfileQueryData: .init(
                dataBroker: .mock,
                profileQuery: .mock,
                scanJobData: .mock,
                optOutJobData: [OptOutJobData.mock(with: .mockWithoutRemovedDate)]
            ),
            shouldRunNextStep: { true }
        )
    }

    func testCorrectNumberOfTriesIsFired_whenOptOutSucceeds() async {
        try? await runOptOut(shouldThrow: true)
        try? await runOptOut(shouldThrow: true)
        try? await runOptOut()

        if let lastPixelFired = mockPixelHandler.lastFiredEvent {
            switch lastPixelFired {
            case .optOutSubmitSuccess(_, _, _, let tries, _, _, _):
                XCTAssertEqual(tries, 3)
            default: XCTFail("We should be firing the opt-out submit-success pixel last")
            }
        } else {
            XCTFail("We should be firing the opt-out submit-success pixel")
        }
    }

    func testCorrectNumberOfTriesIsFired_whenOptOutFails() async {
        do {
            try? await runOptOut(shouldThrow: true)
            try? await runOptOut(shouldThrow: true)
            try await runOptOut(shouldThrow: true)
            XCTFail("The code above should throw")
        } catch {
            if let lastPixelFired = mockPixelHandler.lastFiredEvent {
                switch lastPixelFired {
                case .optOutFailure(_, _, _, _, _, let tries, _, _, _, _):
                    XCTAssertEqual(tries, 3)
                default: XCTFail("We should be firing the opt-out submit-success pixel last")
                }
            } else {
                XCTFail("We should be firing the opt-out submit-success pixel")
            }
        }
    }

    func testAttemptCountNotIncreased_whenOptOutFails() async {
        do {
            try await runOptOut(shouldThrow: true)
            XCTFail("The code above should throw")
        } catch {
            XCTAssertEqual(mockDatabase.attemptCount, 0)
        }
    }

    func testAttemptCountIncreased_whenOptOutSucceeds() async {
        do {
            try await runOptOut()
            XCTAssertEqual(mockDatabase.attemptCount, 1)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testAttemptCountIncreasedWithEachSuccessfulOptOut() async {
        do {
            for attempt in 0..<10 {
                try await runOptOut()
                XCTAssertEqual(mockDatabase.attemptCount, Int64(attempt) + 1)
                try? await runOptOut(shouldThrow: true)
                XCTAssertEqual(mockDatabase.attemptCount, Int64(attempt) + 1)
            }
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testUpdatingScanDateFromOptOut_thenScanRespectMostRecentDate() throws {
        let config = DataBrokerScheduleConfig(retryError: 1000, confirmOptOutScan: 1000, maintenanceScan: 1000, maxAttempts: -1)

        let brokerId: Int64 = 1
        let profileQueryId: Int64 = 1
        let extractedProfileId: Int64 = 1
        let currentPreferredRunDate = Date()

        let mockDataBroker = DataBroker(
            name: "databroker",
            url: "databroker.com",
            steps: [Step](),
            version: "1.0",
            schedulingConfig: config,
            optOutUrl: "",
            eTag: ""
        )

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

}
