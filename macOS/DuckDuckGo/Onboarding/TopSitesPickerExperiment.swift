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
    /// Whether to show the step, decided when the user reaches it, after the import step, so imported favorites count.
    func shouldShowStep() -> Bool
}

/// POC: reads the local `onboardingTopSitesPicker` flag and shows the step to users with fewer than 5 favorites.
/// The experiment adds enrolment and the treatment cohort.
final class TopSitesPickerExperiment: TopSitesPickerExperimentProtocol {
    private let favoritesLimit = 5
    private let featureFlagger: FeatureFlagger
    private let bookmarkManager: BookmarkManager

    init(featureFlagger: FeatureFlagger, bookmarkManager: BookmarkManager) {
        self.featureFlagger = featureFlagger
        self.bookmarkManager = bookmarkManager
    }

    var isStepOffered: Bool {
        featureFlagger.isFeatureOn(.onboardingTopSitesPicker)
    }

    func shouldShowStep() -> Bool {
        isStepOffered && favoritesCount < favoritesLimit
    }

    private var favoritesCount: Int {
        bookmarkManager.list?.favoriteBookmarks.count ?? 0
    }
}
