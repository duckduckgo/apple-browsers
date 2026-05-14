//
//  AIChatFullModeFeature.swift
//  DuckDuckGo
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
import PrivacyConfig
import Common
import UIKit

/// Provides access to full Duck AI chat mode availability.
protocol AIChatFullModeFeatureProviding {
    /// Whether Duck AI full chat mode is available on this device.
    ///
    /// Returns `true` only when both conditions are met:
    /// - The `fullDuckAIMode` feature flag is enabled
    /// - The device is running on an iPhone (not iPad or other devices)
    var isAvailable: Bool { get }
}

/// Provides device platform detection.
protocol DevicePlatformProviding {
    /// Whether the current device is an iPhone.
    static var isIphone: Bool { get }
}

extension DevicePlatform: DevicePlatformProviding {}

/// Determines availability of Duck AI's full chat mode feature.
struct AIChatFullModeFeature: AIChatFullModeFeatureProviding {

    private let featureFlagger: any FeatureFlagger
    private let devicePlatform: DevicePlatformProviding.Type

    /// Initializes with dependencies.
    ///
    /// - Parameters:
    ///   - featureFlagger: The feature flag provider. Defaults to the shared app dependency provider.
    ///   - devicePlatform: The device platform provider. Defaults to the actual `DevicePlatform`.
    init(featureFlagger: any FeatureFlagger = AppDependencyProvider.shared.featureFlagger, devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        self.featureFlagger = featureFlagger
        self.devicePlatform = devicePlatform
    }

    /// Whether Duck AI full chat mode is available.
    ///
    /// Returns `true` only when both the feature flag is enabled AND the device is an iPhone.
    var isAvailable: Bool {
        featureFlagger.isFeatureOn(.fullDuckAIMode) && devicePlatform.isIphone
    }
}
