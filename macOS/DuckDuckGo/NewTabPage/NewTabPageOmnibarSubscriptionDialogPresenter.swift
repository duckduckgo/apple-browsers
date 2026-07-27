//
//  NewTabPageOmnibarSubscriptionDialogPresenter.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import AIChat
import NewTabPage
import PixelKit
import Subscription

/// Unlike the address bar's presenter, the web already knows which flow to use, so this skips
/// `routeGatedSelection` and calls the matching message directly.
@MainActor
final class NewTabPageOmnibarSubscriptionDialogPresenter: NewTabPageOmnibarSubscriptionDialogPresenting {

    private static let featurePage = "duckai"

    private let coordinator: SubscriptionNavigationCoordinator
    private let subscriptionManager: any SubscriptionManager

    init(coordinator: SubscriptionNavigationCoordinator, subscriptionManager: any SubscriptionManager) {
        self.coordinator = coordinator
        self.subscriptionManager = subscriptionManager
    }

    func showSubscriptionUpsellDialog(source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) async {
        makeUpsellDialog(userTier: await resolveUserTier(), source: source).show()
    }

    func showSubscriptionUpgradeDialog(source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) {
        makeUpgradeDialog(source: source).show()
    }

    /// Checks `userTier == .free` before trusting StoreKit eligibility — trial eligibility is
    /// independent of subscription tier, so an existing subscriber could otherwise still read as eligible.
    func makeUpsellDialog(userTier: AIChatUserTier, source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) -> AIChatSubscriptionUpsellDialog {
        var dialog: AIChatSubscriptionUpsellDialog = .upsell(
            isEligibleForFreeTrial: userTier == .free && subscriptionManager.isUserEligibleForFreeTrial()
        )
        dialog.onSubscribe = { [coordinator] in
            coordinator.navigateToSubscriptionPurchase(origin: SubscriptionFunnelOrigin.newTabPageOmnibar.rawValue, featurePage: Self.featurePage)
            Self.firePixel(flowType: "purchase", source: source)
        }
        dialog.onHaveSubscription = { [coordinator] in
            coordinator.navigateToSubscriptionActivation()
        }
        return dialog
    }

    /// Fires only for an existing Plus subscriber gated to Pro.
    func makeUpgradeDialog(source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) -> AIChatSubscriptionUpsellDialog {
        var dialog: AIChatSubscriptionUpsellDialog = .proUpgrade()
        dialog.onSubscribe = { [coordinator] in
            coordinator.navigateToSubscriptionPlans(origin: SubscriptionFunnelOrigin.newTabPageOmnibar.rawValue, featurePage: Self.featurePage)
            Self.firePixel(flowType: "upgrade", source: source)
        }
        dialog.onHaveSubscription = { [coordinator] in
            coordinator.navigateToSubscriptionActivation()
        }
        return dialog
    }

    /// Mirrors `NewTabPageOmnibarModelsProvider.resolveUserTier()`; not shared since a cached value
    /// from one could be stale for the other's unrelated call timing.
    private func resolveUserTier() async -> AIChatUserTier {
        do {
            guard let subscription = try await subscriptionManager.getSubscription(),
                  subscription.isActive else { return .free }
            switch subscription.tier {
            case .plus: return .plus
            case .pro: return .pro
            case .none: return .free
            }
        } catch {
            return .free
        }
    }

    private static func firePixel(flowType: String, source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) {
        PixelKit.fire(
            AIChatPixel.aiChatNtpSubscriptionUpsellTriggered(flowType: flowType, source: source.rawValue),
            frequency: .dailyAndCount,
            includeAppVersionParameter: true
        )
    }
}
