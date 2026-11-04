//
//  MemoryCacheCleaner.swift
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
import PixelKit
import UIKit
import WebKit
import WKAbstractions

/// Removes sites' memory cache after a single-tab burn returns. Normal and Fire mode each have their own cleaner.
///
/// Listing the memory cache waits for every live web view to respond, so a page still loading in another tab
/// would otherwise hold up the burn. The burnt tab is gone by then, and a new tab can't read its cached resources.
/// https://app.asana.com/1/137249556945/project/481882893211075/task/1219652686297425
@MainActor
protocol MemoryCacheCleaning: AnyObject {

    /// Queues removal of the memory cache for `sites`, matched against data record display names (eTLD+1).
    func scheduleRemoval(ofSites sites: Set<String>)

    /// Drops queued removals. A removal WebKit already started may still finish, but nothing waits for it.
    func cancelRemovals()

    /// Drops queued removals, then waits a bounded time for started ones, so their data store can be released.
    func cancelRemovalsAndWaitForRunningOne() async

}

@MainActor
protocol BackgroundTaskRunning {
    func beginBackgroundTask(withName name: String, expirationHandler: @escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier
    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier)
}

struct ApplicationBackgroundTaskRunner: BackgroundTaskRunning {

    // Not redundant: the synthesized one is main-actor isolated, and it's used as a default argument.
    // swiftlint:disable:next unneeded_synthesized_initializer
    nonisolated init() {}

    func beginBackgroundTask(withName name: String, expirationHandler: @escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: name) {
            MainActor.assumeIsolated { expirationHandler() }
        }
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

@MainActor
final class MemoryCacheCleaner: MemoryCacheCleaning {

    typealias DataStoreProvider = @MainActor () -> any DDGWebsiteDataStore

    static let memoryCacheDataTypes: Set<String> = [WKWebsiteDataTypeMemoryCache]

    /// The Fire tabs are closed by the time their data store is removed, so a started removal ends quickly.
    static let runningRemovalWaitTimeout: TimeInterval = 3

    private struct RunningRemoval {
        let task: Task<Void, Never>
        let sites: Set<String>
        let start = CACurrentMediaTime()
        var backgroundTask: UIBackgroundTaskIdentifier
        var expired = false
    }

    /// At most one removal runs; sites scheduled meanwhile wait for it and are removed together.
    private var running: RunningRemoval?
    private var pendingSites: Set<String> = []
    private var runningPreflightCacheClears = 0
    /// Set when iOS ended the background time; pending sites wait until the app is active again.
    private var waitsForForeground = false
    private var idleWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    private var isIdle: Bool { running == nil && runningPreflightCacheClears == 0 }

    private let dataStoreProvider: DataStoreProvider
    private let backgroundTaskRunner: BackgroundTaskRunning
    private let pixelFiring: (any PixelFiring)?
    private let runningRemovalWaitTimeout: TimeInterval
    private var didBecomeActiveObserver: NSObjectProtocol?

