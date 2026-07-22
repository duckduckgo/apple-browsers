//
//  EventHubStoreTests.swift
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

import Testing
import Foundation
@testable import EventHub

@Suite("EventHubStore")
struct EventHubStoreTests {
    static let sampleConfig = TelemetryPixelConfig(
        name: "testPixel",
        state: "enabled",
        trigger: TelemetryTriggerConfig(type: "period", period: TelemetryPeriodConfig(seconds: 86400)),
        parameters: [
            "count": TelemetryParameterConfig(
                template: "counter",
                source: "adwall.detected",
                buckets: [
                    OrderedBucket(name: "0", config: BucketConfig(gte: 0, lt: 1)),
                    OrderedBucket(name: "1-5", config: BucketConfig(gte: 1, lt: 6)),
                    OrderedBucket(name: "6+", config: BucketConfig(gte: 6)),
                ]),
        ])

    let store = InMemoryKeyValueStore()
    let repository: EventHubStore

    init() {
        repository = EventHubKeyValueStore(store: store, parser: EventHubConfigParser())
    }

    @Test("savePixelState then pixelState(named:) round trips correctly")
    func savePixelStateThenGetPixelStateRoundTripsCorrectly() throws {
        let original = PixelState(pixelName: "testPixel", periodStartMillis: 1000, periodEndMillis: 87_401_000,
                                   config: Self.sampleConfig, params: ["count": ParamState(value: 3)])

        repository.savePixelState(original)
        let restored = try #require(repository.pixelState(named: "testPixel"))

        #expect(restored.pixelName == original.pixelName)
        #expect(restored.periodStartMillis == original.periodStartMillis)
        #expect(restored.periodEndMillis == original.periodEndMillis)
        #expect(restored.params["count"]?.value == 3)
        #expect(restored.params["count"]?.stopCounting == false)
        #expect(restored.config.name == original.config.name)
        #expect(restored.config.trigger.period?.periodSeconds == 86400)
        #expect(restored.config.parameters.count == original.config.parameters.count)
    }

    @Test("savePixelState with stopCounting preserves the flag")
    func savePixelStateWithStopCountingPreservesFlag() throws {
        let original = PixelState(pixelName: "testPixel", periodStartMillis: 0, periodEndMillis: 86_400_000,
                                   config: Self.sampleConfig, params: ["count": ParamState(value: 10, stopCounting: true)])

        repository.savePixelState(original)
        let restored = try #require(repository.pixelState(named: "testPixel"))

        #expect(restored.params["count"]?.stopCounting == true)
        #expect(restored.params["count"]?.value == 10)
    }

    @Test("pixelState(named:) returns nil for a missing entry")
    func getPixelStateReturnsNilForMissingEntry() {
        #expect(repository.pixelState(named: "missing") == nil)
    }

    @Test("pixelState(named:) returns nil for corrupt config JSON")
    func getPixelStateReturnsNilForCorruptConfigJSON() {
        store.set(
            try? JSONEncoder().encode(["corrupt": EventHubStoredPixelState(periodStartMillis: 0, periodEndMillis: 1000, paramsJSON: "{\"count\":{\"value\":1}}", configJSON: "not valid json")]),
            forKey: EventHubKeyValueStore.storageKey)

        #expect(repository.pixelState(named: "corrupt") == nil)
    }

    @Test("allPixelStates skips entries with corrupt config")
    func getAllPixelStatesSkipsEntitiesWithCorruptConfig() throws {
        repository.savePixelState(PixelState(pixelName: "good", periodStartMillis: 0, periodEndMillis: 86_400_000,
                                              config: Self.sampleConfig, params: ["count": ParamState(value: 0)]))

        var stored = (try? JSONDecoder().decode([String: EventHubStoredPixelState].self, from: store.object(forKey: EventHubKeyValueStore.storageKey) as? Data ?? Data())) ?? [:]
        stored["bad"] = EventHubStoredPixelState(periodStartMillis: 0, periodEndMillis: 1000, paramsJSON: "{}", configJSON: "corrupt")
        store.set(try? JSONEncoder().encode(stored), forKey: EventHubKeyValueStore.storageKey)

        let results = repository.allPixelStates()

        #expect(results.count == 1)
        #expect(results.first?.pixelName == "good")
    }

    @Test("deletePixelState(named:) removes the entry")
    func deletePixelStateRemovesEntry() {
        repository.savePixelState(PixelState(pixelName: "testPixel", periodStartMillis: 0, periodEndMillis: 86_400_000,
                                              config: Self.sampleConfig, params: ["count": ParamState(value: 0)]))

        repository.deletePixelState(named: "testPixel")

        #expect(repository.pixelState(named: "testPixel") == nil)
    }

    @Test("deleteAllPixelStates removes everything")
    func deleteAllPixelStatesRemovesAll() {
        repository.savePixelState(PixelState(pixelName: "a", periodStartMillis: 0, periodEndMillis: 86_400_000, config: Self.sampleConfig, params: ["count": ParamState(value: 0)]))
        repository.savePixelState(PixelState(pixelName: "b", periodStartMillis: 0, periodEndMillis: 86_400_000, config: Self.sampleConfig, params: ["count": ParamState(value: 0)]))

        repository.deleteAllPixelStates()

        #expect(repository.allPixelStates().isEmpty)
    }

    @Test("round trips empty params")
    func roundTripsEmptyParams() throws {
        repository.savePixelState(PixelState(pixelName: "testPixel", periodStartMillis: 0, periodEndMillis: 86_400_000, config: Self.sampleConfig, params: [:]))

        let restored = try #require(repository.pixelState(named: "testPixel"))
        #expect(restored.params.isEmpty)
    }

    @Test("round trips multiple params")
    func roundTripsMultipleParams() throws {
        let original = PixelState(pixelName: "testPixel", periodStartMillis: 0, periodEndMillis: 86_400_000,
                                   config: Self.sampleConfig,
                                   params: ["count": ParamState(value: 5), "other": ParamState(value: 0, stopCounting: true)])

        repository.savePixelState(original)
        let restored = try #require(repository.pixelState(named: "testPixel"))

        #expect(restored.params.count == 2)
        #expect(restored.params["count"]?.value == 5)
        #expect(restored.params["count"]?.stopCounting == false)
        #expect(restored.params["other"]?.value == 0)
        #expect(restored.params["other"]?.stopCounting == true)
    }

    @Test("corrupt params JSON yields empty params but the state is still returned")
    func corruptParamsJSONYieldsEmptyParamsButStateStillReturned() throws {
        repository.savePixelState(PixelState(pixelName: "testPixel", periodStartMillis: 0, periodEndMillis: 86_400_000,
                                              config: Self.sampleConfig, params: ["count": ParamState(value: 1)]))

        var stored = (try? JSONDecoder().decode([String: EventHubStoredPixelState].self, from: store.object(forKey: EventHubKeyValueStore.storageKey) as? Data ?? Data())) ?? [:]
        if let existing = stored["testPixel"] {
            stored["testPixel"] = EventHubStoredPixelState(periodStartMillis: existing.periodStartMillis, periodEndMillis: existing.periodEndMillis, paramsJSON: "not json", configJSON: existing.configJSON)
        }
        store.set(try? JSONEncoder().encode(stored), forKey: EventHubKeyValueStore.storageKey)

        let restored = try #require(repository.pixelState(named: "testPixel"))
        #expect(restored.params.isEmpty)
    }
}
