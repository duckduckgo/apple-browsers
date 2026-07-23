//
//  IOSMonthlyFreeTrialDecider.swift
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
import PrivacyConfig
import Subscription

struct IOSMonthlyFreeTrialDecider: MonthlyFreeTrialDeciding {

    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    func shouldOfferMonthlyFreeTrial() -> Bool {
        // Resolving the cohort here (at the paywall/tier-options request) enrolls the user at the
        // moment the decision is needed. `treatment` removes the monthly free trial; `control` and
        // unenrolled users keep the current behavior.
        let cohort = featureFlagger.resolveCohort(for: FeatureFlag.monthlyFreeTrialExperiment) as? FeatureFlag.MonthlyFreeTrialExperimentCohort

        switch cohort {
        case .treatment:
            return false
        case .control, .none:
            return true
        }
    }
}
