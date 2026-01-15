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

import Combine
import Foundation
import os.log
import PixelKit
import PrivacyConfig

extension Notification.Name {
    static let memoryPressureWarning = Notification.Name("com.duckduckgo.macos.memoryPressure.warning")
    static let memoryPressureCritical = Notification.Name("com.duckduckgo.macos.memoryPressure.critical")
}

enum MemoryPressurePixel: PixelKitEvent {
    /// Fired when the system reports warning level memory pressure.
    case memoryPressureWarning

    /// Fired when the system reports critical level memory pressure.
    case memoryPressureCritical

    var name: String {
        switch self {
        case .memoryPressureWarning:
            return "m_mac_memory_pressure_warning"
        case .memoryPressureCritical:
            return "m_mac_memory_pressure_critical"
        }
    }

    var parameters: [String: String]? { nil }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}

/// Reports system memory pressure events as pixels.
///
/// This reporter listens to macOS memory pressure notifications using `DispatchSource`
/// and fires pixels when warning or critical memory pressure levels are detected.
///
final class MemoryPressureReporter {

    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?
    private let logger: Logger?
    private let notificationCenter: NotificationCenter
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var cancellables: Set<AnyCancellable> = []

    init(featureFlagger: FeatureFlagger,
         pixelFiring: PixelFiring?,
         logger: Logger? = nil,
         notificationCenter: NotificationCenter = .default) {
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
        self.logger = logger
        self.notificationCenter = notificationCenter
        subscribeToFeatureFlagUpdates()
    }

    deinit {
        stopMonitoring()
    }

    private func subscribeToFeatureFlagUpdates() {
        featureFlagger.updatesPublisher
            .compactMap { [weak featureFlagger] in
                featureFlagger?.isFeatureOn(.memoryPressureReporting)
            }
            .prepend(featureFlagger.isFeatureOn(.memoryPressureReporting))
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                if isEnabled {
                    self?.startMonitoring()
                } else {
                    self?.stopMonitoring()
                }
            }
            .store(in: &cancellables)
    }

    func startMonitoring() {
        guard memoryPressureSource == nil, featureFlagger.isFeatureOn(.memoryPressureReporting) else { return }

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            self.handleMemoryPressureEvent(event)
        }

        source.resume()
        memoryPressureSource = source
        logger?.warning("Memory pressure reporter started")
    }

    func stopMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
        logger?.warning("Memory pressure reporter stopped")
    }

    private func handleMemoryPressureEvent(_ event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.critical) {
            logger?.warning("Memory pressure: critical")
            notificationCenter.post(name: .memoryPressureCritical, object: self)
            pixelFiring?.fire(MemoryPressurePixel.memoryPressureCritical, frequency: .dailyAndStandard)
        } else if event.contains(.warning) {
            logger?.warning("Memory pressure: warning")
            notificationCenter.post(name: .memoryPressureWarning, object: self)
            pixelFiring?.fire(MemoryPressurePixel.memoryPressureWarning, frequency: .dailyAndStandard)
        }
    }

    // MARK: - Debug Menu Support

    /// Simulates a memory pressure event for debugging purposes.
    ///
    /// This method is intended **only for use by the Debug menu** to manually trigger
    /// memory pressure handling without waiting for actual system memory pressure events.
    /// It allows developers to test the app's response to memory pressure conditions.
    ///
    /// - Parameter level: The memory pressure level to simulate (`.warning` or `.critical`).
    ///
    /// - Warning: Do not use this method in production code. It is designed exclusively
    ///   for debugging and testing purposes via the Debug menu.
    ///
    func simulateMemoryPressureEvent(level: DispatchSource.MemoryPressureEvent) {
        handleMemoryPressureEvent(level)
    }
}

#if DEBUG
extension MemoryPressureReporter {
    func processMemoryPressureEventForTesting(_ event: DispatchSource.MemoryPressureEvent) {
        handleMemoryPressureEvent(event)
    }
}
#endif
