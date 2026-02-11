//
//  DataClearingCapability.swift
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

/// Protocol for resolving enhanced data clearing feature state.
///
/// Enhanced data clearing is only enabled when both `burnSingleTab` and `enhancedDataClearingSettings`
/// feature flags are enabled. This supports dependent gradual rollout where `enhancedDataClearingSettings`
/// is rolled out at 100% while `burnSingleTab` is rolled out to x%.
protocol DataClearingCapable {
    /// Whether the enhanced data clearing settings UI should be shown.
    /// This requires both `burnSingleTab` and `enhancedDataClearingSettings` feature flags to be enabled.
    var isEnhancedDataClearingEnabled: Bool { get }

    /// Whether the burn single tab feature is enabled.
    var isBurnSingleTabEnabled: Bool { get }
}

enum DataClearingCapability {
    static func create(using featureFlagger: FeatureFlagger) -> DataClearingCapable {
        DataClearingDefaultCapability(featureFlagger: featureFlagger)
    }
}

struct DataClearingDefaultCapability: DataClearingCapable {
    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    var isEnhancedDataClearingEnabled: Bool {
        // Enhanced data clearing is only enabled with burnSingleTab. But can be disabled on its own.
        // This supports dependent gradual rollout (Rolling out two features to the same cohort of users.
        // enhancedDataClearingSettings rolled out at 100%, while burnSingleTab rolled out to x%.
        featureFlagger.isFeatureOn(for: FeatureFlag.enhancedDataClearingSettings) && isBurnSingleTabEnabled
    }

    var isBurnSingleTabEnabled: Bool {
        featureFlagger.isFeatureOn(for: FeatureFlag.burnSingleTab)
    }
}
