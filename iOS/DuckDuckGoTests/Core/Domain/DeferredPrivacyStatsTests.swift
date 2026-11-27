//
//  DeferredPrivacyStatsTests.swift
//  DuckDuckGo
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

import Foundation
@_spi(Testing) import PixelKit
import Testing
@testable import DuckDuckGo

@Suite("Privacy Stats - deferred store load")
struct DeferredPrivacyStatsTests {

    /// Holds the load back until `release()`, standing in for a slow store.
    private final class GatedLoad {
        let stats = MockPrivacyStats()
        private let gate = DispatchSemaphore(value: 0)

        func load() -> PrivacyStatsProviding {
            gate.wait()
            return stats
        }

        func release() {
            gate.signal()
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Count reads zero while the store loads and the stored total once loaded", .timeLimit(.minutes(1)))
    func countIsZeroUntilLoaded() async {
        let gated = GatedLoad()
        gated.stats.total = 42
        let stats = DeferredPrivacyStats(load: gated.load)

        #expect(await stats.fetchPrivacyStatsTotalCount() == 0)

        gated.release()
        await stats.handleAppTermination() // Waits for the load.

        #expect(await stats.fetchPrivacyStatsTotalCount() == 42)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Trackers blocked before the store loads are recorded once it loads", .timeLimit(.minutes(1)))
    func trackersBeforeLoadAreRecorded() async {
        let gated = GatedLoad()
        let stats = DeferredPrivacyStats(load: gated.load)

        let recording = Task {
            await stats.recordBlockedTracker("Tracker A")
            await stats.recordBlockedTracker("Tracker B")
        }
        #expect(gated.stats.recordCalls.isEmpty)

        gated.release()
        await recording.value

        #expect(gated.stats.recordCalls == ["Tracker A", "Tracker B"])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Clearing while the store loads clears it once loaded", .timeLimit(.minutes(1)))
    func clearDuringLoadClearsLoadedStore() async throws {
        let gated = GatedLoad()
        let stats = DeferredPrivacyStats(load: gated.load)

        let clearing = Task { await stats.clearPrivacyStats() }
        gated.release()

        try await clearing.value.get()
        #expect(gated.stats.clearCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Loading runs the store load once, off the main thread", .timeLimit(.minutes(1)))
    func loadRunsOnceOffMainThread() async {
        var loadedOnMainThread: [Bool] = []
        let stats = DeferredPrivacyStats(load: {
            loadedOnMainThread.append(Thread.isMainThread)
            return MockPrivacyStats()
        })

        await stats.recordBlockedTracker("Tracker")
        _ = await stats.clearPrivacyStats()
        await stats.handleAppTermination()

        #expect(loadedOnMainThread == [false])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A store that can't be opened gives unavailable stats and fires the unavailable pixel once", .timeLimit(.minutes(1)))
    func unreadableStoreGivesUnavailableStats() throws {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: location) }
        // Creates the store; the instance is released before the second load.
        _ = try #require(PrivacyStatsDatabase(location: location, pixelFiring: nil))
        let storeFile = location.appendingPathComponent("PrivacyStats.sqlite")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: storeFile.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storeFile.path) }
        let pixelKit = PixelKitMock()

        let stats = DeferredPrivacyStats.loadStore(location: location, pixelFiring: pixelKit)

        #expect(stats is UnavailablePrivacyStats)
        #expect(pixelKit.actualFireCalls.map(\.pixel.name) == ["privacy-stats_database_load_failed"])
        #expect(pixelKit.actualFireCalls.map(\.pixel.parameters) == [["outcome": "unavailable"]])
    }
}
