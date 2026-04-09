//
//  FireModeCapability.swift
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

import Core
import Foundation
import PrivacyConfig

/// Protocol for resolving fire mode feature state.
///
/// Fire mode is only enabled when the `fireMode` feature flag is enabled AND iOS 17 is available.
protocol FireModeCapable {
    /// Whether fire mode is enabled.
    /// This requires the `fireMode` feature flag to be enabled and iOS 17+ availability.
    var isFireModeEnabled: Bool { get }
}

enum FireModeCapability {

    static let isFireModeEnabledKey = "com.duckduckgo.fireMode.session.enabled"

    /// Evaluate the feature flag once and persist the result for the session.
    /// Must be called early in the app launch sequence, before any consumer
    /// reads `isFireModeEnabled`, so that every component sees the same value.
    static func resolve(using featureFlagger: FeatureFlagger) {
        let enabled: Bool
        if #available(iOS 17, *) {
            enabled = featureFlagger.isFeatureOn(for: FeatureFlag.fireMode)
        } else {
            enabled = false
        }
        UserDefaults.app.set(enabled, forKey: isFireModeEnabledKey)
    }

    static func create() -> FireModeCapable {
        FireModeDefaultCapability()
    }
}

struct FireModeDefaultCapability: FireModeCapable {
    var isFireModeEnabled: Bool {
        UserDefaults.app.bool(forKey: FireModeCapability.isFireModeEnabledKey)
    }
}
