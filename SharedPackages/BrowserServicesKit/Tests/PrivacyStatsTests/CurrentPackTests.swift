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
    private var commitChangesStream: AsyncStream<PrivacyStatsPack>!

    override func setUp() async throws {
        currentPack = CurrentPack(pack: .init(timestamp: Date.currentPrivacyStatsPackTimestamp), commitDebounce: 10_000_000)
        makeCommitChangesStream()
    }

    func testThatRecordBlockedTrackerUpdatesThePack() async {
        await currentPack.recordBlockedTracker("A")
        let companyA = await currentPack.pack.trackers["A"]
        XCTAssertEqual(companyA, 1)
    }

    func testThatRecordBlockedTrackerTriggersCommitChangesEvent() async throws {
        await currentPack.recordBlockedTracker("A")
        let pack = try await getCommittedChangesValue()

        let companyA = await currentPack.pack.trackers["A"]
        XCTAssertEqual(companyA, 1)
        XCTAssertEqual(pack.trackers["A"], 1)
    }

    func testThatMultipleCallsToRecordBlockedTrackerOnlyTriggerOneCommitChangesEvent() async throws {
        await currentPack.recordBlockedTracker("A")
        await currentPack.recordBlockedTracker("A")
        await currentPack.recordBlockedTracker("A")
        await currentPack.recordBlockedTracker("A")
        await currentPack.recordBlockedTracker("A")

        let pack = try await getCommittedChangesValue()

        XCTAssertEqual(pack.trackers["A"], 5)
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
        makeCommitChangesStream()

        await currentPack.recordBlockedTracker("A")
        let packs = try await getCommittedChangesValues(2)

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

    private struct CommitChangesNotReceivedError: Error {}

    /// Creates an async stream that emits updates to `currentPack.commitChangesPublisher`
    private func makeCommitChangesStream() {
        commitChangesStream = AsyncStream { continuation in
            let cancellable = currentPack.commitChangesPublisher
                .sink { value in
                    continuation.yield(value)
                }

            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
    /// Awaits first event emitted by the commitChanges AsyncStream.
    private func getCommittedChangesValue() async throws -> PrivacyStatsPack {
        let values = try await getCommittedChangesValues(1)
        guard let value = values.first else {
            throw CommitChangesNotReceivedError()
        }
        return value
    }

    /// Awaits first `count` events emitted by the commitChanges AsyncStream.
    private func getCommittedChangesValues(_ count: Int) async throws -> [PrivacyStatsPack] {
        var iterator = commitChangesStream.makeAsyncIterator()
        var values: [PrivacyStatsPack] = []

        for _ in 0..<count {
            guard let value = await iterator.next() else {
                throw CommitChangesNotReceivedError()
            }
            values.append(value)
        }

        return values
    }
}
