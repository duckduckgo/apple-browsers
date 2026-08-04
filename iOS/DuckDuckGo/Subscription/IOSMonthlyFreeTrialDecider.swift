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
import FeatureFlags

struct IOSMonthlyFreeTrialDecider: MonthlyFreeTrialDeciding {

    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    func shouldOfferMonthlyFreeTrial() -> Bool {
        let cohort = featureFlagger.assignedCohort(for: FeatureFlag.monthlyFreeTrialExperiment) as? FeatureFlag.MonthlyFreeTrialExperimentCohort

        // Do not offer free monthly trial for users in the treatment group.
        switch cohort {
        case .treatment:
            return false
        case .control, .none:
            return true
        }
    }
}
