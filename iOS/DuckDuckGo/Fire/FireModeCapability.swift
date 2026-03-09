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
    static func create(using featureFlagger: FeatureFlagger) -> FireModeCapable {
        FireModeDefaultCapability(featureFlagger: featureFlagger)
    }
}

struct FireModeDefaultCapability: FireModeCapable {
    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    var isFireModeEnabled: Bool {
        guard #available(iOS 17, *) else { return false }
        return featureFlagger.isFeatureOn(for: FeatureFlag.fireMode)
    }
}
