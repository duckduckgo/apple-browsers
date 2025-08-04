//
//  SubscriptionService.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Subscription
import Combine
import BrowserServicesKit
import WebKit
import Core
import WKAbstractions

final class SubscriptionService {

    let subscriptionFeatureAvailability: DefaultSubscriptionFeatureAvailability
    private let subscriptionManagerV1 = AppDependencyProvider.shared.subscriptionManager
    private let subscriptionManagerV2 = AppDependencyProvider.shared.subscriptionManagerV2
    private let subscriptionAuthMigrator = AppDependencyProvider.shared.subscriptionAuthMigrator
    private var cancellables: Set<AnyCancellable> = []

    init(application: UIApplication = UIApplication.shared,
         privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(privacyConfigurationManager: privacyConfigurationManager,
                                                                                 purchasePlatform: .appStore,
                                                                                 paidAIChatFlagStatusProvider: { featureFlagger.isFeatureOn(.paidAIChat) },
                                                                                 supportsAlternateStripePaymentFlowStatusProvider: { featureFlagger.isFeatureOn(.supportsAlternateStripePaymentFlow) })
        Task {
            await subscriptionManagerV1?.loadInitialData()
            await subscriptionManagerV2?.loadInitialData()
        }
    }

    // MARK: - Resume

    func resume() {
        subscriptionManagerV1?.refreshCachedSubscriptionAndEntitlements { isSubscriptionActive in // only for v1
            if isSubscriptionActive {
                DailyPixel.fire(pixel: .privacyProSubscriptionActive, withAdditionalParameters: [AuthVersion.key: AuthVersion.v1.rawValue])
            }
        }
        Task {
            await subscriptionAuthMigrator.migrateAuthV1toAuthV2IfNeeded()
        }
    }
}
