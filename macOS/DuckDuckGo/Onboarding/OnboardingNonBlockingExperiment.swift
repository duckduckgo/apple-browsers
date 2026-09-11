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
import PixelKit
import PrivacyConfig

struct OnboardingNonBlockingExperiment {

    private let featureFlagger: FeatureFlagger
    private static let subfeatureID = MacOSBrowserConfigSubfeature.onboardingNonBlocking.rawValue

    enum Metric: String {
        case importRequested
        case addToDockRequested
        case setAsDefaultEnabled

        var conversionWindows: [ClosedRange<Int>] {
            switch self {
            case .importRequested, .addToDockRequested:
                return [0...0]
            case .setAsDefaultEnabled:
                return [5...7]
            }
        }
    }

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    /// Reads the assigned cohort without enrolling, so the many places that ask about the mode
    /// never pull a user into the experiment.
    var isNonBlocking: Bool {
        featureFlagger.assignedCohort(for: FeatureFlag.onboardingNonBlocking) as? FeatureFlag.OnboardingNonBlockingCohort == .treatment
    }

    /// The only place a cohort is assigned. Call it when onboarding starts, so the experiment
    /// measures the users who could see it rather than everyone who launches the app.
    func enroll() {
        _ = featureFlagger.resolveCohort(for: FeatureFlag.onboardingNonBlocking)
    }

    func fireMetric(_ metric: Metric) {
        for window in metric.conversionWindows {
            PixelKit.fireExperimentPixel(
                for: Self.subfeatureID,
                metric: metric.rawValue,
                conversionWindowDays: window,
                value: "true"
            )
        }
    }

    // MARK: - Search retention segmentation

    /// Splits D1-3 search retention by whether onboarding had been completed at the time of the search.
    /// Each segment fires at most once per window, so a user who completes onboarding between two
    /// searches in the window can appear in both.
    enum SearchRetentionSegment: String {
        case onboardingCompleted = "search_onboarding_completed"
        case onboardingNotCompleted = "search_onboarding_not_completed"
    }

    static let searchRetentionWindow: ClosedRange<Int> = 1...3

    /// Fires the D1-3 search retention metric, plus a segment recording whether onboarding
    /// had been completed at the time of the search.
    func fireSearchRetention(persistor: NonBlockingOnboardingPersistor = NonBlockingOnboardingPersistor()) {
        fireSearchRetention(metric: PixelKit.Constants.searchMetricValue)
        fireSearchRetentionSegment(persistor: persistor)
    }

    /// Blocking onboarding cannot be searched past, so control always counts as completed.
    private func fireSearchRetentionSegment(persistor: NonBlockingOnboardingPersistor) {
        let isCompleted = !isNonBlocking || persistor.outcome == .completed
        let segment: SearchRetentionSegment = isCompleted ? .onboardingCompleted : .onboardingNotCompleted
        fireSearchRetention(metric: segment.rawValue)
    }

    /// Counted once per window by the framework, matching its automatic search retention metrics.
    private func fireSearchRetention(metric: String) {
        PixelKit.fireExperimentPixelIfThresholdReached(
            for: Self.subfeatureID,
            metric: metric,
            conversionWindowDays: Self.searchRetentionWindow,
            threshold: 1
        )
    }
}