    /// - Parameter dataStoreProvider: Called when each removal starts, so no data store is held between removals.
    init(dataStoreProvider: @escaping DataStoreProvider,
         backgroundTaskRunner: BackgroundTaskRunning = ApplicationBackgroundTaskRunner(),
         notificationCenter: NotificationCenter = .default,
         pixelFiring: (any PixelFiring)? = PixelKit.shared,
         runningRemovalWaitTimeout: TimeInterval = MemoryCacheCleaner.runningRemovalWaitTimeout) {
        self.dataStoreProvider = dataStoreProvider
        self.backgroundTaskRunner = backgroundTaskRunner
        self.pixelFiring = pixelFiring
        self.runningRemovalWaitTimeout = runningRemovalWaitTimeout
        didBecomeActiveObserver = notificationCenter.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                                 object: nil,
                                                                 queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resumeRemovalsAfterForegrounding() }
        }
    }

    func scheduleRemoval(ofSites sites: Set<String>) {
        startPreflightCacheClear()
        pendingSites.formUnion(sites)
        startNextRemovalIfIdle()
    }

    func cancelRemovals() {
        pendingSites.removeAll()
        running?.task.cancel()
    }

    func cancelRemovalsAndWaitForRunningOne() async {
        cancelRemovals()
        guard !isIdle else { return }

        let waiterID = UUID()
        let timeout = runningRemovalWaitTimeout
        await withCheckedContinuation { continuation in
            idleWaiters[waiterID] = continuation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.resumeWaiter(waiterID)
            }
        }
    }

    private func resumeRemovalsAfterForegrounding() {
        waitsForForeground = false
        startNextRemovalIfIdle()
    }

    private func startNextRemovalIfIdle() {
        guard running == nil, !waitsForForeground, !pendingSites.isEmpty else { return }

        let sites = pendingSites
        pendingSites.removeAll()
        let backgroundTask = backgroundTaskRunner.beginBackgroundTask(withName: "MemoryCacheCleanup") { [weak self] in
            self?.backgroundTimeDidExpire()
        }
        let task = Task { [weak self] in
            await self?.removeMemoryCache(ofSites: sites)
            self?.removalDidFinish()
        }
        running = RunningRemoval(task: task, sites: sites, backgroundTask: backgroundTask)
    }

    private func startPreflightCacheClear() {
        let dataStore = dataStoreProvider()
        runningPreflightCacheClears += 1
        Task { [weak self] in
            await Self.clearPreflightCache(in: dataStore)
            self?.preflightCacheClearDidFinish()
        }
    }

    /// With no records, no site's cached resources are removed, but WebKit still clears the data it shares
    /// across sites right away, as every single-tab burn did before.
    private static func clearPreflightCache(in dataStore: some DDGWebsiteDataStore) async {
        await dataStore.removeData(ofTypes: memoryCacheDataTypes, for: [])
    }

    private func preflightCacheClearDidFinish() {
        runningPreflightCacheClears -= 1
        resumeIdleWaiters()
    }

    private func removeMemoryCache(ofSites sites: Set<String>) async {
        await Self.removeMemoryCache(ofSites: sites, from: dataStoreProvider())
    }

    private static func removeMemoryCache(ofSites sites: Set<String>, from dataStore: some DDGWebsiteDataStore) async {
        let records = await dataStore.dataRecords(ofTypes: memoryCacheDataTypes).filter { sites.contains($0.displayName) }
        guard !Task.isCancelled else { return }
        await dataStore.removeData(ofTypes: memoryCacheDataTypes, for: records)
    }

    /// iOS is about to suspend the app; the sites run again once it's active, unless the removal was cancelled.
    private func backgroundTimeDidExpire() {
        guard running != nil else { return }
        running?.expired = true
        endBackgroundTaskOfRunningRemoval()
        if let running, !running.task.isCancelled {
            pendingSites.formUnion(running.sites)
        }
        waitsForForeground = true
    }

    private func removalDidFinish() {
        guard let finished = running else { return }
        if !finished.task.isCancelled {
            fireFinishedPixel(duration: CACurrentMediaTime() - finished.start, expired: finished.expired)
        }
        endBackgroundTaskOfRunningRemoval()
        running = nil

        resumeIdleWaiters()
        startNextRemovalIfIdle()
    }

    private func resumeIdleWaiters() {
        guard isIdle else { return }
        let waiters = idleWaiters.values
        idleWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func resumeWaiter(_ waiterID: UUID) {
        idleWaiters.removeValue(forKey: waiterID)?.resume()
    }

    private func endBackgroundTaskOfRunningRemoval() {
        guard let backgroundTask = running?.backgroundTask, backgroundTask != .invalid else { return }
        backgroundTaskRunner.endBackgroundTask(backgroundTask)
        running?.backgroundTask = .invalid
    }

    private func fireFinishedPixel(duration: CFTimeInterval, expired: Bool) {
        pixelFiring?.fire(MemoryCacheCleanupPixel.finished(durationMilliseconds: Int(duration * 1000), expired: expired),
                          frequency: .standard)
    }
}
