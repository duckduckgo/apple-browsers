//
//  OnboardingSubscriptionUpsellEligibility.swift
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

/// Decides whether the subscription upsell can follow High Five.
protocol OnboardingSubscriptionUpsellEligibilityChecking {
    /// The remote kill switch. Cheap, so it is read on every decision.
    var isUpsellEnabled: Bool { get }

    /// Whether the user can buy a subscription and doesn't already have one, or `nil` while this launch
    /// can't tell yet. Reads the keychain, so the ending reads it once and saves the answer.
    var isUserEligible: Bool? { get }
}

/// Subscription upsell screen at the end of contextual onboarding, shown to users who can buy a
/// subscription and don't already have one.
/// https://app.asana.com/1/137249556945/project/1207260194172075/task/1219346955712864
struct OnboardingSubscriptionUpsellEligibility: OnboardingSubscriptionUpsellEligibilityChecking {

    private let featureFlagger: FeatureFlagger
    private let subscriptionManager: any SubscriptionManager

    init(featureFlagger: FeatureFlagger, subscriptionManager: any SubscriptionManager) {
        self.featureFlagger = featureFlagger
        self.subscriptionManager = subscriptionManager
    }

    var isUpsellEnabled: Bool {
        featureFlagger.isFeatureOn(.onboardingSubscriptionUpsell)
    }

    var isUserEligible: Bool? {
        guard subscriptionManager.isPurchaseEligibilityKnown else { return nil }
        return subscriptionManager.isSubscriptionPurchaseEligible && !subscriptionManager.isUserAuthenticated
    }
}
