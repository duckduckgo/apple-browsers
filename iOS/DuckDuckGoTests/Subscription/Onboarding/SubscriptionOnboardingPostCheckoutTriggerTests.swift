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
import PixelKit
import PixelExperimentKit
import FeatureFlags_iOS
@testable import Subscription
import SubscriptionTestingUtilities
@testable import DuckDuckGo

/// The rule deciding whether a purchase flow offers post-checkout onboarding.
final class SubscriptionOnboardingPostCheckoutTriggerTests: XCTestCase {

    func test_shouldRequestOnboarding_firstPurchaseCompletes_returnsTrue() async {
        let result = await shouldRequest()

        XCTAssertTrue(result)
    }

    func test_shouldRequestOnboarding_flowIsPlanUpdate_returnsFalse() async {
        let result = await shouldRequest(flowType: .planUpdate)

        XCTAssertFalse(result)
    }

    /// The restore, email, and plan-update flows are built without a store, which is what keeps them out.
    func test_shouldRequestOnboarding_noOnboardingStore_returnsFalse() async {
        let result = await shouldRequest(hasOnboardingStore: false)

        XCTAssertFalse(result)
    }

    func test_shouldRequestOnboarding_featureDisabled_returnsFalse() async {
        let result = await shouldRequest(isFeatureEnabled: false)

        XCTAssertFalse(result)
    }

    /// A defensive re-invocation of the purchase-completed hook must not re-offer the flow.
    func test_shouldRequestOnboarding_alreadyRequested_returnsFalse() async {
        let result = await shouldRequest(didAlreadyRequest: true)

        XCTAssertFalse(result)
    }

    /// `isFeatureEnabled` costs a network round trip, so the cheap conditions must be checked first.
    func test_shouldRequestOnboarding_alreadyRequested_neverEvaluatesFeatureCheck() async {
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
    private var firedEvents: [PixelKit.Event] = []

    override func setUp() {
        super.setUp()
        firedEvents = []
        // isOnboardingFeatureEnabled can report the ai_features_disabled metric on fresh enrollment, which
        // asserts if PixelKit's experiment kit was never configured — an empty MockFeatureFlagger keeps every
        // metric call a no-op unless a test below configures one with a matching active experiment.
        configureExperimentKit(featureFlagger: PrivacyConfig.MockFeatureFlagger())
    }

    private func configureExperimentKit(featureFlagger: FeatureFlagger) {
        PixelKit.configureExperimentKit(
            featureFlagger: featureFlagger,
            eventTracker: ExperimentEventTracker(),
            fire: { [weak self] event, _, _ in self?.firedEvents.append(event) }
        )
    }

    func test_isOnboardingFeatureEnabled_onFreeTrialAndEnrolledAsTreatment_returnsTrue() async {
        let isEnabled = await isFeatureEnabled(hasActiveTrialOffer: true,
                                               resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsSep2026Cohort.treatment)

        XCTAssertTrue(isEnabled)
    }

    /// A paid (non-trial) subscriber is eligible too, via the separate paid-subs experiment.
    func test_isOnboardingFeatureEnabled_notOnFreeTrialAndEnrolledAsTreatment_returnsTrue() async {
        let isEnabled = await isFeatureEnabled(hasActiveTrialOffer: false,
                                               resolveCohortStub: FeatureFlag.SubscriptionOnboardingPaidSubsSep2026Cohort.treatment)

        XCTAssertTrue(isEnabled)
    }

    func test_isOnboardingFeatureEnabled_onFreeTrialButNotEnrolled_returnsFalse() async {
        let isEnabled = await isFeatureEnabled(hasActiveTrialOffer: true, resolveCohortStub: nil)

        XCTAssertFalse(isEnabled)
        XCTAssertTrue(firedEvents.isEmpty)
    }

    /// Proves the "already enrolled" branch (`resolveCohort`'s early return) threads through end-to-end.
    /// The metric-reporting guard itself — that a non-fresh enrollment must not fire `ai_features_disabled`
    /// — is covered deterministically in `SubscriptionOnboardingExperimentTests`, which can inject
    /// `isAIChatEnabled`; it can't be proven from here, since `AIChatSettings`'s real default is "enabled",
    /// which would mask a broken guard by never firing anyway.
    func test_isOnboardingFeatureEnabled_alreadyEnrolledAsTreatment_returnsTrue() async {
        let isEnabled = await isFeatureEnabled(hasActiveTrialOffer: true,
                                               resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsSep2026Cohort.treatment,
                                               isAlreadyAssigned: true)

        XCTAssertTrue(isEnabled)
    }

    /// Stubbed to enroll-as-treatment if reached, proving the fetch failure skips enrollment entirely.
    func test_isOnboardingFeatureEnabled_subscriptionFetchFails_returnsFalseAndQueriesNeitherExperiment() async {
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.resultSubscription = .failure(TestError.fetchFailed)
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingPaidSubsSep2026Cohort.treatment)

        let isEnabled = await SubscriptionFlowViewModel.isOnboardingFeatureEnabled(subscriptionManager: subscriptionManager,
                                                                                   featureFlagger: featureFlagger,
                                                                                   locale: Self.enUS)

        XCTAssertFalse(isEnabled)
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
        XCTAssertFalse(featureFlagger.didCallAssignedCohort)
    }

    // MARK: - Helper

    private enum TestError: Error {
        case fetchFailed
    }

    private func isFeatureEnabled(hasActiveTrialOffer: Bool,
                                  resolveCohortStub: (any FeatureFlagCohortDescribing)?,
                                  isAlreadyAssigned: Bool = false) async -> Bool {
        let subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(
            status: .autoRenewable,
            activeOffers: hasActiveTrialOffer ? [DuckDuckGoSubscription.Offer(type: .trial)] : []
        ))
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: resolveCohortStub, isAlreadyAssigned: isAlreadyAssigned)
        return await SubscriptionFlowViewModel.isOnboardingFeatureEnabled(subscriptionManager: subscriptionManager,
                                                                          featureFlagger: featureFlagger,
                                                                          locale: Self.enUS)
    }
}
