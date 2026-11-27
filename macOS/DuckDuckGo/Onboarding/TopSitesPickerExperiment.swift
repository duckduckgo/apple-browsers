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
    /// Whether onboarding lists the step when it starts. The page still asks `shouldShowStep()` right before it.
    var isStepOffered: Bool { get }
    /// Enrols users with fewer than 5 favorites and returns whether they're in treatment.
    /// The page asks when the user reaches the step, after the import step, so imported favorites count.
    func shouldShowStep() -> Bool
}

final class TopSitesPickerExperiment: TopSitesPickerExperimentProtocol {
    private let favoritesLimitForEnrolment = 5
    private let featureFlagger: FeatureFlagger
    private let bookmarkManager: BookmarkManager

    init(featureFlagger: FeatureFlagger, bookmarkManager: BookmarkManager) {
        self.featureFlagger = featureFlagger
        self.bookmarkManager = bookmarkManager
    }

    /// Control users get the step listed too, so both cohorts see the same onboarding until they reach it.
    var isStepOffered: Bool {
        featureFlagger.isFeatureOn(.onboardingFavoritesStepExperiment) || assignedCohort != nil
    }

    func shouldShowStep() -> Bool {
        if let assignedCohort {
            return assignedCohort == .treatment
        }
        guard favoritesCount < favoritesLimitForEnrolment else { return false }
        let cohort = featureFlagger.resolveCohort(for: FeatureFlag.onboardingFavoritesStepExperiment) as? FeatureFlag.OnboardingFavoritesStepCohort
        return cohort == .treatment
    }

    private var assignedCohort: FeatureFlag.OnboardingFavoritesStepCohort? {
        featureFlagger.assignedCohort(for: FeatureFlag.onboardingFavoritesStepExperiment) as? FeatureFlag.OnboardingFavoritesStepCohort
    }

    private var favoritesCount: Int {
        bookmarkManager.list?.favoriteBookmarks.count ?? 0
    }
}
