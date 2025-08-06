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
import PixelKit
import Subscription

extension VPNUpsellPopoverViewModel {
    struct FeatureSet {
        let core: [Feature]
        let plus: [Feature]
        let isEligibleForFreeTrial: Bool

        var mainCTATitle: String {
            isEligibleForFreeTrial ? UserText.vpnUpsellPopoverFreeTrialCTA : UserText.vpnUpsellPopoverLearnMoreCTA
        }

        var plusFeaturesSubtitle: String {
            let plusCount = plus.count
            return plusCount > 1 ? String(format: UserText.vpnUpsellPopoverPlusFeaturesSubtitleCount, plusCount) : UserText.vpnUpsellPopoverPlusFeaturesSubtitle
        }
    }

    enum Feature: Equatable {
        case hideIPAddress
        case shieldOnlineActivity
        case blockHarmfulSites
        case aiChat
        case identityTheftProtection
        case pir

        var title: String {
            switch self {
            case .hideIPAddress:
                return UserText.hideIPAddressFeatureTitle
            case .shieldOnlineActivity:
                return UserText.shieldOnlineActivityFeatureTitle
            case .blockHarmfulSites:
                return UserText.blockHarmfulSitesFeatureTitle
            case .aiChat:
                return UserText.aiChatFeatureTitle
            case .identityTheftProtection:
                return UserText.identityTheftProtectionFeatureTitle
            case .pir:
                return UserText.pirFeatureTitle
            }
        }

        var subtitle: String? {
            switch self {
            case .pir:
                return "(\(UserText.pirFeatureSubtitle))"
            default:
                return nil
            }
        }
    }
}

@MainActor
final class VPNUpsellPopoverViewModel: ObservableObject {
    @Published private(set) var featureSet: FeatureSet = FeatureSet(core: [], plus: [], isEligibleForFreeTrial: false)

    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let featureFlagger: FeatureFlagger
    private let vpnUpsellVisibilityManager: VPNUpsellVisibilityManager
    private let urlOpener: @MainActor (URL) -> Void
    private let onDismiss: () -> Void
    private let pixelHandler: (PrivacyProPixel) -> Void

    private let coreFeatures: [Feature] = [
        .hideIPAddress,
        .shieldOnlineActivity,
        .blockHarmfulSites
    ]

    init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
         featureFlagger: FeatureFlagger,
         vpnUpsellVisibilityManager: VPNUpsellVisibilityManager,
         urlOpener: @escaping @MainActor (URL) -> Void = { @MainActor url in
            Application.appDelegate.windowControllersManager.showTab(with: .contentFromURL(url, source: .appOpenUrl))
         },
         onDismiss: @escaping () -> Void,
         pixelHandler: @escaping (PrivacyProPixel) -> Void = { PixelKit.fire($0) })
    {
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
        self.vpnUpsellVisibilityManager = vpnUpsellVisibilityManager
        self.urlOpener = urlOpener
        self.onDismiss = onDismiss
        self.pixelHandler = pixelHandler

        checkFeatureEligibility()
    }

    private func checkFeatureEligibility() {
        Task {
            let isPIRFeatureEnabled = try? await subscriptionManager.isFeatureIncludedInSubscription(.dataBrokerProtection)
            let isEligibleForFreeTrial = subscriptionManager.isUserEligibleForFreeTrial()
            let hasAIChatFeature = featureFlagger.isFeatureOn(.paidAIChat)

            updateFeatures(isEligibleForFreeTrial: isEligibleForFreeTrial,
                           isPIRFeatureEnabled: isPIRFeatureEnabled ?? false,
                           hasAIChatFeature: hasAIChatFeature)
        }
    }

    private func updateFeatures(isEligibleForFreeTrial: Bool,
                                isPIRFeatureEnabled: Bool,
                                hasAIChatFeature: Bool) {

        var plusFeatures: [Feature] = []

        if hasAIChatFeature {
            plusFeatures.append(.aiChat)
        }

        plusFeatures.append(.identityTheftProtection)

        if isPIRFeatureEnabled {
            plusFeatures.append(.pir)
        }

        featureSet = FeatureSet(core: coreFeatures,
                                plus: plusFeatures,
                                isEligibleForFreeTrial: isEligibleForFreeTrial)
    }

    func showSubscriptionLandingPage() {
        pixelHandler(.privacyProToolbarButtonPopoverProceedButtonClicked)
        onDismiss()

        guard let components = SubscriptionURL.purchaseURLComponentsWithOrigin(SubscriptionFunnelOrigin.vpnUpsell.rawValue),
              let url = components.url else {
            // Fallback to original URL
            let url = subscriptionManager.url(for: .purchase)
            urlOpener(url)
            return
        }

        urlOpener(url)
    }

    func dismiss() {
        pixelHandler(.privacyProToolbarButtonPopoverDismissButtonClicked)
        vpnUpsellVisibilityManager.dismissUpsell()
        onDismiss()
    }
}
