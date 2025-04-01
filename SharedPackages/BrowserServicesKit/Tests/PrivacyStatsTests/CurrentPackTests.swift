//
//  CurrentPackTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Combine
import XCTest
@testable import PrivacyStats

final class CurrentPackTests: XCTestCase {
    var currentPack: CurrentPack!

    override func setUp() async throws {
        currentPack = CurrentPack(pack: .init(timestamp: Date.currentPrivacyStatsPackTimestamp), commitDebounce: 10_000_000)
    }

    func testThatRecordBlockedTrackerUpdatesThePack() async {
        await currentPack.recordBlockedTracker("A")
        let companyA = await currentPack.pack.trackers["A"]
        XCTAssertEqual(companyA, 1)
    }

    func testThatRecordBlockedTrackerTriggersCommitChangesEvent() async throws {
        let packs = try await waitForCommitChangesEvents(for: 100_000_000) {
            await currentPack.recordBlockedTracker("A")
        }

        let companyA = await currentPack.pack.trackers["A"]
        XCTAssertEqual(companyA, 1)
        XCTAssertEqual(packs.first?.trackers["A"], 1)
    }

    func testThatMultipleCallsToRecordBlockedTrackerOnlyTriggerOneCommitChangesEvent() async throws {
        let packs = try await waitForCommitChangesEvents(for: 1000_000_000) {
            await currentPack.recordBlockedTracker("A")
            await currentPack.recordBlockedTracker("A")
            await currentPack.recordBlockedTracker("A")
            await currentPack.recordBlockedTracker("A")
            await currentPack.recordBlockedTracker("A")
        }

        XCTAssertEqual(packs.count, 1)
        XCTAssertEqual(packs.first?.trackers["A"], 5)
    }

    func testThatRecordBlockedTrackerCalledConcurrentlyForTheSameCompanyStoresAllCalls() async {
        await withTaskGroup(of: Void.self) { group in
            (0..<1000).forEach { _ in
                group.addTask {
                    await self.currentPack.recordBlockedTracker("A")
                }
            }
        }
        let companyA = await currentPack.pack.trackers["A"]
        XCTAssertEqual(companyA, 1000)
    }

    func testWhenCurrentPackIsOldThenRecordBlockedTrackerSendsCommitEventAndCreatesNewPack() async throws {
        let oldTimestamp = Date.currentPrivacyStatsPackTimestamp.daysAgo(1)
        let pack = PrivacyStatsPack(
            timestamp: oldTimestamp,
            trackers: ["A": 100, "B": 50, "C": 400]
        )
        currentPack = CurrentPack(pack: pack, commitDebounce: 10_000_000)

        let packs = try await waitForCommitChangesEvents(for: 100_000_000) {
            await currentPack.recordBlockedTracker("A")
        }

        XCTAssertEqual(packs.count, 2)
        let oldPack = try XCTUnwrap(packs.first)
        XCTAssertEqual(oldPack, pack)
        let newPack = try XCTUnwrap(packs.last)
        XCTAssertEqual(newPack, PrivacyStatsPack(timestamp: Date.currentPrivacyStatsPackTimestamp, trackers: ["A": 1]))
    }

    func testThatResetPackClearsAllRecordedTrackersAndSetsCurrentTimestamp() async {
        let oldTimestamp = Date.currentPrivacyStatsPackTimestamp.daysAgo(1)
        let pack = PrivacyStatsPack(
            timestamp: oldTimestamp,
            trackers: ["A": 100, "B": 50, "C": 400]
        )
        currentPack = CurrentPack(pack: pack, commitDebounce: 10_000_000)

        await currentPack.resetPack()

        let packAfterReset = await currentPack.pack
        XCTAssertEqual(packAfterReset, PrivacyStatsPack(timestamp: Date.currentPrivacyStatsPackTimestamp, trackers: [:]))
    }

    // MARK: - Helpers

    /**
     * Sets up Combine subscription, then calls the provided block and then waits
     * for the specific time before cancelling the subscription.
     * Returns an array of values passed in the published events.
     */
    func waitForCommitChangesEvents(for nanoseconds: UInt64, _ block: () async -> Void) async throws -> [PrivacyStatsPack] {
        var packs: [PrivacyStatsPack] = []
        let cancellable = currentPack.commitChangesPublisher.sink { packs.append($0) }

        await block()

        try await Task.sleep(nanoseconds: nanoseconds)
        cancellable.cancel()
        return packs
    }
}
