//
//  AttributedMetricUtils.swift
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

import Foundation
import AttributedMetric
import BrowserServicesKit
import Subscription

extension SystemDefaultBrowserProvider: AttributedMetricDefaultBrowserProviding {

    var isDefaultBrowser: Bool {
        self.isDefault
    }
}

struct DefaultBucketsSettingsProvider: BucketsSettingsProviding {

    let privacyConfig: PrivacyConfiguration

    var bucketsSettings: [String: Any] {
        privacyConfig.settings(for: .attributedMetrics)
    }
}

struct DefaultSubscriptionStateProvider: SubscriptionStateProviding {

    let subscriptionManager: SubscriptionAuthV1toV2Bridge

    func isFreeTrial() async -> Bool {
        (try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst).hasActiveTrialOffer) ?? false
    }

    var isActive: Bool {
        subscriptionManager.isUserAuthenticated
    }
}
