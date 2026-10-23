//
//  MemoryCacheCleanerTests.swift
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

import Testing
import UIKit
import WebKit
@_spi(Testing) import PixelKit
import BrowserServicesKitTestsUtils
import WKAbstractions
@testable import DuckDuckGo

@MainActor
@Suite("Memory cache cleaner")
struct MemoryCacheCleanerTests {

    let store = HeldWebsiteDataStore(recordNames: ["a.com", "b.com", "c.com", "d.com", "unrelated.com"])
    let backgroundTasks = BackgroundTaskRunnerSpy()
    let notificationCenter = NotificationCenter()
    let pixelKit = PixelKitMock()

    @available(iOS 16, macOS 13, *)
    @Test("Sites scheduled during a running removal are removed together once it ends", .timeLimit(.minutes(1)))
    func coalescesSitesScheduledDuringRunningRemoval() async {
        let cleaner = makeCleaner()
        store.holdsListing = true

        cleaner.scheduleRemoval(ofSites: ["a.com"])
        await store.waitForListing(count: 1)
        cleaner.scheduleRemoval(ofSites: ["b.com"])
        cleaner.scheduleRemoval(ofSites: ["c.com"])
        cleaner.scheduleRemoval(ofSites: ["d.com"])
        store.releaseListings()
        await store.waitForListing(count: 2)
        store.releaseListings()
        await store.waitForRemoval(count: 2)

        #expect(store.removedRecordNames == [["a.com"], ["b.com", "c.com", "d.com"]])
        #expect(store.removedTypes.allSatisfy { $0 == MemoryCacheCleaner.memoryCacheDataTypes })
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancelling drops queued sites and skips the running removal", .timeLimit(.minutes(1)))
    func cancellingDropsQueuedSitesAndRunningRemoval() async {
        let cleaner = makeCleaner()
        store.holdsListing = true

        cleaner.scheduleRemoval(ofSites: ["a.com"])
        await store.waitForListing(count: 1)
        cleaner.scheduleRemoval(ofSites: ["b.com"])
        cleaner.cancelRemovals()
        store.releaseListings()
        await cleaner.cancelRemovalsAndWaitForRunningOne()

        #expect(store.removedRecordNames.isEmpty)
        #expect(pixelKit.actualFireCalls.isEmpty)

        store.holdsListing = false
        cleaner.scheduleRemoval(ofSites: ["c.com"])
        await store.waitForRemoval(count: 1)
        #expect(store.removedRecordNames == [["c.com"]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Waiting for a running removal gives up after the timeout", .timeLimit(.minutes(1)))
    func waitingForRunningRemovalTimesOut() async {
        let cleaner = makeCleaner(runningRemovalWaitTimeout: 0.05)
        store.holdsListing = true

        cleaner.scheduleRemoval(ofSites: ["a.com"])
        await store.waitForListing(count: 1)
        await cleaner.cancelRemovalsAndWaitForRunningOne()

        #expect(store.removedRecordNames.isEmpty)
        store.releaseListings()
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each removal and preflight cache clear asks for the current store", .timeLimit(.minutes(1)))
    func eachRemovalAsksForCurrentStore() async {
        var storeRequests = 0
        let cleaner = makeCleaner {
            storeRequests += 1
            return store
        }

        cleaner.scheduleRemoval(ofSites: ["a.com"])
        await store.waitForRemoval(count: 1)
        cleaner.scheduleRemoval(ofSites: ["b.com"])
        await store.waitForRemoval(count: 2)

        #expect(storeRequests == 4)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The preflight cache is cleared when a removal is scheduled, without waiting for the listing", .timeLimit(.minutes(1)))
    func preflightCacheIsClearedWithoutWaitingForListing() async {
        let cleaner = makeCleaner()
        store.holdsListing = true

        cleaner.scheduleRemoval(ofSites: ["a.com"])
        cleaner.scheduleRemoval(ofSites: ["b.com"])
        await store.waitForRecordlessRemoval(count: 2)

        #expect(store.removedRecordNames.isEmpty)
        #expect(store.recordlessRemovalTypes.allSatisfy { $0 == MemoryCacheCleaner.memoryCacheDataTypes })
        store.releaseListings()
    }

    @available(iOS 16, macOS 13, *)
    @Test("Waiting for running removals also waits for a started preflight cache clear", .timeLimit(.minutes(1)))
    func waitingCoversStartedPreflightCacheClear() async {
        let cleaner = makeCleaner()
        let waitEnded = WaitEnded()
        store.holdsRecordlessRemoval = true

        cleaner.scheduleRemoval(ofSites: ["a.com"])
        await store.waitForRemoval(count: 1)
        await backgroundTasks.waitForEnd(count: 1)
        let wait = Task {
            await cleaner.cancelRemovalsAndWaitForRunningOne()
            waitEnded.value = true
        }
        for _ in 0..<10 { await Task.yield() }
        #expect(!waitEnded.value)

        store.releaseRecordlessRemovals()
        await wait.value
        #expect(waitEnded.value)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A finished removal ends its background task and fires the pixel", .timeLimit(.minutes(1)))
    func finishedRemovalEndsBackgroundTaskAndFiresPixel() async {
        let cleaner = makeCleaner()

        cleaner.scheduleRemoval(ofSites: ["a.com"])
        await store.waitForRemoval(count: 1)
        await backgroundTasks.waitForEnd(count: 1)

        #expect(backgroundTasks.endedIdentifiers == backgroundTasks.begunIdentifiers)
        #expect(pixelKit.actualFireCalls.map(\.pixel.name) == ["fire_memory-cache-cleanup_finished"])
        #expect(pixelKit.actualFireCalls.first?.pixel.parameters?["expired"] == "false")
    }

    @available(iOS 16, macOS 13, *)
    @Test("When background time expires, the sites run again once the app is active", .timeLimit(.minutes(1)))
    func expiredRemovalRunsAgainWhenAppIsActive() async {
        let cleaner = makeCleaner()
        store.holdsListing = true

        cleaner.scheduleRemoval(ofSites: ["a.com"])
        await store.waitForListing(count: 1)
        backgroundTasks.expire()
        store.holdsListing = false
        store.releaseListings()
        await store.waitForRemoval(count: 1)

        #expect(backgroundTasks.endedIdentifiers == backgroundTasks.begunIdentifiers)
        #expect(pixelKit.actualFireCalls.first?.pixel.parameters?["expired"] == "true")
        #expect(store.listingCount == 1)

        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await store.waitForRemoval(count: 2)
        #expect(store.removedRecordNames == [["a.com"], ["a.com"]])
    }

    @available(iOS 16, macOS 13, *)
    @Test("A cancelled removal isn't run again when background time expires", .timeLimit(.minutes(1)))
    func cancelledRemovalIsNotRequeuedOnExpiry() async {
        let cleaner = makeCleaner()
        store.holdsListing = true

        cleaner.scheduleRemoval(ofSites: ["a.com"])
        await store.waitForListing(count: 1)
        cleaner.cancelRemovals()
        backgroundTasks.expire()
        store.holdsListing = false
        store.releaseListings()
        await backgroundTasks.waitForEnd(count: 1)

        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        cleaner.scheduleRemoval(ofSites: ["b.com"])
        await store.waitForRemoval(count: 1)
        #expect(store.removedRecordNames == [["b.com"]])
    }

    @MainActor
    final class WaitEnded {
        var value = false
    }

    private func makeCleaner(runningRemovalWaitTimeout: TimeInterval = 60,
                             dataStoreProvider: MemoryCacheCleaner.DataStoreProvider? = nil) -> MemoryCacheCleaner {
        MemoryCacheCleaner(dataStoreProvider: dataStoreProvider ?? { [store] in store },
                           backgroundTaskRunner: backgroundTasks,
                           notificationCenter: notificationCenter,
                           pixelFiring: pixelKit,
                           runningRemovalWaitTimeout: runningRemovalWaitTimeout)
    }
}

/// A data store whose listing can be held, standing in for a web view that doesn't respond.
@MainActor
final class HeldWebsiteDataStore: DDGWebsiteDataStore {

    let httpCookieStore: any DDGHTTPCookieStore = MockHTTPCookieStore()
    var holdsListing = false
    var holdsRecordlessRemoval = false
    private(set) var listingCount = 0
    private(set) var recordlessRemovalTypes: [Set<String>] = []
    private(set) var removedRecordNames: [Set<String>] = []
    private(set) var removedTypes: [Set<String>] = []

    private let recordNames: [String]
    private var heldListings: [CheckedContinuation<Void, Never>] = []
    private var heldRecordlessRemovals: [CheckedContinuation<Void, Never>] = []
    private var progressWaiters: [CheckedContinuation<Void, Never>] = []

    init(recordNames: [String]) {
        self.recordNames = recordNames
    }

    func removeData(ofTypes types: Set<String>, modifiedSince: Date) async {}

    func dataRecords(ofTypes types: Set<String>) async -> [MockWebsiteDataRecord] {
        listingCount += 1
        notifyProgress()
        if holdsListing {
            await withCheckedContinuation { heldListings.append($0) }
        }
        return recordNames.map(MockWebsiteDataRecord.init(displayName:))
    }

    func removeData(ofTypes types: Set<String>, for records: [MockWebsiteDataRecord]) async {
        guard !records.isEmpty else { return await removeDataWithoutRecords(ofTypes: types) }
        removedTypes.append(types)
        removedRecordNames.append(Set(records.map(\.displayName)))
        notifyProgress()
    }

    private func removeDataWithoutRecords(ofTypes types: Set<String>) async {
        recordlessRemovalTypes.append(types)
        notifyProgress()
        if holdsRecordlessRemoval {
            await withCheckedContinuation { heldRecordlessRemovals.append($0) }
        }
    }

    func releaseRecordlessRemovals() {
        let removals = heldRecordlessRemovals
        heldRecordlessRemovals.removeAll()
        removals.forEach { $0.resume() }
    }

    func releaseListings() {
        let listings = heldListings
        heldListings.removeAll()
        listings.forEach { $0.resume() }
    }

    func waitForListing(count: Int) async {
        await waitUntil { listingCount >= count }
    }

    func waitForRecordlessRemoval(count: Int) async {
        await waitUntil { recordlessRemovalTypes.count >= count }
    }

    func waitForRemoval(count: Int) async {
        await waitUntil { removedRecordNames.count >= count }
    }

    private func waitUntil(_ isDone: () -> Bool) async {
        while !isDone() {
            await withCheckedContinuation { progressWaiters.append($0) }
        }
    }

    private func notifyProgress() {
        let waiters = progressWaiters
        progressWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

@MainActor
final class BackgroundTaskRunnerSpy: BackgroundTaskRunning {

    private(set) var begunIdentifiers: [UIBackgroundTaskIdentifier] = []
    private(set) var endedIdentifiers: [UIBackgroundTaskIdentifier] = []
    private var expirationHandlers: [@MainActor () -> Void] = []
    private var endWaiters: [CheckedContinuation<Void, Never>] = []

    func beginBackgroundTask(withName name: String, expirationHandler: @escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier {
        let identifier = UIBackgroundTaskIdentifier(rawValue: begunIdentifiers.count + 1)
        begunIdentifiers.append(identifier)
        expirationHandlers.append(expirationHandler)
        return identifier
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        endedIdentifiers.append(identifier)
        let waiters = endWaiters
        endWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func expire() {
        expirationHandlers.last?()
    }

    func waitForEnd(count: Int) async {
        while endedIdentifiers.count < count {
            await withCheckedContinuation { endWaiters.append($0) }
        }
    }
}
