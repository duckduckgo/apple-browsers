//
//  OnboardingSubscriptionUpsellExperimentTests.swift
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
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class OnboardingSubscriptionUpsellExperimentTests: XCTestCase {

    func testWhenEligibleThenEnrollResolvesCohortAndReturnsIt() {
        let cohort = FeatureFlag.OnboardingSubscriptionUpsellCohort.treatment
        let featureFlagger = makeFeatureFlagger(resolveCohortStub: cohort)
        let experiment = makeExperiment(featureFlagger: featureFlagger, subscriptionState: .eligible)

        let resolved = experiment.enroll()

        XCTAssertTrue(experiment.isEligible)
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
        XCTAssertEqual(resolved, cohort)
    }

    func testWhenEligibleAndAssignedControlThenEnrollReturnsControl() {
        let featureFlagger = makeFeatureFlagger(
            resolveCohortStub: FeatureFlag.OnboardingSubscriptionUpsellCohort.control)
        let experiment = makeExperiment(featureFlagger: featureFlagger, subscriptionState: .eligible)

        XCTAssertEqual(experiment.enroll(), .control)
    }

    func testWhenNotPurchaseEligibleThenEnrollDoesNotResolveCohortAndReturnsNil() {
        let featureFlagger = makeFeatureFlagger(
            resolveCohortStub: FeatureFlag.OnboardingSubscriptionUpsellCohort.treatment)
        let state = StubOnboardingSubscriptionUpsellSubscriptionState(isSubscriptionPurchaseEligible: false,
                                                                     isUserAuthenticated: false)
        let experiment = makeExperiment(featureFlagger: featureFlagger, subscriptionState: state)

        XCTAssertNil(experiment.enroll())
        XCTAssertFalse(experiment.isEligible)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testWhenAlreadyASubscriberThenEnrollDoesNotResolveCohortAndReturnsNil() {
        let featureFlagger = makeFeatureFlagger(
            resolveCohortStub: FeatureFlag.OnboardingSubscriptionUpsellCohort.treatment)
        let state = StubOnboardingSubscriptionUpsellSubscriptionState(isSubscriptionPurchaseEligible: true,
                                                                     isUserAuthenticated: true)
        let experiment = makeExperiment(featureFlagger: featureFlagger, subscriptionState: state)

        XCTAssertNil(experiment.enroll())
        XCTAssertFalse(experiment.isEligible)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
    }

    func testWhenCohortCannotBeResolvedThenEnrollReturnsNil() {
        let featureFlagger = makeFeatureFlagger(resolveCohortStub: nil)
        let experiment = makeExperiment(featureFlagger: featureFlagger, subscriptionState: .eligible)

        XCTAssertNil(experiment.enroll())
        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }
}

// MARK: - Helpers

private extension OnboardingSubscriptionUpsellExperimentTests {

    func makeFeatureFlagger(resolveCohortStub: (any FeatureFlagCohortDescribing)?) -> MockFeatureFlagger {
        MockFeatureFlagger(resolveCohortStub: resolveCohortStub)
    }

    func makeExperiment(featureFlagger: MockFeatureFlagger,
                        subscriptionState: StubOnboardingSubscriptionUpsellSubscriptionState) -> OnboardingSubscriptionUpsellExperiment {
        OnboardingSubscriptionUpsellExperiment(featureFlagger: featureFlagger, subscriptionState: subscriptionState)
    }
}

private struct StubOnboardingSubscriptionUpsellSubscriptionState: OnboardingSubscriptionUpsellSubscriptionState {

    static let eligible = StubOnboardingSubscriptionUpsellSubscriptionState(isSubscriptionPurchaseEligible: true,
                                                                           isUserAuthenticated: false)

    let isSubscriptionPurchaseEligible: Bool
    let isUserAuthenticated: Bool
}
