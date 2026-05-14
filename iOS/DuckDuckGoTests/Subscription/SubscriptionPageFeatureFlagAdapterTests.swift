//
//  SubscriptionPageFeatureFlagAdapterTests.swift
//  DuckDuckGo
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

import Testing
import BrowserServicesKit
@testable import DuckDuckGo
import Core

@Suite("SubscriptionPageFeatureFlagAdapter Tests")
struct SubscriptionPageFeatureFlagAdapterTests {
    
    @Test("Flag mapping correctness", arguments: [
        (SubscriptionPageFeatureFlag.paidAIChat, FeatureFlag.paidAIChat, true),
        (SubscriptionPageFeatureFlag.paidAIChat, FeatureFlag.paidAIChat, false),
        (SubscriptionPageFeatureFlag.proTierPurchase, FeatureFlag.allowProTierPurchase, true),
        (SubscriptionPageFeatureFlag.proTierPurchase, FeatureFlag.allowProTierPurchase, false),
        (SubscriptionPageFeatureFlag.supportsAlternateStripePaymentFlow, FeatureFlag.supportsAlternateStripePaymentFlow, true),
        (SubscriptionPageFeatureFlag.supportsAlternateStripePaymentFlow, FeatureFlag.supportsAlternateStripePaymentFlow, false),
    ])
    func flagMapping(
        subscriptionFlag: SubscriptionPageFeatureFlag,
        appFlag: FeatureFlag,
        isEnabled: Bool
    ) {
        let mockFlagger = MockFeatureFlagger()
        if isEnabled {
            mockFlagger.enabledFeatureFlags = [appFlag]
        }
        let adapter = SubscriptionPageFeatureFlagAdapter(featureFlagger: mockFlagger)
        
        #expect(adapter.isEnabled(subscriptionFlag) == isEnabled)
    }
    
    @Test("All flags respond independently")
    func allFlagsIndependent() {
        // Enable only paidAIChat
        let mockFlagger = MockFeatureFlagger()
        mockFlagger.enabledFeatureFlags = [.paidAIChat]

        let adapter = SubscriptionPageFeatureFlagAdapter(featureFlagger: mockFlagger)
        
        // Only paidAIChat should be enabled
        #expect(adapter.isEnabled(.paidAIChat) == true)
        #expect(adapter.isEnabled(.proTierPurchase) == false)
        #expect(adapter.isEnabled(.supportsAlternateStripePaymentFlow) == false)
    }
    
    @Test("Multiple flags can be enabled simultaneously")
    func multipleFlagsEnabled() {
        let mockFlagger = MockFeatureFlagger()
        mockFlagger.enabledFeatureFlags = [
            .paidAIChat,
            .allowProTierPurchase
        ]
        
        let adapter = SubscriptionPageFeatureFlagAdapter(featureFlagger: mockFlagger)
        
        #expect(adapter.isEnabled(.paidAIChat) == true)
        #expect(adapter.isEnabled(.proTierPurchase) == true)
        #expect(adapter.isEnabled(.supportsAlternateStripePaymentFlow) == false)
    }
}
