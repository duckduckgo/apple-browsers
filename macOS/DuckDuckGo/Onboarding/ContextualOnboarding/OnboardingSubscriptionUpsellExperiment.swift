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

import Foundation
import Subscription

protocol OnboardingSubscriptionUpsellEnrolling {
    var isEligible: Bool { get }
}

/// Narrower than `SubscriptionManager` so the eligibility gate can be tested on its own.
protocol OnboardingSubscriptionUpsellSubscriptionState {
    var isSubscriptionPurchaseEligible: Bool { get }
    var isUserAuthenticated: Bool { get }
}

/// https://app.asana.com/1/137249556945/task/1210565180535541
struct OnboardingSubscriptionUpsellExperiment: OnboardingSubscriptionUpsellEnrolling {

    private let subscriptionState: OnboardingSubscriptionUpsellSubscriptionState

    init(subscriptionState: OnboardingSubscriptionUpsellSubscriptionState) {
        self.subscriptionState = subscriptionState
    }

    init(subscriptionManager: any SubscriptionManager) {
        self.init(subscriptionState: SubscriptionManagerUpsellSubscriptionState(subscriptionManager: subscriptionManager))
    }

    var isEligible: Bool {
        subscriptionState.isSubscriptionPurchaseEligible && !subscriptionState.isUserAuthenticated
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
