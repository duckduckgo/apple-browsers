//
//  OnboardingNonBlockingExperiment.swift
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
import Foundation
import PixelKit
import PrivacyConfig

struct OnboardingNonBlockingExperiment {

    private let featureFlagger: FeatureFlagger

    private static let subfeatureID = MacOSBrowserConfigSubfeature.onboardingNonBlocking.rawValue

    enum Metric: String {
        case onboardingCompleted
        /// Onboarding ended without completing: the tab was closed, navigated away from, removed in
        /// bulk, or its window was closed. Quitting is deliberately excluded — it records nothing,
        /// so onboarding shows again on the next launch just as it does today.
        case onboardingSkipped
        case browsingBeforeCompletion
        case importRequested
        case addToDockRequested
        case setAsDefaultEnabled

        var conversionWindows: [ClosedRange<Int>] {
            switch self {
            case .onboardingCompleted, .onboardingSkipped, .importRequested, .addToDockRequested:
                return [ConversionWindows.oneDay, ConversionWindows.fiveDays, ConversionWindows.sevenDays]
            case .browsingBeforeCompletion:
                return [ConversionWindows.sevenDays]
            case .setAsDefaultEnabled:
                return [ConversionWindows.fiveToSevenDays]
            }
        }
    }

    private enum ConversionWindows {
        static let oneDay = 0...1
        static let fiveDays = 0...5
        static let sevenDays = 0...7
        static let fiveToSevenDays = 5...7
    }

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    /// Assigns a cohort via `resolveCohort`. Caller must only invoke for eligible new installs.
    func enroll() {
        _ = featureFlagger.resolveCohort(for: FeatureFlag.onboardingNonBlocking)
    }

    /// Already-assigned cohort, or `nil` when not enrolled. Never assigns.
    var cohort: FeatureFlag.OnboardingNonBlockingCohort? {
        featureFlagger.assignedCohort(for: FeatureFlag.onboardingNonBlocking) as? FeatureFlag.OnboardingNonBlockingCohort
    }

    /// Whether onboarding should run non-blocking: the local debug flag forces it,
    /// and the treatment cohort gets it.
    var isNonBlocking: Bool {
        featureFlagger.isFeatureOn(.onboardingAsync) || cohort == .treatment
    }

    /// Tags a pixel that isn't one of this experiment's own metrics — the quit survey's, for
    /// instance — so its responses can be broken down by cohort. Unenrolled users send `none`
    /// rather than nothing, so an absent parameter always means a client too old to send it, never
    /// an unenrolled user.
    var cohortParameters: [String: String] {
        [Self.cohortParameterKey: cohort?.rawValue ?? Self.unenrolledCohortValue]
    }

    private static let cohortParameterKey = "onboardingNonBlockingCohort"
    private static let unenrolledCohortValue = "none"

    func fireMetric(_ metric: Metric) {
        guard cohort != nil else { return }
        for window in metric.conversionWindows {
            PixelKit.fireExperimentPixel(
                for: Self.subfeatureID,
                metric: metric.rawValue,
                conversionWindowDays: window,
                value: "true"
            )
        }
    }
}
