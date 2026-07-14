//
//  SubscriptionPageFeatureFlagAdapterTests.swift
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
import FeatureFlags
import PrivacyConfig
import Testing
@testable import DuckDuckGo_Privacy_Browser

@Suite("SubscriptionPageFeatureFlagAdapter Tests")
struct SubscriptionPageFeatureFlagAdapterTests {

    @Test("Flag mapping correctness", arguments: [
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
}
