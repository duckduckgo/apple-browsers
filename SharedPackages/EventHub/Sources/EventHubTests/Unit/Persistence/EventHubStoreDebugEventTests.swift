//
//  EventHubStoreDebugEventTests.swift
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

@Suite("EventHubStore debug events")
struct EventHubStoreDebugEventTests {
    private static let sampleConfig = TelemetryPixelConfig(
        name: "testPixel",
        state: "enabled",
        trigger: TelemetryTriggerConfig(type: "period", period: TelemetryPeriodConfig(seconds: 86400)),
        parameters: [
            "count": TelemetryParameterConfig(
                template: "counter",
                source: "adwall.detected",
                buckets: [OrderedBucket(name: "0+", config: BucketConfig(gte: 0))]),
        ])

    private static var sampleState: PixelState {
        PixelState(pixelName: "testPixel", periodStartMillis: 1000, periodEndMillis: 87_401_000,
                   config: sampleConfig, params: ["count": ParamState(value: 3)])
    }

    private let capture = CapturingEventMapping()
    private let store = ThrowingKeyValueStore()
    private let repository: EventHubStore

    init() {
        repository = EventHubKeyValueStore(store: store, parser: EventHubConfigParser(), eventMapping: capture.eventMapping)
    }

    @Test("a throwing read reports the read operation")
    func throwingReadReportsReadOperation() {
        store.throwOnRead = true

        _ = repository.allPixelStates()

        #expect(capture.fired == [.pixelStatePersistenceFailed(operation: .read)])
        #expect(capture.errors.first is ThrowingKeyValueStore.StoreError)
    }

    @Test("an undecodable stored blob reports the decode operation")
    func undecodableStoredBlobReportsDecodeOperation() throws {
        try store.set(Data("not encoded state".utf8), forKey: EventHubKeyValueStore.storageKey)

        _ = repository.allPixelStates()

        #expect(capture.fired == [.pixelStatePersistenceFailed(operation: .decode)])
    }

    @Test("a stored value that is not Data reports the decode operation")
    func storedValueThatIsNotDataReportsDecodeOperation() throws {
        try store.set("not Data at all", forKey: EventHubKeyValueStore.storageKey)

        _ = repository.allPixelStates()

        #expect(capture.fired == [.pixelStatePersistenceFailed(operation: .decode)])
    }

    @Test("a throwing write reports the write operation")
    func throwingWriteReportsWriteOperation() {
        store.throwOnWrite = true

        repository.savePixelState(Self.sampleState)

        #expect(capture.fired == [.pixelStatePersistenceFailed(operation: .write)])
        #expect(capture.errors.first is ThrowingKeyValueStore.StoreError)
    }

    @Test("a throwing delete reports the delete operation")
    func throwingDeleteReportsDeleteOperation() {
        store.throwOnRemove = true

        repository.deleteAllPixelStates()

        #expect(capture.fired == [.pixelStatePersistenceFailed(operation: .delete)])
        #expect(capture.errors.first is ThrowingKeyValueStore.StoreError)
    }

    // Regression guard: "nothing stored yet" is the normal cold-start state on every first launch. Were
    // it treated as a read failure, this pixel would fire for the entire install base.
    @Test("an absent value fires nothing")
    func absentValueFiresNothing() {
        _ = repository.allPixelStates()
        #expect(repository.pixelState(named: "testPixel") == nil)

        #expect(capture.fired.isEmpty)
    }

    // The successful path must stay silent even though it reads, writes and deletes.
    @Test("a successful round trip fires nothing")
    func successfulRoundTripFiresNothing() {
        repository.savePixelState(Self.sampleState)
        #expect(repository.pixelState(named: "testPixel") != nil)
        repository.deletePixelState(named: "testPixel")
        repository.deleteAllPixelStates()

        #expect(capture.fired.isEmpty)
    }
}
