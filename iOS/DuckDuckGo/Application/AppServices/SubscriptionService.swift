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
import PrivacyConfig
import WebKit
import Core
import WKAbstractions
import Persistence

final class SubscriptionService {

    let subscriptionFeatureAvailability: DefaultSubscriptionFeatureAvailability
    private let subscriptionManager = AppDependencyProvider.shared.subscriptionManager
    private let tokenRefreshTask: SubscriptionTokenRefreshTask
    private var cancellables: Set<AnyCancellable> = []

    init(application: UIApplication = UIApplication.shared,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         keyValueStore: ThrowingKeyValueStoring,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         onboardingVPNExperimentMetrics: OnboardingVPNDownloadReasonExperimentMetrics,
         notificationCenter: NotificationCenter) {
        subscriptionFeatureAvailability = DefaultSubscriptionFeatureAvailability(
                    privacyConfigurationManager: privacyConfigurationManager,
                    purchasePlatform: .appStore,
                    featureFlagProvider: SubscriptionPageFeatureFlagAdapter(featureFlagger: featureFlagger)
                )
        let debugSettings = SubscriptionTokenRefreshDebugSettings(keyValueStore: keyValueStore)
        let intervals = SubscriptionTokenRefreshIntervals(debugSettings: debugSettings,
                                                          isInternalUser: { featureFlagger.internalUserDecider.isInternalUser })
        let keepAlive = SubscriptionTokenKeepAlive(tokenProvider: subscriptionManager,
                                                   isEnabled: { featureFlagger.isFeatureOn(.authBackgroundTokenRefresh) },
                                                   maxRefreshTokenAge: intervals.maxRefreshTokenAge,
                                                   retryInterval: intervals.retryInterval)
        tokenRefreshTask = SubscriptionTokenRefreshTask(keepAlive: keepAlive,
                                                        debugSettings: debugSettings,
                                                        retryInterval: intervals.retryInterval)
        tokenRefreshTask.register()

        Task {
            await subscriptionManager.loadInitialData()
        }
        recordPurchasesForOnboardingVPNExperiment(metrics: onboardingVPNExperimentMetrics,
                                                  featureFlagger: featureFlagger,
                                                  notificationCenter: notificationCenter)
    }

    /// New subscriptions from any entry point count. Restores and plan changes of an existing subscription don't.
    private func recordPurchasesForOnboardingVPNExperiment(metrics: OnboardingVPNDownloadReasonExperimentMetrics,
                                                           featureFlagger: FeatureFlagger,
                                                           notificationCenter: NotificationCenter) {
        let subfeatureID = PrivacyProSubfeature.onboardingVPNDownloadReasonExperiment.rawValue
        notificationCenter.publisher(for: .userDidStartNewSubscription)
            .sink { _ in
                metrics.recordSubscriptionPurchase(enrollmentDate: featureFlagger.allActiveExperiments[subfeatureID]?.enrollmentDate,
                                                   now: Date())
            }
            .store(in: &cancellables)
    }

    // MARK: - Resume

    func resume() {
        Task { [subscriptionManager, tokenRefreshTask] in
            await subscriptionManager.restoreMissingTokenIfPossible()
            await tokenRefreshTask.refreshAndSchedule().value
        }
    }
}
