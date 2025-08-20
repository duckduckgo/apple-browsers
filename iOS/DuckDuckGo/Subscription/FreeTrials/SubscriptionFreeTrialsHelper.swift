//
//  SubscriptionFreeTrialsHelper.swift
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

import BrowserServicesKit
import Core

/// Protocol defining the interface for encapsulating subscription free trial logic.
protocol SubscriptionFreeTrialsHelping {
    /// Indicates whether free trials are currently enabled.
    var areFreeTrialsEnabled: Bool { get }
}

/// A helper struct that encapsulates subscription free trial logic.
struct SubscriptionFreeTrialsHelper: SubscriptionFreeTrialsHelping {

    /// The feature flagging service used to determine if the promotion should be shown.
    private let featureFlagger: FeatureFlagger

    /// Indicates whether free trials are currently enabled.
    /// This is determined by checking if the privacy pro free trial feature flag is enabled.
    var areFreeTrialsEnabled: Bool {
        return featureFlagger.isFeatureOn(for: FeatureFlag.privacyProFreeTrial, allowOverride: true)
    }

    /// Initializes a new instance of SubscriptionFreeTrialsHelper.
    /// - Parameter featureFlagger: The feature flagging service to use. Defaults to the shared app dependency provider's feature flagger.
    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.featureFlagger = featureFlagger
    }
}
