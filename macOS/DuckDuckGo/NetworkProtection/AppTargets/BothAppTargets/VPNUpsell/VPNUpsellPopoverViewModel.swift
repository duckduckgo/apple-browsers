//
//  VPNUpsellPopoverViewModel.swift
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
import BrowserServicesKit
import Subscription

extension VPNUpsellPopoverViewModel {
    struct FeatureStatus {
        let isEligibleForFreeTrial: Bool
        let isPIRFeatureEnabled: Bool
        let hasAIChatFeature: Bool

        static var `default`: Self {
            Self(isEligibleForFreeTrial: false, isPIRFeatureEnabled: false, hasAIChatFeature: false)
        }

        var plusFeatureCount: Int {
            var count = 1
            if hasAIChatFeature { count += 1 }
            if isPIRFeatureEnabled { count += 1 }
            return count
        }
    }
}

final class VPNUpsellPopoverViewModel {
    @Published private(set) var featureEligibility: FeatureStatus = .default

    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let featureFlagger: FeatureFlagger
    private let vpnUpsellVisibilityManager: VPNUpsellVisibilityManager
    private let urlOpener: @MainActor (URL) -> Void
    private let onDismiss: () -> Void

    init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
         featureFlagger: FeatureFlagger,
         vpnUpsellVisibilityManager: VPNUpsellVisibilityManager,
         urlOpener: @escaping @MainActor (URL) -> Void = { @MainActor url in
            Application.appDelegate.windowControllersManager.showTab(with: .contentFromURL(url, source: .appOpenUrl))
         },
         onDismiss: @escaping () -> Void)
    {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.vpnUpsellVisibilityManager = vpnUpsellVisibilityManager
        self.urlOpener = urlOpener
        self.onDismiss = onDismiss
        checkFeatureEligibility()
    }

    private func checkFeatureEligibility() {
        Task { @MainActor in
            let isPIRFeatureEnabled = try? await subscriptionManager.isFeatureIncludedInSubscription(.dataBrokerProtection)
            let isEligibleForFreeTrial = subscriptionManager.isUserEligibleForFreeTrial()
            let hasAIChatFeature = featureFlagger.isFeatureOn(.paidAIChat)

            self.featureEligibility = FeatureStatus(
                isEligibleForFreeTrial: isEligibleForFreeTrial,
                isPIRFeatureEnabled: isPIRFeatureEnabled ?? false,
                hasAIChatFeature: hasAIChatFeature
            )
        }
    }

    @MainActor
    func showSubscriptionLandingPage() {
        onDismiss()
        let url = subscriptionManager.url(for: .purchase)
        urlOpener(url)
    }

    func dismiss() {
        vpnUpsellVisibilityManager.dismissUpsell()
        onDismiss()
    }
}
