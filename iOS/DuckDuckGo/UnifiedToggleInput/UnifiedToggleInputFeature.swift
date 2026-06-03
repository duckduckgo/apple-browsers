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
import FoundationExtensions
import Core
import PrivacyConfig

protocol UnifiedToggleInputFeatureProviding {
    var isAvailable: Bool { get }
    /// When true, the UTI hides the Search↔Duck.ai toggle on Duck.ai tabs regardless of the
    /// user's toggle-enabled setting. Backed by `FeatureFlag.aiChatTabHideToggle`.
    ///
    /// No protocol-extension default: every conformer (including test mocks) must declare an
    /// explicit value so test coverage isn't silently masked by a convenient fallback.
    var isToggleHiddenOnDuckAITab: Bool { get }
}

struct UnifiedToggleInputFeature: UnifiedToggleInputFeatureProviding {

    private static let isFeatureFlagEnabledKey = "com.duckduckgo.unifiedToggleInput.session.enabled"
    private static let isToggleHiddenOnDuckAITabKey = "com.duckduckgo.unifiedToggleInput.aiChatTabHideToggle.session.enabled"

    private static let controlCohortID = FeatureFlag.DuckAIQueryExperimentCohort.control.rawValue

    private static let nonControlCohortExcludedExperimentIDs: Set<SubfeatureID> = [
        AIChatSubfeature.onboardingDuckAIQueryExperiment.rawValue,
        AIChatSubfeature.onboardingDuckAIQueryTrackersDemoExperiment.rawValue,
    ]

    /// Snapshot the feature flags once per session. Call early at launch, before any consumer reads `isAvailable` / `isToggleHiddenOnDuckAITab`.
    static func resolve(using featureFlagger: FeatureFlagger) {
        UserDefaults.app.set(featureFlagger.isFeatureOn(.unifiedToggleInput), forKey: isFeatureFlagEnabledKey)
        UserDefaults.app.set(featureFlagger.isFeatureOn(.aiChatTabHideToggle), forKey: isToggleHiddenOnDuckAITabKey)
    }

    private let featureFlagger: FeatureFlagger
    private let devicePlatform: DevicePlatformProviding.Type

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         devicePlatform: DevicePlatformProviding.Type = DevicePlatform.self) {
        self.featureFlagger = featureFlagger
        self.devicePlatform = devicePlatform
    }

    private var isFeatureFlagEnabled: Bool {
        UserDefaults.app.bool(forKey: Self.isFeatureFlagEnabledKey)
    }

    var isAvailable: Bool {
        isFeatureFlagEnabled && devicePlatform.isIphone && !isInExcludedExperimentCohort
    }

    var isToggleHiddenOnDuckAITab: Bool {
        UserDefaults.app.bool(forKey: Self.isToggleHiddenOnDuckAITabKey)
    }

    private var isInExcludedExperimentCohort: Bool {
        Self.nonControlCohortExcludedExperimentIDs.contains { experimentID in
            guard let cohortID = featureFlagger.allActiveExperiments[experimentID]?.cohortID else {
                return false
            }
            return cohortID != Self.controlCohortID
        }
    }
}
