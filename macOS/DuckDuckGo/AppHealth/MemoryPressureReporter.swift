//
//  MemoryPressureReporter.swift
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

import Foundation
import os.log
import PixelKit

extension Notification.Name {
    static let memoryPressureCritical = Notification.Name("com.duckduckgo.macos.memoryPressure.critical")
}

enum MemoryPressurePixel: PixelKitEvent {
    /// Fired when the system reports critical level memory pressure, with context about browser state.
    case memoryPressureCritical(context: MemoryReportingContext)

    var name: String {
        switch self {
        case .memoryPressureCritical:
            return "m_mac_memory_pressure_critical"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .memoryPressureCritical(let context):
            return context.parameters
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

/// Reports system memory pressure events as pixels.
///
/// This reporter listens to macOS memory pressure notifications using `DispatchSource`
/// and fires pixels when critical memory pressure levels are detected.
///
final class MemoryPressureReporter {

    private let pixelFiring: PixelFiring?
    private let memoryUsageMonitor: MemoryUsageMonitoring
    private let windowContext: () -> WindowContext?
    private let isSyncEnabled: () -> Bool?
    private let allocationStatsProvider: MemoryAllocationStatsProviding
    private let launchDate: Date
    private let logger: Logger?
    private let notificationCenter: NotificationCenter
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    init(pixelFiring: PixelFiring?,
         memoryUsageMonitor: MemoryUsageMonitoring,
         windowContext: @autoclosure @escaping () -> WindowContext?,
         isSyncEnabled: @escaping () -> Bool?,
         allocationStatsProvider: MemoryAllocationStatsProviding = MemoryAllocationStatsExporter(),
         launchDate: Date = Date(),
         logger: Logger? = nil,
         notificationCenter: NotificationCenter = .default) {
        self.pixelFiring = pixelFiring
        self.memoryUsageMonitor = memoryUsageMonitor
        self.windowContext = windowContext
        self.isSyncEnabled = isSyncEnabled
        self.allocationStatsProvider = allocationStatsProvider
        self.launchDate = launchDate
        self.logger = logger
        self.notificationCenter = notificationCenter
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        guard memoryPressureSource == nil else { return }

        let source = DispatchSource.makeMemoryPressureSource(eventMask: .critical, queue: .main)

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            Task { @MainActor in
                self.handleMemoryPressureEvent(event)
            }
        }

        source.resume()
        memoryPressureSource = source
        logger?.warning("Memory pressure reporter started")
    }

    private func stopMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        logger?.warning("Memory pressure reporter stopped")
    }

    /// Handles a memory pressure event by collecting context and firing the pixel.
    ///
    /// This method is called on the main queue (set in `DispatchSource`), so
    /// `MemoryReportingContext.collect()` can be called directly.
    @MainActor
    private func handleMemoryPressureEvent(_ event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.critical) {
            logger?.warning("Memory pressure: critical")
            notificationCenter.post(name: .memoryPressureCritical, object: self)

            let context = MemoryReportingContext.collect(
                memoryUsageMonitor: memoryUsageMonitor,
                windowContext: windowContext(),
                isSyncEnabled: isSyncEnabled(),
                usedAllocationBytes: allocationStatsProvider.currentTotalUsedBytes(),
                launchDate: launchDate
            )
            pixelFiring?.fire(MemoryPressurePixel.memoryPressureCritical(context: context), frequency: .dailyAndStandard)
        }
    }

    // MARK: - Debug Menu Support

    /// Simulates a memory pressure event for debugging purposes.
    ///
    /// This method is intended **only for use by the Debug menu** to manually trigger
    /// memory pressure handling without waiting for actual system memory pressure events.
    /// It allows developers to test the app's response to memory pressure conditions.
    ///
    /// - Parameter level: The memory pressure level to simulate (`.critical`).
    ///
    /// - Warning: Do not use this method in production code. It is designed exclusively
    ///   for debugging and testing purposes via the Debug menu.
    ///
    @MainActor
    func simulateMemoryPressureEvent(level: DispatchSource.MemoryPressureEvent) {
        handleMemoryPressureEvent(level)
    }
}

#if DEBUG
extension MemoryPressureReporter {
    @MainActor
    func processMemoryPressureEventForTesting(_ event: DispatchSource.MemoryPressureEvent) {
        handleMemoryPressureEvent(event)
    }
}
#endif
