//
//  SubscriptionOnboardingPostCheckoutTriggerTests.swift
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

import XCTest
import PrivacyConfig
import FeatureFlags_iOS
@testable import Subscription
import SubscriptionTestingUtilities
@testable import DuckDuckGo

/// The rule deciding whether a purchase flow offers post-checkout onboarding.
final class SubscriptionOnboardingPostCheckoutTriggerTests: XCTestCase {

    func testWhenAFirstPurchaseCompletesThenOnboardingIsRequested() async {
        let result = await shouldRequest()

        XCTAssertTrue(result)
    }

    func testWhenTheFlowIsAPlanUpdateThenOnboardingIsNotRequested() async {
        let result = await shouldRequest(flowType: .planUpdate)

        XCTAssertFalse(result)
    }

    /// The restore, email, and plan-update flows are built without a store, which is what keeps them out.
    func testWhenTheFlowHasNoOnboardingStoreThenOnboardingIsNotRequested() async {
        let result = await shouldRequest(hasOnboardingStore: false)

        XCTAssertFalse(result)
    }

    func testWhenTheFeatureIsDisabledThenOnboardingIsNotRequested() async {
        let result = await shouldRequest(isFeatureEnabled: false)

        XCTAssertFalse(result)
    }

    /// A defensive re-invocation of the purchase-completed hook must not re-offer the flow.
    func testWhenOnboardingWasAlreadyRequestedThenItIsNotRequestedAgain() async {
        let result = await shouldRequest(didAlreadyRequest: true)

        XCTAssertFalse(result)
    }

    /// `isFeatureEnabled` costs a network round trip, so the cheap conditions must be checked first.
    func testWhenOnboardingWasAlreadyRequestedThenTheFeatureCheckIsNeverEvaluated() async {
        var wasEvaluated = false

        _ = await SubscriptionFlowViewModel.shouldRequestOnboarding(flowType: .firstPurchase,
                                                                     hasOnboardingStore: true,
                                                                     didAlreadyRequest: true) {
            wasEvaluated = true
            return true
        }

        XCTAssertFalse(wasEvaluated)
    }

    // MARK: - Helper

    /// Defaults describe the one case that should fire, so each test names only the condition it breaks.
    private func shouldRequest(flowType: SubscriptionFlowType = .firstPurchase,
                               hasOnboardingStore: Bool = true,
                               isFeatureEnabled: Bool = true,
                               didAlreadyRequest: Bool = false) async -> Bool {
        await SubscriptionFlowViewModel.shouldRequestOnboarding(flowType: flowType,
                                                                hasOnboardingStore: hasOnboardingStore,
                                                                didAlreadyRequest: didAlreadyRequest) {
            isFeatureEnabled
        }
    }
}

final class SubscriptionOnboardingFeatureCheckTests: XCTestCase {

    private static let enUS = Locale(identifier: "en_US")

    func testWhenOnFreeTrialAndEnrolledAsTreatmentThenFeatureIsEnabled() async {
        let isEnabled = await isFeatureEnabled(hasActiveTrialOffer: true)

        XCTAssertTrue(isEnabled)
    }

    func testWhenNotOnFreeTrialThenFeatureIsDisabled() async {
        let isEnabled = await isFeatureEnabled(hasActiveTrialOffer: false)

        XCTAssertFalse(isEnabled)
    }

    func testWhenSubscriptionFetchFailsThenFeatureIsDisabled() async {
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.resultSubscription = .failure(TestError.fetchFailed)
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingSep2026Cohort.treatment,
                                                               isAlreadyAssigned: false)

        let isEnabled = await SubscriptionFlowViewModel.isOnboardingFeatureEnabled(subscriptionManager: subscriptionManager,
                                                                                   featureFlagger: featureFlagger,
                                                                                   locale: Self.enUS)

        XCTAssertFalse(isEnabled)
    }

    // MARK: - Helper

    private enum TestError: Error {
        case fetchFailed
    }

    private func isFeatureEnabled(hasActiveTrialOffer: Bool) async -> Bool {
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            activeOffers: hasActiveTrialOffer ? [DuckDuckGoSubscription.Offer(type: .trial)] : []
        ))
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingSep2026Cohort.treatment,
                                                               isAlreadyAssigned: false)
        return await SubscriptionFlowViewModel.isOnboardingFeatureEnabled(subscriptionManager: subscriptionManager,
                                                                          featureFlagger: featureFlagger,
                                                                          locale: Self.enUS)
    }
}
