//
//  UnifiedToggleInputFeature.swift
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
import Common
import Core
import PrivacyConfig

protocol UnifiedToggleInputFeatureProviding {
    var isAvailable: Bool { get }
    var isFeatureFlagEnabled: Bool { get }
}

struct UnifiedToggleInputFeature: UnifiedToggleInputFeatureProviding {

    static let isFeatureFlagEnabledKey = "com.duckduckgo.unifiedToggleInput.session.enabled"

    /// Evaluate the feature flag once and persist the result for the session.
    /// Must be called early in the app launch sequence, before any consumer
    /// reads `isAvailable`, so that every component sees the same value.
    static func resolve(using featureFlagger: FeatureFlagger) {
        let enabled = featureFlagger.isFeatureOn(.unifiedToggleInput)
        UserDefaults.app.set(enabled, forKey: isFeatureFlagEnabledKey)
    }

    private let devicePlatform: DevicePlatformProviding.Type

    init(devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        self.devicePlatform = devicePlatform
    }

    var isFeatureFlagEnabled: Bool {
        UserDefaults.app.bool(forKey: Self.isFeatureFlagEnabledKey)
    }

    var isAvailable: Bool {
        isFeatureFlagEnabled && devicePlatform.isIphone
    }
}
