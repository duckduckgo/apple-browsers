//
//  IOSMonthlyFreeTrialDeciderTests.swift
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

import PrivacyConfig
import Testing
@testable import Core
@testable import DuckDuckGo

@Suite("iOS Monthly Free Trial Decider")
struct IOSMonthlyFreeTrialDeciderTests {

    @available(iOS 16, *)
    @Test("Control cohort keeps the monthly free trial (current behavior)", .timeLimit(.minutes(1)))
    func controlCohortOffersMonthlyFreeTrial() {
        let sut = IOSMonthlyFreeTrialDecider(
            featureFlagger: PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.MonthlyFreeTrialExperimentCohort.control)
        )

        #expect(sut.shouldOfferMonthlyFreeTrial() == true)
    }

    @available(iOS 16, *)
    @Test("Treatment cohort removes the monthly free trial", .timeLimit(.minutes(1)))
    func treatmentCohortDoesNotOfferMonthlyFreeTrial() {
        let sut = IOSMonthlyFreeTrialDecider(
            featureFlagger: PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.MonthlyFreeTrialExperimentCohort.treatment)
        )

        #expect(sut.shouldOfferMonthlyFreeTrial() == false)
    }

    @available(iOS 16, *)
    @Test("A user not enrolled in the experiment keeps the monthly free trial", .timeLimit(.minutes(1)))
    func unenrolledUserOffersMonthlyFreeTrial() {
        let sut = IOSMonthlyFreeTrialDecider(
            featureFlagger: PrivacyConfig.MockFeatureFlagger(resolveCohortStub: nil)
        )

        #expect(sut.shouldOfferMonthlyFreeTrial() == true)
    }
}
