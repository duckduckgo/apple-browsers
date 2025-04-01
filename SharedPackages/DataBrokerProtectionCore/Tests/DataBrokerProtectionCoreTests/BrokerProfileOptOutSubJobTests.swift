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
            _ = try await sut.runOptOutOperation(
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
            _ = try await sut.runOptOutOperation(
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
            _ = try await sut.runOptOutOperation(
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
            _ = try await sut.runOptOutOperation(
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
            _ = try await sut.runOptOutOperation(
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
            _ = try await sut.runOptOutOperation(
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
            _ = try await sut.runOptOutOperation(
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
            _ = try await sut.runOptOutOperation(
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

    private func runOptOutOperation(shouldThrow: Bool = false) async throws {
        mockOptOutRunner.shouldOptOutThrow = shouldThrow
        _ = try await sut.runOptOutOperation(
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
        try? await runOptOutOperation(shouldThrow: true)
        try? await runOptOutOperation(shouldThrow: true)
        try? await runOptOutOperation()

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
            try? await runOptOutOperation(shouldThrow: true)
            try? await runOptOutOperation(shouldThrow: true)
            try await runOptOutOperation(shouldThrow: true)
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
            try await runOptOutOperation(shouldThrow: true)
            XCTFail("The code above should throw")
        } catch {
            XCTAssertEqual(mockDatabase.attemptCount, 0)
        }
    }

    func testAttemptCountIncreased_whenOptOutSucceeds() async {
        do {
            try await runOptOutOperation()
            XCTAssertEqual(mockDatabase.attemptCount, 1)
        } catch {
            XCTFail("Should not throw")
        }
    }

    func testAttemptCountIncreasedWithEachSuccessfulOptOut() async {
        do {
            for attempt in 0..<10 {
                try await runOptOutOperation()
                XCTAssertEqual(mockDatabase.attemptCount, Int64(attempt) + 1)
                try? await runOptOutOperation(shouldThrow: true)
                XCTAssertEqual(mockDatabase.attemptCount, Int64(attempt) + 1)
            }
        } catch {
            XCTFail("Should not throw")
        }
    }

}
