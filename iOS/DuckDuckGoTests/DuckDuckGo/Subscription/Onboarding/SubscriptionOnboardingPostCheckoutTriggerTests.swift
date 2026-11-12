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
import Persistence
import Subscription
import SubscriptionTestingUtilities
@_spi(Testing) import WideEvent
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
        // enrollInOnboardingExperimentIfNeeded can report the ai_features_disabled metric on fresh enrollment, which
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

    func test_isOnboardingFeatureEnabled_assignedFreeTrialsTreatment_returnsTrue() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.treatment,
                                                              isAlreadyAssigned: true)

        XCTAssertTrue(SubscriptionFlowViewModel.isOnboardingFeatureEnabled(featureFlagger: featureFlagger))
    }

    func test_isOnboardingFeatureEnabled_assignedPaidSubsTreatment_returnsTrue() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingPaidSubsNov2026Cohort.treatment,
                                                              isAlreadyAssigned: true)

        XCTAssertTrue(SubscriptionFlowViewModel.isOnboardingFeatureEnabled(featureFlagger: featureFlagger))
    }

    func test_isOnboardingFeatureEnabled_assignedControl_returnsFalse() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.control,
                                                              isAlreadyAssigned: true)

        XCTAssertFalse(SubscriptionFlowViewModel.isOnboardingFeatureEnabled(featureFlagger: featureFlagger))
    }

    func test_isOnboardingFeatureEnabled_notYetAssigned_returnsFalseWithoutEnrolling() {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.treatment,
                                                              isAlreadyAssigned: false)

        XCTAssertFalse(SubscriptionFlowViewModel.isOnboardingFeatureEnabled(featureFlagger: featureFlagger))
        XCTAssertFalse(featureFlagger.didCallResolveCohort)
        XCTAssertTrue(firedEvents.isEmpty)
    }

    // MARK: - Enrollment before purchase confirmation

    func test_enrollInOnboardingExperimentIfNeeded_firstPurchaseWithOnboardingStore_enrolls() {
        let featureFlagger = notYetEnrolledFeatureFlagger()

        enroll(featureFlagger: featureFlagger)

        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func test_enrollInOnboardingExperimentIfNeeded_paidPurchase_enrolls() {
        let featureFlagger = notYetEnrolledFeatureFlagger()

        enroll(isFreeTrial: false, featureFlagger: featureFlagger)

        XCTAssertTrue(featureFlagger.didCallResolveCohort)
    }

    func test_enrollInOnboardingExperimentIfNeeded_planUpdate_doesNotEnroll() {
        let featureFlagger = notYetEnrolledFeatureFlagger()

        enroll(flowType: .planUpdate, featureFlagger: featureFlagger)

        XCTAssertFalse(featureFlagger.didCallResolveCohort)
        XCTAssertFalse(featureFlagger.didCallAssignedCohort)
    }

    func test_enrollInOnboardingExperimentIfNeeded_noOnboardingStore_doesNotEnroll() {
        let featureFlagger = notYetEnrolledFeatureFlagger()

        enroll(hasOnboardingStore: false, featureFlagger: featureFlagger)

        XCTAssertFalse(featureFlagger.didCallResolveCohort)
        XCTAssertFalse(featureFlagger.didCallAssignedCohort)
    }

    // MARK: - Helper

    private func notYetEnrolledFeatureFlagger() -> PrivacyConfig.MockFeatureFlagger {
        PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.treatment,
                                         isAlreadyAssigned: false)
    }

    private func enroll(flowType: SubscriptionFlowType = .firstPurchase,
                        hasOnboardingStore: Bool = true,
                        isFreeTrial: Bool = true,
                        featureFlagger: FeatureFlagger) {
        SubscriptionFlowViewModel.enrollInOnboardingExperimentIfNeeded(flowType: flowType,
                                                                        hasOnboardingStore: hasOnboardingStore,
                                                                        isFreeTrial: isFreeTrial,
                                                                        featureFlagger: featureFlagger,
                                                                        locale: Self.enUS)
    }
}

