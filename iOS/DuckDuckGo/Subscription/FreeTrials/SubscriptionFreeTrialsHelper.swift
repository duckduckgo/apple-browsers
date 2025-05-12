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

protocol SubscriptionFreeTrialsHelping {
    var areFreeTrialsAvailable: Bool { get }
    var origin: String  { get }
}

struct SubscriptionFreeTrialsHelper: SubscriptionFreeTrialsHelping {
    /// Constants used by the helper.
    enum Constants {
        /// The origin parameter value for this privacy pro promotion funnel.
        static let origin = "TBD"
    }

    /// The feature flagging service used to determine if the promotion should be shown.
    private let featureFlagger: FeatureFlagger

    var areFreeTrialsAvailable: Bool {
        return featureFlagger.isFeatureOn(for: FeatureFlag.privacyProFreeTrial, allowOverride: true)
    }

    let origin = Constants.origin

    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.featureFlagger = featureFlagger
    }
}
