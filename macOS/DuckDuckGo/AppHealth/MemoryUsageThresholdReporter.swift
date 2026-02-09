//
//  MemoryUsageThresholdReporter.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Reports threshold memory usage pixels when memory enters specific buckets.
///
/// This reporter periodically polls memory usage via `getCurrentMemoryUsage()` on a background
/// thread and fires daily pixels when memory usage falls into different threshold buckets.
/// It waits 5 minutes after app launch before starting to monitor, avoiding initialization
/// memory spikes.
///
/// Client-side deduplication tracks which pixel names have been fired today. The set resets
/// on day change. PixelKit's `.daily` frequency remains as a server-side safety net.
///
/// This reporter is fully independent from the `MemoryUsageMonitor` feature flag
/// (`.memoryUsageMonitor`), which only controls the debug UI display.
///
final class MemoryUsageThresholdReporter {

    /// The interval between memory threshold checks, in seconds.
    static let defaultCheckInterval: TimeInterval = 30

    private let memoryUsageMonitor: MemoryUsageMonitoring
    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?
    private let logger: Logger?
    private let checkInterval: TimeInterval
    private var featureFlagCancellable: AnyCancellable?
    private var monitoringTask: Task<Void, Never>?
    private var delayWorkItem: DispatchWorkItem?

    // MARK: - Thread-safe state

    /// Lock protecting mutable state accessed from both the main thread and the background task.
    private let lock = NSLock()
    private var hasDelayElapsed = false
    /// Tracks which pixel names have already been fired today to avoid redundant fire calls.
    /// Persists across feature flag toggles; only resets on day change.
    private var firedPixelNames: Set<String> = []
    /// The date of the last threshold check, used to detect day changes and reset `firedPixelNames`.
    private var lastCheckDate = Date()

    /// Creates a new memory usage threshold reporter.
    ///
    /// - Parameters:
    ///   - memoryUsageMonitor: The monitor that provides memory usage readings
    ///   - featureFlagger: Feature flag provider to check if reporting is enabled
    ///   - pixelFiring: The pixel firing service for sending analytics
    ///   - checkInterval: The interval between memory checks. Defaults to 30 seconds.
    ///   - logger: Optional logger for debugging
    init(
        memoryUsageMonitor: MemoryUsageMonitoring,
        featureFlagger: FeatureFlagger,
        pixelFiring: PixelFiring?,
        checkInterval: TimeInterval = MemoryUsageThresholdReporter.defaultCheckInterval,
        logger: Logger? = nil
    ) {
        self.memoryUsageMonitor = memoryUsageMonitor
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
        self.checkInterval = checkInterval
        self.logger = logger
        subscribeToFeatureFlagUpdates()
    }

    deinit {
        stopMonitoring()
        featureFlagCancellable?.cancel()
    }

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

    /// Starts monitoring memory usage after a 5-minute delay.
    ///
    /// The delay helps avoid capturing memory spikes during app initialization.
    /// Only starts if the feature flag is enabled and monitoring hasn't already started.
    private func startMonitoring() {
        let alreadyStarted = lock.withLock { hasDelayElapsed }
        guard !alreadyStarted, featureFlagger.isFeatureOn(.memoryUsageReporting) else {
            return
        }

        logger?.debug("Memory usage threshold reporter will start monitoring after 5-minute delay")

        // Create work item for cancellation support
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.withLock { self.hasDelayElapsed = true }
            self.logger?.debug("Memory usage threshold reporter delay elapsed, starting monitoring")
            self.startThresholdChecking()
        }

        delayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: workItem)
    }

    /// Starts a repeating task to periodically check memory thresholds on a background thread.
    ///
    /// Polls memory usage directly via `getCurrentMemoryUsage()` at regular intervals,
    /// independent of whether the `MemoryUsageMonitor` is actively publishing.
    private func startThresholdChecking() {
        // Fire an initial check immediately
        checkThresholdAndFire()

        // Set up a repeating background task for subsequent checks
        let interval = checkInterval
        monitoringTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(interval))
                self?.checkThresholdAndFire()
            }
        }
    }

    /// Checks which threshold bucket the current memory usage falls into and fires the pixel.
    ///
    /// Thread-safe: can be called from both the main thread and the background monitoring task.
    /// Skips firing if the pixel has already been fired today. Resets the fired set on day change.
    private func checkThresholdAndFire() {
        let shouldProceed = lock.withLock { hasDelayElapsed }
        guard shouldProceed, featureFlagger.isFeatureOn(.memoryUsageReporting) else { return }

        let report = memoryUsageMonitor.getCurrentMemoryUsage()
        let pixel = MemoryUsagePixel.pixel(forMB: report.physFootprintMB)

        let shouldFire: Bool = lock.withLock {
            let now = Date()
            if !Calendar.current.isDate(now, inSameDayAs: lastCheckDate) {
                firedPixelNames.removeAll()
                lastCheckDate = now
            }

            guard !firedPixelNames.contains(pixel.name) else { return false }
            firedPixelNames.insert(pixel.name)
            return true
        }

        guard shouldFire else { return }

        logger?.debug("Memory threshold firing: \(report.physFootprintMB, privacy: .public) MB -> \(pixel.name, privacy: .public)")
        pixelFiring?.fire(pixel, frequency: .daily)
    }

    /// Stops monitoring memory usage.
    ///
    /// Cancels the monitoring task and delay work. The `firedPixelNames` set is intentionally
    /// preserved across stop/start cycles to avoid re-firing pixels within the same day.
    private func stopMonitoring() {
        delayWorkItem?.cancel()
        delayWorkItem = nil
        monitoringTask?.cancel()
        monitoringTask = nil
        lock.withLock { hasDelayElapsed = false }
        logger?.debug("Memory usage threshold reporter stopped")
    }
}

extension MemoryUsageThresholdReporter {
    /// For testing and debug menu: immediately start monitoring without delay
    func startMonitoringImmediately() {
        lock.withLock { hasDelayElapsed = true }
        startThresholdChecking()
    }

    /// For debug menu and testing: trigger an immediate threshold check.
    func checkThresholdNow() {
        checkThresholdAndFire()
    }

    /// Clears the client-side deduplication set, allowing all pixels to fire again.
    /// Used by the debug menu before triggering a simulated check.
    func resetFiredPixels() {
        lock.withLock { firedPixelNames.removeAll() }
    }
}