final class SubscriptionFlowViewModelOnboardingHookTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PixelKit.configureExperimentKit(featureFlagger: PrivacyConfig.MockFeatureFlagger(),
                                        eventTracker: ExperimentEventTracker(),
                                        fire: { _, _, _ in })
    }

    @MainActor
    func test_setupTransactionObserver_appStoreTransactionCompleted_runsOnboardingEnrollment() async {
        let featureFlagger = PrivacyConfig.MockFeatureFlagger(resolveCohortStub: FeatureFlag.SubscriptionOnboardingFreeTrialsNov2026Cohort.treatment,
                                                              isAlreadyAssigned: false)
        let subFeature = makeSubscriptionFeature()
        let sut = makeViewModel(subFeature: subFeature, featureFlagger: featureFlagger)

        await sut.setupTransactionObserver()
        subFeature.onAppStoreTransactionCompleted?(true)

        XCTAssertTrue(featureFlagger.didCallAssignedCohort)
    }

    // MARK: - Helper

    @MainActor
    private func makeSubscriptionFeature() -> DefaultSubscriptionPagesUseSubscriptionFeature {
        let subscriptionManager = SubscriptionManagerMock()
        let purchaseFlow = AppStorePurchaseFlowMock()
        let wideEvent = WideEventMock()
        return DefaultSubscriptionPagesUseSubscriptionFeature(
            subscriptionManager: subscriptionManager,
            subscriptionFeatureAvailability: SubscriptionFeatureAvailabilityMock(isSubscriptionPurchaseAllowed: true),
            subscriptionAttributionOrigin: nil,
            appStorePurchaseFlow: purchaseFlow,
            appStoreRestoreFlow: AppStoreRestoreFlowMock(),
            subscriptionDataReporter: nil,
            internalUserDecider: PrivacyConfig.MockInternalUserDecider(isInternalUser: false),
            wideEvent: wideEvent,
            pendingTransactionHandler: MockPendingTransactionHandler(),
            subscriptionFlowsExecuter: DefaultSubscriptionFlowsExecuter(subscriptionManager: subscriptionManager,
                                                                         appStorePurchaseFlow: purchaseFlow,
                                                                         wideEvent: wideEvent,
                                                                         pendingTransactionHandler: MockPendingTransactionHandler()),
            requestValidator: ScriptRequestValidatorMock(),
            subscriptionExperimentAttributionProvider: DefaultSubscriptionExperimentAttributionProvider(featureFlagger: PrivacyConfig.MockFeatureFlagger()))
    }

    @MainActor
    private func makeViewModel(subFeature: DefaultSubscriptionPagesUseSubscriptionFeature,
                               featureFlagger: FeatureFlagger) -> SubscriptionFlowViewModel {
        SubscriptionFlowViewModel(initialURL: URL(string: "https://duckduckgo.com/subscriptions")!,
                                  flowType: .firstPurchase,
                                  userScript: SubscriptionPagesUserScript(),
                                  userScriptsDependencies: DefaultScriptSourceProvider.Dependencies.makeMock(),
                                  subFeature: subFeature,
                                  subscriptionManager: SubscriptionManagerMock(),
                                  featureFlagger: featureFlagger,
                                  wideEvent: WideEventMock(),
                                  dataBrokerProtectionViewControllerProvider: nil,
                                  onboardingKeyValueStore: InMemoryOnboardingStore(),
                                  meetsPIRLocaleRequirement: { false })
    }
}

private final class InMemoryOnboardingStore: ThrowingKeyValueStoring {
    private var values: [String: Any] = [:]

    func object(forKey key: String) throws -> Any? {
        values[key]
    }

    func set(_ value: Any?, forKey key: String) throws {
        values[key] = value
    }

    func removeObject(forKey key: String) throws {
        values.removeValue(forKey: key)
    }
}
