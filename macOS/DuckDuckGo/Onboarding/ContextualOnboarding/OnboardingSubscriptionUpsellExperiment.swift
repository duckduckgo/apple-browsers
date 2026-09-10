//
//  OnboardingSubscriptionUpsellExperiment.swift
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
import Foundation
import PrivacyConfig
import Subscription

/// Enrolls a user in the onboarding subscription upsell experiment.
protocol OnboardingSubscriptionUpsellEnrolling {

    /// The already-assigned cohort, or `nil` when never enrolled. Never assigns.
    var cohort: FeatureFlag.OnboardingSubscriptionUpsellCohort? { get }

    /// Assigns a cohort for eligible users and returns it. `nil` when the user is not eligible.
    @discardableResult
    func enroll() -> FeatureFlag.OnboardingSubscriptionUpsellCohort?
}

/// Narrower than `SubscriptionManager` so the eligibility gate can be tested on its own.
protocol OnboardingSubscriptionUpsellSubscriptionState {
    var isSubscriptionPurchaseEligible: Bool { get }
    var isUserAuthenticated: Bool { get }
}

/// A/B experiment adding a subscription upsell screen at the end of contextual onboarding. Primary
/// metrics are search and app retention, derived by `PixelExperimentKit` from the enrollment pixel.
/// https://app.asana.com/1/137249556945/task/1210565180535541
struct OnboardingSubscriptionUpsellExperiment: OnboardingSubscriptionUpsellEnrolling {

    private let featureFlagger: FeatureFlagger
    private let subscriptionState: OnboardingSubscriptionUpsellSubscriptionState

    init(featureFlagger: FeatureFlagger, subscriptionState: OnboardingSubscriptionUpsellSubscriptionState) {
        self.featureFlagger = featureFlagger
        self.subscriptionState = subscriptionState
    }

    init(featureFlagger: FeatureFlagger, subscriptionManager: any SubscriptionManager) {
        self.init(featureFlagger: featureFlagger,
                  subscriptionState: SubscriptionManagerUpsellSubscriptionState(subscriptionManager: subscriptionManager))
    }

    /// Checked before `resolveCohort` so ineligible users land in neither arm.
    var isEligible: Bool {
        subscriptionState.isSubscriptionPurchaseEligible && !subscriptionState.isUserAuthenticated
    }

    var cohort: FeatureFlag.OnboardingSubscriptionUpsellCohort? {
        featureFlagger.assignedCohort(for: FeatureFlag.onboardingSubscriptionUpsell) as? FeatureFlag.OnboardingSubscriptionUpsellCohort
    }

    @discardableResult
    func enroll() -> FeatureFlag.OnboardingSubscriptionUpsellCohort? {
        guard isEligible else { return nil }
        return featureFlagger.resolveCohort(for: FeatureFlag.onboardingSubscriptionUpsell) as? FeatureFlag.OnboardingSubscriptionUpsellCohort
    }
}

/// Adapts the app's `SubscriptionManager` to the narrow state the experiment reads.
private struct SubscriptionManagerUpsellSubscriptionState: OnboardingSubscriptionUpsellSubscriptionState {

    private let subscriptionManager: any SubscriptionManager

    init(subscriptionManager: any SubscriptionManager) {
        self.subscriptionManager = subscriptionManager
    }

    var isSubscriptionPurchaseEligible: Bool { subscriptionManager.isSubscriptionPurchaseEligible }

    var isUserAuthenticated: Bool { subscriptionManager.isUserAuthenticated }
}
