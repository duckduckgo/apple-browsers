//
//  MemoryUsageIntervalReporter.swift
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
import Foundation
import os.log
import PixelKit
import PrivacyConfig

/// Reports memory usage at startup and scheduled intervals (1h, 2h, 4h, 8h, 24h).
///
/// Each trigger fires at most once per monitoring session. A session starts when the
/// `.memoryUsageReporting` feature flag is enabled and ends when the flag is disabled.
/// Disabling and re-enabling the flag starts a fresh session.
///
/// Context parameters (memory, windows, tabs, architecture, sync) are collected at the
/// moment of firing each pixel, on the `MainActor`.
///
final class MemoryUsageIntervalReporter {

    /// The interval between checks, in seconds.
    static let defaultCheckInterval: TimeInterval = 60

    // MARK: - Dependencies

    private let memoryUsageMonitor: MemoryUsageMonitoring
    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?
    private let windowContext: () -> WindowContext?
    private let isSyncEnabled: () -> Bool?
    private let logger: Logger?
    private let checkInterval: TimeInterval

    // MARK: - State

    private var featureFlagCancellable: AnyCancellable?
    private var monitoringTask: Task<Void, Never>?

    /// Lock protecting mutable state accessed from both the main thread and the background task.
    private let lock = NSLock()
    /// The time monitoring started. `nil` when not monitoring.
    /// Note: This records when the feature flag is enabled, not app launch.
    /// Consistent with threshold reporter; acceptable because the flag is enabled early in startup.
    private var startTime: Date?
    /// Triggers that have already been fired in this session.
    private var firedTriggers: Set<String> = []

    // MARK: - Init

    /// Creates a new memory usage interval reporter.
    ///
    /// - Parameters:
    ///   - memoryUsageMonitor: Provides memory usage readings via `getCurrentMemoryUsage()`.
    ///   - featureFlagger: Feature flag provider to check if reporting is enabled.
    ///   - pixelFiring: The pixel firing service for sending analytics.
    ///   - windowContext: Closure that provides information about opened tabs and windows
    ///   - isSyncEnabled: Closure that provides a boolean if Sync is enabled.
    ///   - checkInterval: The interval between checks. Defaults to 60 seconds.
    ///   - logger: Optional logger for debugging.
    init(
        memoryUsageMonitor: MemoryUsageMonitoring,
        featureFlagger: FeatureFlagger,
        pixelFiring: PixelFiring?,
        windowContext: @autoclosure @escaping () -> WindowContext?,
        isSyncEnabled: @autoclosure @escaping () -> Bool?,
        checkInterval: TimeInterval = MemoryUsageIntervalReporter.defaultCheckInterval,
        logger: Logger? = nil
    ) {
        self.memoryUsageMonitor = memoryUsageMonitor
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
        self.windowContext = windowContext
        self.isSyncEnabled = isSyncEnabled
        self.checkInterval = checkInterval
        self.logger = logger
        subscribeToFeatureFlagUpdates()
    }

    deinit {
        stopMonitoring()
        featureFlagCancellable?.cancel()
    }

    // MARK: - Feature Flag

