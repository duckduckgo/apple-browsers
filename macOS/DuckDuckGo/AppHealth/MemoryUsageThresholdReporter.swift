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
/// This reporter monitors memory usage from `MemoryUsageMonitor` and fires daily pixels
/// when memory usage crosses into different threshold buckets. It waits 5 minutes after
/// app launch before starting to monitor, avoiding initialization memory spikes.
///
final class MemoryUsageThresholdReporter {

    private let memoryUsageMonitor: MemoryUsageMonitoring
    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?
    private let logger: Logger?
    private var featureFlagCancellable: AnyCancellable?
    private var cancellables: Set<AnyCancellable> = []
    private var hasDelayElapsed = false
    private var delayWorkItem: DispatchWorkItem?

    /// Creates a new memory usage threshold reporter.
    ///
    /// - Parameters:
    ///   - memoryUsageMonitor: The monitor that provides memory usage updates
    ///   - featureFlagger: Feature flag provider to check if reporting is enabled
    ///   - pixelFiring: The pixel firing service for sending analytics
    ///   - logger: Optional logger for debugging
    init(
        memoryUsageMonitor: MemoryUsageMonitoring,
        featureFlagger: FeatureFlagger,
        pixelFiring: PixelFiring?,
        logger: Logger? = nil
    ) {
        self.memoryUsageMonitor = memoryUsageMonitor
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
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

        logger?.info("Memory usage threshold reporter will start monitoring after 5-minute delay")

        // Create work item for cancellation support
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hasDelayElapsed = true
            self.logger?.info("Memory usage threshold reporter delay elapsed, starting monitoring")
            self.subscribeToMemoryUpdates()
        }

        delayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: workItem)
    }

    /// Subscribes to memory usage updates from the monitor.
    ///
    /// Checks the threshold on each update and fires the appropriate pixel with daily frequency.
    private func subscribeToMemoryUpdates() {
        memoryUsageMonitor.memoryReportPublisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] report in
                self?.checkThresholdAndFire(report: report)
            }
            .store(in: &cancellables)
    }

    /// Checks which threshold bucket the memory usage falls into and fires the pixel.
    ///
    /// - Parameter report: The current memory usage report
    private func checkThresholdAndFire(report: MemoryUsageMonitor.MemoryReport) {
        guard hasDelayElapsed else { return }

        // Use physical footprint (matches Activity Monitor)
        let pixel = MemoryUsagePixel.pixel(forMB: report.physFootprintMB)

        logger?.debug("Memory threshold check: \(report.physFootprintMB) MB -> \(pixel.name)")

        // Fire with .daily frequency (PixelKit handles once-per-day logic per pixel name)
        pixelFiring?.fire(pixel, frequency: .daily)
    }

    /// Stops monitoring memory usage.
    ///
    /// Cancels all subscriptions, clears the delay flag, and cancels any pending delay work.
    private func stopMonitoring() {
        delayWorkItem?.cancel()
        delayWorkItem = nil
        cancellables.removeAll()
        hasDelayElapsed = false
        logger?.info("Memory usage threshold reporter stopped")
    }
}

#if DEBUG
extension MemoryUsageThresholdReporter {
    /// For testing: immediately start monitoring without delay
    func startMonitoringImmediately() {
        hasDelayElapsed = true
        subscribeToMemoryUpdates()
    }
}
#endif
