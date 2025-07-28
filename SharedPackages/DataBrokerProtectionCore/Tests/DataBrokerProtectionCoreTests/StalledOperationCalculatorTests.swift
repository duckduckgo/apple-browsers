//
//  StalledOperationCalculatorTests.swift
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
import Foundation
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class StalledOperationCalculatorTests: XCTestCase {

    func testNoOperations_ReturnsZeroCounts() {
        // Given
        let calculator = StalledOperationCalculator.scan
        let profileData: [BrokerProfileQueryData] = []

        // When
        let result = calculator.calculate(from: profileData)

        // Then
        XCTAssertEqual(result.total, 0)
        XCTAssertEqual(result.stalled, 0)
        XCTAssertTrue(result.totalByBroker.isEmpty)
        XCTAssertTrue(result.stalledByBroker.isEmpty)
    }

    func testCompletedOperations_NoStalledOperations() {
        // Given
        let calculator = StalledOperationCalculator.scan
        let historyEvents = [
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date().addingTimeInterval(-3600)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .matchesFound(count: 1), date: Date().addingTimeInterval(-1800))
        ]
        let profileData = createProfileData(with: historyEvents)

        // When
        let result = calculator.calculate(from: profileData)

        // Then
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.stalled, 0)
        XCTAssertEqual(result.totalByBroker["test-1.0.0"], 1)
        XCTAssertNil(result.stalledByBroker["test-1.0.0"])
    }

    func testStalledOperation_CountsCorrectly() {
        // Given
        let calculator = StalledOperationCalculator.scan
        let historyEvents = [
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date().addingTimeInterval(-3600))
            // No completion event
        ]
        let profileData = createProfileData(with: historyEvents)

        // When
        let result = calculator.calculate(from: profileData)

        // Then
        XCTAssertEqual(result.total, 1)
        XCTAssertEqual(result.stalled, 1)
        XCTAssertEqual(result.totalByBroker["test-1.0.0"], 1)
        XCTAssertEqual(result.stalledByBroker["test-1.0.0"], 1)
    }

    func testMultipleStalledOperations_CountsAllStalled() {
        // Given
        let calculator = StalledOperationCalculator.scan
        let historyEvents = [
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date().addingTimeInterval(-7200)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date().addingTimeInterval(-3600)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date().addingTimeInterval(-1800))
            // No completion events for any
        ]
        let profileData = createProfileData(with: historyEvents)

        // When
        let result = calculator.calculate(from: profileData)

        // Then
        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.stalled, 3)
    }

    func testMixedCompletedAndStalled_CountsCorrectly() {
        // Given
        let calculator = StalledOperationCalculator.scan
        let historyEvents = [
            // First operation: completed
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date().addingTimeInterval(-7200)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .noMatchFound, date: Date().addingTimeInterval(-6600)),
            // Second operation: stalled
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date().addingTimeInterval(-3600)),
            // Third operation: completed
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date().addingTimeInterval(-1800)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .matchesFound(count: 1), date: Date().addingTimeInterval(-900))
        ]
        let profileData = createProfileData(with: historyEvents)

        // When
        let result = calculator.calculate(from: profileData)

        // Then
        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.stalled, 1)
    }

    func testEventsOlderThan7Days_AreExcluded() {
        // Given
        let calculator = StalledOperationCalculator.scan
        let historyEvents = [
            // Old operation (>7 days): should be excluded
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date().addingTimeInterval(-8 * 24 * 3600)),
            // Recent operation (<7 days): should be included
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date().addingTimeInterval(-3600))
        ]
        let profileData = createProfileData(with: historyEvents)

        // When
        let result = calculator.calculate(from: profileData)

        // Then
        XCTAssertEqual(result.total, 1) // Only the recent operation
        XCTAssertEqual(result.stalled, 1)
    }

    func testMixedScansAndOptOuts_CalculatesSeparately() {
        // Given - Mixed scan and opt-out events
        let scanEvents = [
            // First scan: completed with match
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date().addingTimeInterval(-7200)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .matchesFound(count: 2), date: Date().addingTimeInterval(-6600)),

            // Second scan: stalled (started but no completion)
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date().addingTimeInterval(-3600)),
            // No completion event - this is stalled

            // Third scan: completed with no match
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .scanStarted, date: Date().addingTimeInterval(-1800)),
            HistoryEvent(brokerId: 1, profileQueryId: 1, type: .noMatchFound, date: Date().addingTimeInterval(-1700))
        ]

        let optOutEvents = [
            // First opt-out: completed with optOutRequested
            [
                HistoryEvent(brokerId: 1, profileQueryId: 1, type: .optOutStarted, date: Date().addingTimeInterval(-5400)),
                HistoryEvent(brokerId: 1, profileQueryId: 1, type: .optOutRequested, date: Date().addingTimeInterval(-5000))
            ],
            // Second opt-out: stalled (started but no completion)
            [
                HistoryEvent(brokerId: 1, profileQueryId: 1, type: .optOutStarted, date: Date().addingTimeInterval(-2400))
                // No completion event - this is stalled
            ],
            // Third opt-out: completed with optOutConfirmed
            [
                HistoryEvent(brokerId: 1, profileQueryId: 1, type: .optOutStarted, date: Date().addingTimeInterval(-1000)),
                HistoryEvent(brokerId: 1, profileQueryId: 1, type: .optOutConfirmed, date: Date().addingTimeInterval(-800))
            ]
        ]

        let profileData = createProfileData(with: scanEvents, optOutEvents: optOutEvents)

        // When
        let scanResult = StalledOperationCalculator.scan.calculate(from: profileData)
        let optOutResult = StalledOperationCalculator.optOut.calculate(from: profileData)

        // Then
        // Scan results: 3 total, 1 stalled
        XCTAssertEqual(scanResult.total, 3)
        XCTAssertEqual(scanResult.stalled, 1)
        XCTAssertEqual(scanResult.totalByBroker["test-1.0.0"], 3)
        XCTAssertEqual(scanResult.stalledByBroker["test-1.0.0"], 1)

        // Opt-out results: 3 total, 1 stalled
        XCTAssertEqual(optOutResult.total, 3)
        XCTAssertEqual(optOutResult.stalled, 1)
        XCTAssertEqual(optOutResult.totalByBroker["test-1.0.0"], 3)
        XCTAssertEqual(optOutResult.stalledByBroker["test-1.0.0"], 1)
    }

    private func createProfileData(with scanEvents: [HistoryEvent], optOutEvents: [[HistoryEvent]] = []) -> [BrokerProfileQueryData] {
        let optOutJobData = optOutEvents.map { events in
            OptOutJobData.mock(with: .mockWithoutRemovedDate, historyEvents: events)
        }

        return [BrokerProfileQueryData.mock(
            scanHistoryEvents: scanEvents,
            optOutJobData: optOutJobData.isEmpty ? nil : optOutJobData
        )]
    }
}
