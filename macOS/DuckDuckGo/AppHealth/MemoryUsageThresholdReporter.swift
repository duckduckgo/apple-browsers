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
/// This reporter periodically polls memory usage via `getCurrentMemoryUsage()` and fires daily
/// pixels when memory usage falls into different threshold buckets. It waits 5 minutes after
/// app launch before starting to monitor, avoiding initialization memory spikes.
///
/// This reporter is fully independent from the `MemoryUsageMonitor` feature flag
/// (`.memoryUsageMonitor`), which only controls the debug UI display.
///
final class MemoryUsageThresholdReporter {

    /// The interval between memory threshold checks, in seconds.
    static let defaultCheckInterval: TimeInterval = 5

    private let memoryUsageMonitor: MemoryUsageMonitoring
    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?
    private let logger: Logger?
    private let checkInterval: TimeInterval
    private var featureFlagCancellable: AnyCancellable?
    private var monitoringTask: Task<Void, Never>?
    private var hasDelayElapsed = false
    private var delayWorkItem: DispatchWorkItem?

    /// Creates a new memory usage threshold reporter.
    ///
    /// - Parameters:
    ///   - memoryUsageMonitor: The monitor that provides memory usage readings
    ///   - featureFlagger: Feature flag provider to check if reporting is enabled
    ///   - pixelFiring: The pixel firing service for sending analytics
    ///   - checkInterval: The interval between memory checks. Defaults to 5 seconds.
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
        guard !hasDelayElapsed, featureFlagger.isFeatureOn(.memoryUsageReporting) else {
            return
        }

        logger?.debug("Memory usage threshold reporter will start monitoring after 5-minute delay")

        // Create work item for cancellation support
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hasDelayElapsed = true
            self.logger?.debug("Memory usage threshold reporter delay elapsed, starting monitoring")
            self.startThresholdChecking()
        }

        delayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: workItem)
    }

    /// Starts a repeating task to periodically check memory thresholds.
    ///
    /// Polls memory usage directly via `getCurrentMemoryUsage()` at regular intervals,
    /// independent of whether the `MemoryUsageMonitor` is actively publishing.
    private func startThresholdChecking() {
        // Fire an initial check immediately
        checkThresholdAndFire()

        // Set up a repeating task for subsequent checks
        let interval = checkInterval
        monitoringTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: NSEC_PER_SEC * UInt64(interval))
                self?.checkThresholdAndFire()
            }
        }
    }

    /// Checks which threshold bucket the current memory usage falls into and fires the pixel.
    private func checkThresholdAndFire() {
        guard hasDelayElapsed, featureFlagger.isFeatureOn(.memoryUsageReporting) else { return }

        let report = memoryUsageMonitor.getCurrentMemoryUsage()

        // Use physical footprint (matches Activity Monitor)
        let pixel = MemoryUsagePixel.pixel(forMB: report.physFootprintMB)

        logger?.debug("Memory threshold check: \(report.physFootprintMB) MB -> \(pixel.name)")

        // Fire with .daily frequency (PixelKit handles once-per-day logic per pixel name)
        pixelFiring?.fire(pixel, frequency: .daily)
    }

    /// Stops monitoring memory usage.
    ///
    /// Cancels the monitoring task, clears the delay flag, and cancels any pending delay work.
    private func stopMonitoring() {
        delayWorkItem?.cancel()
        delayWorkItem = nil
        monitoringTask?.cancel()
        monitoringTask = nil
        hasDelayElapsed = false
        logger?.debug("Memory usage threshold reporter stopped")
    }
}

extension MemoryUsageThresholdReporter {
    /// For testing and debug menu: immediately start monitoring without delay
    func startMonitoringImmediately() {
        hasDelayElapsed = true
        startThresholdChecking()
    }

    /// For debug menu: trigger an immediate threshold check
    func checkThresholdNow() {
        checkThresholdAndFire()
    }
}
