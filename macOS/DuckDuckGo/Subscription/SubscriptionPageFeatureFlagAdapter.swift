//
//  SubscriptionPageFeatureFlagAdapter.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Foundation
import PrivacyConfig

/// Adapts the app's FeatureFlagger to the SubscriptionPageFeatureFlagProvider protocol
/// This keeps the Subscription module decoupled from the app's feature flag system
struct SubscriptionPageFeatureFlagAdapter: SubscriptionPageFeatureFlagProviding {
    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    func isEnabled(_ flag: SubscriptionPageFeatureFlag) -> Bool {
        switch flag {
        case .paidAIChat:
            return featureFlagger.isFeatureOn(.paidAIChat)
        case .proTierPurchase:
            return featureFlagger.isFeatureOn(.allowProTierPurchase)
        case .supportsAlternateStripePaymentFlow:
            return featureFlagger.isFeatureOn(.supportsAlternateStripePaymentFlow)
        }
    }
}
