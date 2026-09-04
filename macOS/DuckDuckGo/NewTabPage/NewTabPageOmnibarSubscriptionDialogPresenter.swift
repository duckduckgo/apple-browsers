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
    private let pixelFiring: PixelFiring?
    // Allows tests to exercise the show flow without presenting an AppKit dialog.
    private let showDialog: @MainActor (AIChatSubscriptionUpsellDialog) -> Void

    init(coordinator: SubscriptionNavigationCoordinator,
         subscriptionManager: any SubscriptionManager,
         pixelFiring: PixelFiring? = PixelKit.shared,
         showDialog: @escaping @MainActor (AIChatSubscriptionUpsellDialog) -> Void = { @MainActor dialog in dialog.show() }) {
        self.coordinator = coordinator
        self.subscriptionManager = subscriptionManager
        self.pixelFiring = pixelFiring
        self.showDialog = showDialog
    }

    func showSubscriptionUpsellDialog(source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) async {
        fireGatedRowClick(source: source)
        fireDialogShown(source: source)
        showDialog(makeUpsellDialog(userTier: await resolveUserTier(), source: source))
    }

    func showSubscriptionUpgradeDialog(source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) {
        fireGatedRowClick(source: source)
        fireDialogShown(source: source)
        showDialog(makeUpgradeDialog(source: source))
    }

    /// Checks `userTier == .free` before trusting StoreKit eligibility — trial eligibility is
    /// independent of subscription tier, so an existing subscriber could otherwise still read as eligible.
    func makeUpsellDialog(userTier: AIChatUserTier, source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) -> AIChatSubscriptionUpsellDialog {
        var dialog: AIChatSubscriptionUpsellDialog = .upsell(
            isEligibleForFreeTrial: userTier == .free && subscriptionManager.isUserEligibleForFreeTrial()
        )
        dialog.onSubscribe = { [self, coordinator] in
            coordinator.navigateToSubscriptionPurchase(origin: Self.origin(for: source).rawValue, featurePage: Self.featurePage)
            firePixel(flowType: "purchase", source: source)
        }
        dialog.onHaveSubscription = { [coordinator] in
            coordinator.navigateToSubscriptionActivation()
        }
        return dialog
    }

    /// Fires only for an existing Plus subscriber gated to Pro.
    func makeUpgradeDialog(source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) -> AIChatSubscriptionUpsellDialog {
        var dialog: AIChatSubscriptionUpsellDialog = .proUpgrade()
        dialog.onSubscribe = { [self, coordinator] in
            coordinator.navigateToSubscriptionPlans(origin: Self.origin(for: source).rawValue, featurePage: Self.featurePage)
            firePixel(flowType: "upgrade", source: source)
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

    /// Which picker the user was gated in, so the funnel attributes the entry point rather than
    /// lumping both pickers under one omnibar origin.
    static func origin(for source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) -> SubscriptionFunnelOrigin {
        switch source {
        case .model: .newTabPageModelPicker
        case .reasoning: .newTabPageReasoningDropdown
        }
    }

    /// The NTP picker is web: this is the native side of a gated-row tap.
    private func fireGatedRowClick(source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) {
        pixelFiring?.fire(
            AIChatPixel.aiChatNtpGatedRowClick(origin: Self.origin(for: source).rawValue),
            frequency: .dailyAndCount)
    }

    private func fireDialogShown(source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) {
        pixelFiring?.fire(
            AIChatPixel.aiChatNtpSubscriptionUpsellShown(origin: Self.origin(for: source).rawValue),
            frequency: .dailyAndCount)
    }

    private func firePixel(flowType: String, source: NewTabPageDataModel.OmnibarSubscriptionUpsellSource) {
        pixelFiring?.fire(
            AIChatPixel.aiChatNtpSubscriptionUpsellTriggered(flowType: flowType,
                                                             source: source.rawValue,
                                                             origin: Self.origin(for: source).rawValue),
            frequency: .dailyAndCount)
    }
}
