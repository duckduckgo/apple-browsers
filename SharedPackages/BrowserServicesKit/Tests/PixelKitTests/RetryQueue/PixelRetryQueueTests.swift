//
//  PixelRetryQueueTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import PersistenceTestingUtils
@testable import PixelKit

final class PixelRetryQueueTests: XCTestCase {

    private var store: MockPixelRetryQueueStore!
    private var fireMock: FireRequestMock!
    private var lastProcessingStorage: MockKeyValueStore!
    private var now: Date!

    override func setUp() {
        super.setUp()
        store = MockPixelRetryQueueStore()
        fireMock = FireRequestMock()
        lastProcessingStorage = MockKeyValueStore()
        now = Date(timeIntervalSince1970: 1_700_000_000)
    }

    private func makeQueue() -> PixelRetryQueue {
        PixelRetryQueue(fireRequest: fireMock.fireRequest,
                        store: store,
                        lastProcessingDateStorage: lastProcessingStorage,
                        calendar: .current,
                        dateGenerator: { [unowned self] in self.now })
    }

    private func makeItem(name: String, ageInDays: Int = 0) -> PixelRetryQueueItem {
        let timestamp = Calendar.current.date(byAdding: .day, value: -ageInDays, to: now)!
        return PixelRetryQueueItem(pixelName: name,
                                   headers: [:],
                                   parameters: ["key": "value"],
                                   allowedQueryReservedCharacters: nil,
                                   timestamp: timestamp)
    }

    // MARK: - Persist on failure

    func testWhenOrganicFireSucceeds_ThenNothingIsStored_AndCompletionIsForwarded() {
        let queue = makeQueue()
        let completed = expectation(description: "onComplete")

        queue.fireRequest("m_organic", [:], ["k": "v"], nil, true) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1.0)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testWhenOrganicFireFails_ThenItemIsStoredWithTimestamp_AndCompletionIsForwarded() {
        let error = NSError(domain: "test", code: 7)
        fireMock.defaultResult = (false, error)
        let queue = makeQueue()
        let completed = expectation(description: "onComplete")

        queue.fireRequest("m_organic", ["H": "V"], ["k": "v"], nil, true) { success, returnedError in
            XCTAssertFalse(success)
            XCTAssertEqual((returnedError as NSError?)?.code, 7)
            completed.fulfill()
        }

        wait(for: [completed], timeout: 1.0)

        XCTAssertEqual(store.items.count, 1)
        let stored = store.items[0]
        XCTAssertEqual(stored.pixelName, "m_organic")
        XCTAssertEqual(stored.headers, ["H": "V"])
        XCTAssertEqual(stored.parameters["k"], "v")
        XCTAssertEqual(stored.timestamp, now)
    }

    // MARK: - Draining

    func testWhenSendingQueuedPixels_ThenStoredItemIsSentAndRemoved() {
        let item = makeItem(name: "m_queued")
        try? store.append([item])
        let queue = makeQueue()
        let drained = expectation(description: "drained")

        queue.sendQueuedPixels { error in
            XCTAssertNil(error)
            drained.fulfill()
        }

        wait(for: [drained], timeout: 2.0)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(fireMock.calls.count, 1)
        XCTAssertEqual(fireMock.calls.first?.pixelName, "m_queued")
        // The replay carries the item's stored parameters unchanged — nothing is injected on send.
        XCTAssertEqual(fireMock.calls.first?.parameters, item.parameters)
    }

    func testWhenReplayingItemWithLegacyTimestampParameter_ThenItIsStrippedBeforeSending() {
        // Items persisted by builds that still baked in `originalPixelTimestamp` must not replay with it.
        let legacy = PixelRetryQueueItem(pixelName: "m_queued",
                                         headers: [:],
                                         parameters: ["key": "value", "originalPixelTimestamp": "2026-06-11T00:00:00Z"],
                                         allowedQueryReservedCharacters: nil,
                                         timestamp: now)
        try? store.append([legacy])
        let queue = makeQueue()
        let drained = expectation(description: "drained")

        queue.sendQueuedPixels { _ in drained.fulfill() }
        wait(for: [drained], timeout: 2.0)

        XCTAssertEqual(fireMock.calls.first?.parameters, ["key": "value"])
    }

    func testWhenItemIsOlderThan28Days_ThenItIsNotSentButIsRemoved() {
        let item = makeItem(name: "m_stale", ageInDays: 30)
        try? store.append([item])
        let queue = makeQueue()
        let drained = expectation(description: "drained")

        queue.sendQueuedPixels { _ in drained.fulfill() }
        wait(for: [drained], timeout: 2.0)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(fireMock.calls.isEmpty)
    }

    func testWhenLastProcessingWasRecent_ThenDrainIsSkipped() {
        let item = makeItem(name: "m_queued")
        try? store.append([item])
        // Last processed 30 seconds ago — within the DEBUG 1-minute throttle.
        lastProcessingStorage.set(now.addingTimeInterval(-30), forKey: PixelRetryQueue.Constants.lastProcessingDateKey)
        let queue = makeQueue()
        let drained = expectation(description: "drained")

        queue.sendQueuedPixels { _ in drained.fulfill() }
        wait(for: [drained], timeout: 2.0)

        XCTAssertEqual(store.items, [item])
        XCTAssertTrue(fireMock.calls.isEmpty)
    }

