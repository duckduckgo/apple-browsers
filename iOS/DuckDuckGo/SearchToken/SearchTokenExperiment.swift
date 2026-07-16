//
//  SearchTokenExperiment.swift
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

import BrowserServicesKit
import Core
import Foundation
import PrivacyConfig

struct SearchTokenExperiment {

    private let featureFlagger: FeatureFlagger
    private let statisticsStore: StatisticsStore

    init(featureFlagger: FeatureFlagger,
         statisticsStore: StatisticsStore = StatisticsUserDefaults()) {
        self.featureFlagger = featureFlagger
        self.statisticsStore = statisticsStore
    }

    /// Resolves — and thereby enrols — the cohort for an eligible new user. No-op for returning users.
    func enrollIfEligible() {
        guard statisticsStore.variant != VariantIOS.returningUser.name else { return }
        _ = featureFlagger.resolveCohort(for: FeatureFlag.searchTokenExperiment)
    }

    /// The assigned cohort, or `nil` when not enrolled.
    var cohort: FeatureFlag.SearchTokenExperimentCohort? {
        featureFlagger.assignedCohort(for: FeatureFlag.searchTokenExperiment) as? FeatureFlag.SearchTokenExperimentCohort
    }
}