    /// Subscribes to feature flag updates to automatically start/stop monitoring.
    private func subscribeToFeatureFlagUpdates() {
        featureFlagCancellable = featureFlagger.updatesPublisher
            .compactMap { [weak featureFlagger] in
                featureFlagger?.isFeatureOn(.memoryUsageReporting)
            }
            .prepend(featureFlagger.isFeatureOn(.memoryUsageReporting))
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                if isEnabled {
                    self?.startMonitoring()
                } else {
                    self?.stopMonitoring()
                }
            }
    }

    // MARK: - Monitoring

    /// Starts monitoring: records the session start time and launches the background check loop.
    ///
    /// The first check fires immediately (which captures the startup trigger).
    private func startMonitoring() {
        let alreadyStarted = lock.withLock { startTime != nil }
        guard !alreadyStarted, featureFlagger.isFeatureOn(.memoryUsageReporting) else { return }

        lock.withLock { startTime = Date() }
        logger?.debug("Memory usage interval reporter starting")

        startIntervalChecking()
    }

    /// Starts a background task that periodically checks and fires interval pixels.
    private func startIntervalChecking() {
        let interval = checkInterval
        monitoringTask = Task.detached(priority: .utility) { [weak self] in
            // Fire startup + any already-elapsed triggers immediately
            await self?.checkAndFireIntervals()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(interval))
                await self?.checkAndFireIntervals()
            }
        }
    }

    /// Checks elapsed time since session start and fires any pending triggers.
    ///
    /// Context is collected on `@MainActor` at the moment each trigger fires.
    /// Thread-safe: can be called from the background task or tests.
    ///
    /// - Note: `featureFlagger.isFeatureOn(...)` is called from the background task.
    ///   `FeatureFlagger` reads are thread-safe (consistent with `MemoryUsageThresholdReporter`).
    private func checkAndFireIntervals() async {
        guard !Task.isCancelled, featureFlagger.isFeatureOn(.memoryUsageReporting) else { return }

        let currentStartTime: Date? = lock.withLock { startTime }
        guard let currentStartTime else { return }

        let elapsed = Date().timeIntervalSince(currentStartTime)

        for trigger in MemoryUsageIntervalPixel.Trigger.allCases {
            guard !Task.isCancelled else { return }

            // For non-startup triggers, check if enough time has elapsed
            if let threshold = trigger.elapsedSeconds, elapsed < threshold {
                continue
            }

            // Check and mark as fired atomically
            let shouldFire: Bool = lock.withLock {
                guard !firedTriggers.contains(trigger.rawValue) else { return false }
                firedTriggers.insert(trigger.rawValue)
                return true
            }
            guard shouldFire else { continue }

            // Collect context on MainActor and fire
            let context = await MainActor.run { [memoryUsageMonitor, windowContext, isSyncEnabled] in
                MemoryReportingContext.collect(
                    memoryUsageMonitor: memoryUsageMonitor,
                    windowContext: windowContext(),
                    isSyncEnabled: isSyncEnabled()
                )
            }

            let pixel = MemoryUsageIntervalPixel.memoryUsage(trigger: trigger, context: context)
            logger?.debug("Memory interval pixel firing: \(trigger.rawValue, privacy: .public)")
            pixelFiring?.fire(pixel, frequency: .standard)
        }
    }

    /// Stops monitoring and resets session state.
    ///
    /// A subsequent `startMonitoring()` call will begin a fresh session
    /// with a new start time and empty fired triggers set.
    private func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
        lock.withLock {
            startTime = nil
            firedTriggers.removeAll()
        }
        logger?.debug("Memory usage interval reporter stopped")
    }
}

// MARK: - Testing & Debug Support

extension MemoryUsageIntervalReporter {

    /// For testing: sets up monitoring state without starting the background task.
    ///
    /// - Parameter startTime: The simulated session start time.
    func startMonitoringForTesting(startTime: Date = Date()) {
        lock.withLock { self.startTime = startTime }
    }

    /// For testing and debug menu: triggers an immediate interval check.
    func checkIntervalsNow() async {
        await checkAndFireIntervals()
    }

#if DEBUG
    /// Clears fired triggers, allowing all triggers to fire again.
    func resetFiredTriggers() {
        lock.withLock { firedTriggers.removeAll() }
    }
#endif

    /// For debug menu: fires a specific trigger immediately, bypassing elapsed-time
    /// checks, deduplication, and feature-flag checks. This is intentional to allow
    /// developers to validate pixel content without enabling the flag or waiting for intervals.
    func fireTriggerNow(_ trigger: MemoryUsageIntervalPixel.Trigger) async {
        let context = await MainActor.run { [memoryUsageMonitor, windowContext, isSyncEnabled] in
            MemoryReportingContext.collect(
                memoryUsageMonitor: memoryUsageMonitor,
                windowContext: windowContext(),
                isSyncEnabled: isSyncEnabled()
            )
        }

        let pixel = MemoryUsageIntervalPixel.memoryUsage(trigger: trigger, context: context)
        logger?.debug("Memory interval pixel firing (debug): \(trigger.rawValue, privacy: .public)")
        pixelFiring?.fire(pixel, frequency: .standard)
    }
}
