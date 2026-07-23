//
//  OnboardingChromeExtensionExperiment.swift
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

import FeatureFlags
import Foundation
import PixelKit
import PrivacyConfig

struct OnboardingChromeExtensionExperiment {

    private let featureFlagger: FeatureFlagger

    private static let subfeatureID = MacOSBrowserConfigSubfeature.onboardingChromeExtension.rawValue

    enum Metric: String {
        case setAsDefault
        case onboardingCompleted
    }

    private enum ConversionWindows {
        static let oneDay = 0...1
        static let fiveDays = 0...5
        static let sevenDays = 0...7
        static let all = [oneDay, fiveDays, sevenDays]
    }

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    /// Assigns a cohort via `resolveCohort`. Caller must only invoke when install-eligible.
    func enroll() {
        _ = featureFlagger.resolveCohort(for: FeatureFlag.onboardingChromeExtension)
    }

    /// Already-assigned cohort, or `nil` when not enrolled. Never assigns.
    var cohort: FeatureFlag.OnboardingChromeExtensionCohort? {
        featureFlagger.assignedCohort(for: FeatureFlag.onboardingChromeExtension) as? FeatureFlag.OnboardingChromeExtensionCohort
    }

    func fireMetric(_ metric: Metric) {
        guard cohort != nil else { return }
        for window in ConversionWindows.all {
            PixelKit.fireExperimentPixel(
                for: Self.subfeatureID,
                metric: metric.rawValue,
                conversionWindowDays: window,
                value: "true"
            )
        }
    }
}
