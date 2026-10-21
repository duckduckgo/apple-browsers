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

/// Removes sites' memory cache after a single-tab burn returns.
///
/// Listing the memory cache waits for every live web view to respond, so a page still loading in another tab
/// would otherwise hold up the burn. The burnt tab is gone by then, and a new tab can't read its cached resources.
/// https://app.asana.com/1/137249556945/project/481882893211075/task/1219652686297425
@MainActor
protocol MemoryCacheCleaning: AnyObject {

    /// Queues removal of the memory cache for `sites`, matched against data record display names (eTLD+1).
    func scheduleRemoval(ofSites sites: Set<String>, isFireMode: Bool)

    /// Drops queued removals. A removal WebKit already started may still finish, but nothing waits for it.
    func cancelRemovals(isFireMode: Bool)

    /// Drops queued removals, then waits a bounded time for started ones, so their data store can be released.
    func cancelRemovalsAndWaitForRunningOne(isFireMode: Bool) async

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

    typealias DataStoreProvider = @MainActor (_ isFireMode: Bool) -> any DDGWebsiteDataStore

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

    /// Normal and Fire mode each keep at most one running removal and one set of sites waiting for it.
    private struct Lane {
        var running: RunningRemoval?
        var pendingSites: Set<String> = []
        var runningPreflightCacheClears = 0
        /// Set when iOS ended the background time; pending sites wait until the app is active again.
        var waitsForForeground = false
        var idleWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

        var isIdle: Bool { running == nil && runningPreflightCacheClears == 0 }
    }

    private var lanes: [Bool: Lane] = [:]
    private let dataStoreProvider: DataStoreProvider
    private let backgroundTaskRunner: BackgroundTaskRunning
    private let pixelFiring: (any PixelFiring)?
    private let runningRemovalWaitTimeout: TimeInterval
    private var didBecomeActiveObserver: NSObjectProtocol?

    /// - Parameter dataStoreProvider: Called when each removal starts, so no data store is held between removals.
    init(dataStoreProvider: @escaping DataStoreProvider = { DDGWebsiteDataStoreProvider.current(fireMode: $0) },
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

    func scheduleRemoval(ofSites sites: Set<String>, isFireMode: Bool) {
        startPreflightCacheClear(isFireMode: isFireMode)
        lanes[isFireMode, default: Lane()].pendingSites.formUnion(sites)
        startNextRemovalIfIdle(isFireMode: isFireMode)
    }

    func cancelRemovals(isFireMode: Bool) {
        lanes[isFireMode]?.pendingSites.removeAll()
        lanes[isFireMode]?.running?.task.cancel()
    }

    func cancelRemovalsAndWaitForRunningOne(isFireMode: Bool) async {
        cancelRemovals(isFireMode: isFireMode)
        guard lanes[isFireMode]?.isIdle == false else { return }

        let waiterID = UUID()
        let timeout = runningRemovalWaitTimeout
        await withCheckedContinuation { continuation in
            lanes[isFireMode]?.idleWaiters[waiterID] = continuation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.resumeWaiter(waiterID, isFireMode: isFireMode)
            }
        }
    }

    private func resumeRemovalsAfterForegrounding() {
        for isFireMode in Array(lanes.keys) {
            lanes[isFireMode]?.waitsForForeground = false
            startNextRemovalIfIdle(isFireMode: isFireMode)
        }
    }

    private func startNextRemovalIfIdle(isFireMode: Bool) {
        guard var lane = lanes[isFireMode],
              lane.running == nil,
              !lane.waitsForForeground,
              !lane.pendingSites.isEmpty else { return }

        let sites = lane.pendingSites
        lane.pendingSites.removeAll()
        let backgroundTask = backgroundTaskRunner.beginBackgroundTask(withName: "MemoryCacheCleanup") { [weak self] in
            self?.backgroundTimeDidExpire(isFireMode: isFireMode)
        }
        let task = Task { [weak self] in
            await self?.removeMemoryCache(ofSites: sites, isFireMode: isFireMode)
            self?.removalDidFinish(isFireMode: isFireMode)
        }
        lane.running = RunningRemoval(task: task, sites: sites, backgroundTask: backgroundTask)
        lanes[isFireMode] = lane
    }

    private func startPreflightCacheClear(isFireMode: Bool) {
        let dataStore = dataStoreProvider(isFireMode)
        lanes[isFireMode, default: Lane()].runningPreflightCacheClears += 1
        Task { [weak self] in
            await Self.clearPreflightCache(in: dataStore)
            self?.preflightCacheClearDidFinish(isFireMode: isFireMode)
        }
    }

    /// With no records, no site's cached resources are removed, but WebKit still clears the data it shares
    /// across sites right away, as every single-tab burn did before.
    private static func clearPreflightCache(in dataStore: some DDGWebsiteDataStore) async {
        await dataStore.removeData(ofTypes: memoryCacheDataTypes, for: [])
    }

    private func preflightCacheClearDidFinish(isFireMode: Bool) {
        lanes[isFireMode]?.runningPreflightCacheClears -= 1
        resumeIdleWaiters(isFireMode: isFireMode)
    }

    private func removeMemoryCache(ofSites sites: Set<String>, isFireMode: Bool) async {
        await Self.removeMemoryCache(ofSites: sites, from: dataStoreProvider(isFireMode))
    }

    private static func removeMemoryCache(ofSites sites: Set<String>, from dataStore: some DDGWebsiteDataStore) async {
        let records = await dataStore.dataRecords(ofTypes: memoryCacheDataTypes).filter { sites.contains($0.displayName) }
        guard !Task.isCancelled else { return }
        await dataStore.removeData(ofTypes: memoryCacheDataTypes, for: records)
    }

    /// iOS is about to suspend the app; the sites run again once it's active, unless the removal was cancelled.
    private func backgroundTimeDidExpire(isFireMode: Bool) {
        guard var lane = lanes[isFireMode], var running = lane.running else { return }
        running.expired = true
        endBackgroundTask(of: &running)
        if !running.task.isCancelled {
            lane.pendingSites.formUnion(running.sites)
        }
        lane.running = running
        lane.waitsForForeground = true
        lanes[isFireMode] = lane
    }

    private func removalDidFinish(isFireMode: Bool) {
        guard var lane = lanes[isFireMode], var running = lane.running else { return }
        if !running.task.isCancelled {
            fireFinishedPixel(duration: CACurrentMediaTime() - running.start, expired: running.expired)
        }
        endBackgroundTask(of: &running)
        lane.running = nil
        lanes[isFireMode] = lane

        resumeIdleWaiters(isFireMode: isFireMode)
        startNextRemovalIfIdle(isFireMode: isFireMode)
    }

    private func resumeIdleWaiters(isFireMode: Bool) {
        guard let lane = lanes[isFireMode], lane.isIdle else { return }
        lanes[isFireMode]?.idleWaiters.removeAll()
        lane.idleWaiters.values.forEach { $0.resume() }
    }

    private func resumeWaiter(_ waiterID: UUID, isFireMode: Bool) {
        lanes[isFireMode]?.idleWaiters.removeValue(forKey: waiterID)?.resume()
    }

    private func endBackgroundTask(of running: inout RunningRemoval) {
        guard running.backgroundTask != .invalid else { return }
        backgroundTaskRunner.endBackgroundTask(running.backgroundTask)
        running.backgroundTask = .invalid
    }

    private func fireFinishedPixel(duration: CFTimeInterval, expired: Bool) {
        pixelFiring?.fire(MemoryCacheCleanupPixel.finished(durationMilliseconds: Int(duration * 1000), expired: expired),
                          frequency: .standard)
    }
}
