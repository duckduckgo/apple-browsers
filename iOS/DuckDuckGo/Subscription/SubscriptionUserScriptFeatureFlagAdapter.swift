//
//  SubscriptionUserScriptFeatureFlagAdapter.swift
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

import PrivacyConfig
import Core
import Subscription

/// Adapter that provides feature flags to SubscriptionUserScript
/// This follows the adapter pattern to avoid direct BSK dependencies in the Subscription module
struct SubscriptionUserScriptFeatureFlagAdapter: SubscriptionUserScriptFeatureFlagProviding {

    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    var usePaidDuckAi: Bool {
        featureFlagger.isFeatureOn(.paidAIChat)
    }

    var useProTier: Bool {
        featureFlagger.isFeatureOn(.allowProTierPurchase)
    }
}
