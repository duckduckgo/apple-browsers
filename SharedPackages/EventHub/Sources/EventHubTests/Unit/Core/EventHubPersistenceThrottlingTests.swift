//
//  EventHubPersistenceThrottlingTests.swift
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

import Combine
import Testing
@testable import EventHub

@Suite("EventHub persistence throttling")
struct EventHubPersistenceThrottlingTests {
    static let burstSize = 5000

    // High buckets so the burst never hits the open-ended bucket / stop-counting (we want an exact count).
    static let burstConfig = """
    { "telemetry": { "burst": {
        "state": "enabled",
        "trigger": { "period": { "seconds": 3600 } },
        "parameters": { "count": { "template": "counter", "source": "e", "buckets": {
            "0-19999": {"gte": 0, "lt": 20000}, "20000+": {"gte": 20000}
        } } }
    } } }
    """

    @Test("burst counts every event without loss")
    func burstCountsEveryEventWithoutLoss() {
        let f = EventHubFixture.active(Self.burstConfig)
        for _ in 0..<Self.burstSize {
            f.manager.handleWebEvent(EventHubFixture.webEvent("e"), tabID: .new())
        }
        #expect(f.count(of: "burst") == Self.burstSize)
    }

    @Test("burst coalesces persistence writes")
    func burstCoalescesPersistenceWrites() {
        let f = EventHubFixture.active(Self.burstConfig)
        let baseline = f.store.setCallCount

        for _ in 0..<Self.burstSize {
            f.manager.handleWebEvent(EventHubFixture.webEvent("e"), tabID: .new())
        }

        // Counting is synchronous but persistence is deferred, so advance time to actually run the
        // write-behind flush — otherwise this would assert against zero writes trivially.
        f.advance(by: EventHubFixture.writeBehindFlush)

        // Writes must be coalesced — far fewer than one per event (a per-event write would be ~burstSize).
        #expect(f.store.setCallCount - baseline < 50)
    }

    @Test("burst count survives a restart")
    func burstCountSurvivesRestart() {
        let f = EventHubFixture.active(Self.burstConfig)
        for _ in 0..<Self.burstSize {
            f.manager.handleWebEvent(EventHubFixture.webEvent("e"), tabID: .new())
        }

        let restarted = f.restart()

        #expect(restarted.count(of: "burst") == Self.burstSize)
    }

    @Test("a rejected flush leaves the state pending, and the next flush persists it")
    func rejectedFlushIsRetried() {
        let h = FailableStoreHarness(settingsJSON: Self.burstConfig)
        // The period-start state was persisted during setup, so the counter is on disk at zero; what
        // must not survive the failed write is the increment.
        h.store.throwOnWrite = true

        h.manager.handleWebEvent(EventHubFixture.webEvent("e"), tabID: .new())
        h.scheduler.advance(by: EventHubFixture.writeBehindFlush)

        #expect(h.repository.pixelState(named: "burst")?.params["count"]?.value == 0)

        h.store.throwOnWrite = false
        h.scheduler.advance(by: EventHubFixture.writeBehindFlush)

        #expect(h.repository.pixelState(named: "burst")?.params["count"]?.value == 1)
    }
}

/// A hub over a store whose writes can be made to fail. `EventHubFixture` cannot do this: its
/// `InMemoryKeyValueStore` conforms to the non-throwing `KeyValueStoring`.
private final class FailableStoreHarness {
    let store = ThrowingKeyValueStore()
    let scheduler = ManualEventHubScheduler(startMillis: 1_780_000_000_000)
    let repository: EventHubStore
    let manager: EventHub

    init(settingsJSON: String) {
        let parser = EventHubConfigParser()
        repository = EventHubKeyValueStore(store: store, parser: parser)
        manager = EventHub(store: repository, parser: parser, settings: TestSettingsProviding(json: settingsJSON),
                            scheduler: scheduler, pixelFiring: SpyPixelFiring())
        scheduler.settle = { [weak manager] in manager?.settle() }
        manager.onAppForegrounded()
        manager.onConfigChanged()
        // Both are dispatched, so drain them here: the tests below arm a store failure immediately after
        // construction and would otherwise be racing setup's own flush.
        manager.settle()
    }
}
