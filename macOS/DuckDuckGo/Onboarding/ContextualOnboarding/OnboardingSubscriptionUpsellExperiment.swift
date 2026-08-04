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

import FeatureFlags
import Foundation
import PrivacyConfig
import Subscription

/// Enrolls a user in the onboarding subscription upsell experiment.
protocol OnboardingSubscriptionUpsellEnrolling {

    /// Assigns a cohort for eligible users and returns it, so the caller can branch on the result of
    /// the same call that performed the assignment. `nil` when the user is not eligible.
    @discardableResult
    func enroll() -> FeatureFlag.OnboardingSubscriptionUpsellCohort?
}

/// The subscription state the upsell experiment needs to decide who may take part.
///
/// Deliberately narrower than `SubscriptionManager` so the eligibility gate can be tested
/// without standing up the whole subscription stack.
protocol OnboardingSubscriptionUpsellSubscriptionState {
    /// Whether the user could complete a subscription purchase on this build and platform.
    var isSubscriptionPurchaseEligible: Bool { get }
    /// Whether the user is already signed in to a subscription.
    var isUserAuthenticated: Bool { get }
}

/// A/B experiment adding a subscription upsell screen at the end of contextual onboarding.
///
/// The experiment is not a test of how many subscribers the screen produces — it exists to show that
/// adding another onboarding screen does not hurt search or app retention. Those two are the primary
/// metrics and `PixelExperimentKit` derives them from the enrollment pixel, which is why enrollment
/// is the only thing wired up so far. Secondary metric pixels land with the screen itself.
///
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

    /// Whether this user may take part in the experiment at all.
    ///
    /// Checked before `resolveCohort` so ineligible users land in neither arm. Because the primary
    /// metrics are retention, an ineligible user sitting in the control arm would be noise we could
    /// not filter out afterwards.
    ///
    /// Deliberately not gated on the onboarding rebranding: the upsell ships on every supported
    /// macOS version, so both the rebranded and legacy dialog factories present it.
    var isEligible: Bool {
        subscriptionState.isSubscriptionPurchaseEligible && !subscriptionState.isUserAuthenticated
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
