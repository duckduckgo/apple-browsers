//
//  OnboardingTryVPNFollowUpProvider.swift
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

import Foundation
import Subscription

/// What the step after Try VPN needs from the subscription and the VPN.
@MainActor
protocol OnboardingTryVPNFollowUpProviding {
    /// Whether the user's subscription includes the VPN.
    func hasVPNAccess() async -> Bool

    /// Builds the view model that turns the VPN on, reusing the subscription onboarding's.
    func makeVPNActivationViewModel() -> SubscriptionOnboardingVPNActivationViewModel
}

@MainActor
struct OnboardingTryVPNFollowUpProvider: OnboardingTryVPNFollowUpProviding {

    private let subscriptionManager: any SubscriptionManager

    init(subscriptionManager: any SubscriptionManager) {
        self.subscriptionManager = subscriptionManager
    }

    func hasVPNAccess() async -> Bool {
        (try? await subscriptionManager.isFeatureEnabled(.networkProtection)) ?? false
    }

    func makeVPNActivationViewModel() -> SubscriptionOnboardingVPNActivationViewModel {
        SubscriptionOnboardingVPNActivationViewModel(prefetcher: SubscriptionOnboardingPrefetcher(pixelFiring: nil))
    }

}
