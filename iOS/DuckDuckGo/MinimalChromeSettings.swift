//
//  MinimalChromeSettings.swift
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
import PrivacyConfig

protocol MinimalChromeSettingsProviding {

    /// Whether the minimal-chrome-in-landscape feature flag is on.
    /// Use for structural guards (keyboard suppression, triggering `applyWidth`).
    var isFeatureEnabled: Bool { get }

    /// Whether minimal chrome should actually be applied given the current tab.
    /// Returns false when the feature flag is off or on an AI tab with unified input.
    func shouldApplyMinimalChrome(isCurrentTabAITab: Bool) -> Bool
}

struct MinimalChromeSettings: MinimalChromeSettingsProviding {

    private let featureFlagger: FeatureFlagger
    private let unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         unifiedToggleInputFeature: UnifiedToggleInputFeatureProviding = UnifiedToggleInputFeature()) {
        self.featureFlagger = featureFlagger
        self.unifiedToggleInputFeature = unifiedToggleInputFeature
    }

    var isFeatureEnabled: Bool {
        featureFlagger.isFeatureOn(.minimalChromeInLandscape)
    }

    func shouldApplyMinimalChrome(isCurrentTabAITab: Bool) -> Bool {
        guard isFeatureEnabled else { return false }
        if isCurrentTabAITab && unifiedToggleInputFeature.isAvailable { return false }
        return true
    }
}