    func testWhenQueueIsEmpty_ThenThrottleIsNotAdvanced_AndLaterItemIsStillDrained() {
        let queue = makeQueue()

        // An empty drain must not advance the throttle...
        let emptyDrain = expectation(description: "empty drain")
        queue.sendQueuedPixels { _ in emptyDrain.fulfill() }
        wait(for: [emptyDrain], timeout: 2.0)
        XCTAssertNil(lastProcessingStorage.object(forKey: PixelRetryQueue.Constants.lastProcessingDateKey))

        // ...so a failure queued immediately afterwards is still replayed on the next drain.
        try? store.append([makeItem(name: "m_queued")])
        let secondDrain = expectation(description: "second drain")
        queue.sendQueuedPixels { _ in secondDrain.fulfill() }
        wait(for: [secondDrain], timeout: 2.0)

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(fireMock.calls.contains { $0.pixelName == "m_queued" })
    }

    func testWhenReplayedItemHasCharacterSet_ThenItIsSentUnchanged() {
        let item = PixelRetryQueueItem(pixelName: "m_chars",
                                       headers: [:],
                                       parameters: [:],
                                       allowedQueryReservedCharacters: CharacterSet(charactersIn: ",;"),
                                       timestamp: now)
        try? store.append([item])
        let queue = makeQueue()
        let drained = expectation(description: "drained")

        queue.sendQueuedPixels { _ in drained.fulfill() }
        wait(for: [drained], timeout: 2.0)

        XCTAssertEqual(fireMock.calls.first?.allowedQueryReservedCharacters, CharacterSet(charactersIn: ",;"))
    }

    // MARK: - Decorator-specific behaviour

    func testWhenOrganicFireSucceeds_ThenQueueIsDrained() {
        let item = makeItem(name: "m_queued")
        try? store.append([item])
        let queue = makeQueue()

        // The queued pixel is only ever fired via replay, so receiving it confirms the drain ran.
        let queuedReplayed = expectation(description: "queued item replayed")
        fireMock.onFireReceived = { call in
            if call.pixelName == "m_queued" { queuedReplayed.fulfill() }
        }

        // An organic success should trigger a drain that replays the queued item.
        queue.fireRequest("m_organic", [:], [:], nil, true) { _, _ in }

        wait(for: [queuedReplayed], timeout: 2.0)
        XCTAssertTrue(fireMock.calls.contains { $0.pixelName == "m_queued" })
    }

    func testWhenNewFireFailsWhileDraining_ThenNewItemIsAlsoStored() {
        let initialItem = makeItem(name: "m_initial")
        try? store.append([initialItem])

        fireMock.deferredPixelNames = ["m_initial"]   // hold the in-flight replay open
        fireMock.defaultResult = (false, NSError(domain: "test", code: 1))  // the new organic fire fails
        let queue = makeQueue()

        // Start the drain; wait until the replay of the queued item is received (and held).
        let replayReceived = expectation(description: "replay received")
        fireMock.onFireReceived = { call in
            if call.pixelName == "m_initial" { replayReceived.fulfill() }
        }
        queue.sendQueuedPixels()
        wait(for: [replayReceived], timeout: 2.0)

        // Fire a failing organic pixel while the drain is in flight.
        let organicCompleted = expectation(description: "organic completed")
        queue.fireRequest("m_new", [:], [:], nil, true) { _, _ in organicCompleted.fulfill() }
        wait(for: [organicCompleted], timeout: 2.0)

        // The new failed pixel is stored alongside the initial one.
        XCTAssertEqual(store.items.count, 2)
        XCTAssertTrue(store.items.contains(initialItem))

        // Release the held replay so the drain completes.
        fireMock.completePendingFires(success: true)
    }

    func testWhenRetryFails_ThenItemRemainsQueued() {
        let item = makeItem(name: "m_queued")
        try? store.append([item])
        fireMock.defaultResult = (false, NSError(domain: "test", code: 2))
        let queue = makeQueue()
        let drained = expectation(description: "drained")

        queue.sendQueuedPixels { _ in drained.fulfill() }
        wait(for: [drained], timeout: 2.0)

        XCTAssertEqual(store.items, [item])
    }

    func testWhenAFailedPixelIsEnqueued_ThenExpiredItemsArePruned() {
        let expired = makeItem(name: "m_stale", ageInDays: 30)
        try? store.append([expired])
        fireMock.defaultResult = (false, NSError(domain: "test", code: 1))
        let queue = makeQueue()
        let completed = expectation(description: "onComplete")

        // A failing organic fire enqueues the new pixel and prunes already-expired items (no drain needed).
        queue.fireRequest("m_new", [:], [:], nil, true) { _, _ in completed.fulfill() }
        wait(for: [completed], timeout: 1.0)

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.pixelName, "m_new")
        XCTAssertFalse(store.items.contains(expired))
    }

    func testWhenExpiredPruningFails_ThenTheFailedPixelIsStillQueued() {
        store.storedItemsError = NSError(domain: "test", code: 9)   // the prune's read throws
        fireMock.defaultResult = (false, NSError(domain: "test", code: 1))
        let queue = makeQueue()
        let completed = expectation(description: "onComplete")

        // A prune failure must not prevent the new failed pixel from being queued.
        queue.fireRequest("m_new", [:], [:], nil, true) { _, _ in completed.fulfill() }
        wait(for: [completed], timeout: 1.0)

        XCTAssertTrue(store.items.contains { $0.pixelName == "m_new" })
    }
}
