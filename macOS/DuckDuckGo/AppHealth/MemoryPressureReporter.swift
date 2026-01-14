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

enum MemoryPressurePixel: PixelKitEvent {
    /// Fired when the system reports warning level memory pressure.
    case memoryPressureWarning

    /// Fired when the system reports critical level memory pressure.
    case memoryPressureCritical

    var name: String {
        switch self {
        case .memoryPressureWarning:
            return "memory_pressure_warning"
        case .memoryPressureCritical:
            return "memory_pressure_critical"
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
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var cancellables: Set<AnyCancellable> = []

    init(featureFlagger: FeatureFlagger, pixelFiring: PixelFiring?, logger: Logger? = nil) {
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
        self.logger = logger
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

    private func startMonitoring() {
        guard memoryPressureSource == nil, featureFlagger.isFeatureOn(.memoryPressureReporting) else { return }

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            self.handleMemoryPressureEvent(event)
        }

        source.resume()
        memoryPressureSource = source
    }

    private func stopMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil
    }

    private func handleMemoryPressureEvent(_ event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.critical) {
            logger?.warning("Memory pressure: critical")
            pixelFiring?.fire(MemoryPressurePixel.memoryPressureCritical, frequency: .dailyAndStandard)
        } else if event.contains(.warning) {
            logger?.warning("Memory pressure: warning")
            pixelFiring?.fire(MemoryPressurePixel.memoryPressureWarning, frequency: .dailyAndStandard)
        } else if event.contains(.normal) {
            logger?.info("Memory pressure: normal")
        }
    }
}
