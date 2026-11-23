//
//  TopSitesPickerExperiment.swift
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

import FeatureFlags_macOS
import PrivacyConfig

protocol TopSitesPickerExperimentProtocol {
    /// Whether onboarding shows the step that adds popular sites to favorites.
    var shouldShowStep: Bool { get }
}

/// POC: reads the local `onboardingTopSitesPicker` flag. The experiment will replace it with eligibility
/// (fewer than 5 favorites after the import step), enrolment and the treatment cohort.
final class TopSitesPickerExperiment: TopSitesPickerExperimentProtocol {
    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    var shouldShowStep: Bool {
        featureFlagger.isFeatureOn(.onboardingTopSitesPicker)
    }
}
