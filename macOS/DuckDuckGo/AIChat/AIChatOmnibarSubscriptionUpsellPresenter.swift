//
//  AIChatOmnibarSubscriptionUpsellPresenter.swift
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
import os.log
import PixelKit

/// Routes a gated Duck.ai omnibar selection (a model or a reasoning effort) to the matching
/// subscription purchase / upgrade flow. Mirrors iOS's `DuckAISubscriptionUpselling`, adapted to
/// macOS's `SubscriptionNavigationCoordinator`-based navigation instead of a settings deep link.
@MainActor
protocol AIChatOmnibarSubscriptionUpselling {
    /// Routes a gated selection to the matching purchase/upgrade flow and fires the upsell pixel.
    /// Returns `false` when no flow applies (e.g. the tier already satisfies `requiredTier`).
    @discardableResult
    func routeGatedSelection(requiredTier: AIChatModelPublicAccessTier, userTier: AIChatUserTier, origin: SubscriptionFunnelOrigin) -> Bool

    /// Opens the subscription activation flow, for a user who already has a subscription (e.g.
    /// purchased on another device) and wants to sign in rather than purchase again.
    func presentSubscriptionActivation()
}

@MainActor
struct AIChatOmnibarSubscriptionUpsellPresenter: AIChatOmnibarSubscriptionUpselling {

    private static let featurePage = "duckai"

    private let coordinator: SubscriptionNavigationCoordinator

    init(coordinator: SubscriptionNavigationCoordinator) {
        self.coordinator = coordinator
    }

    @discardableResult
    func routeGatedSelection(requiredTier: AIChatModelPublicAccessTier, userTier: AIChatUserTier, origin: SubscriptionFunnelOrigin) -> Bool {
        switch userTier.upgradeFlow(for: requiredTier) {
        case .purchase:
            firePixel(currentTier: userTier, requiredTier: requiredTier, flowType: "purchase")
            coordinator.navigateToSubscriptionPurchase(origin: origin.rawValue, featurePage: Self.featurePage)
            return true
        case .upgrade:
            firePixel(currentTier: userTier, requiredTier: requiredTier, flowType: "upgrade")
            coordinator.navigateToSubscriptionPlans(origin: origin.rawValue, featurePage: Self.featurePage)
            return true
        case .none:
            Logger.aiChat.debug("No subscription flow for gated Duck.ai selection")
            return false
        }
    }

    func presentSubscriptionActivation() {
        coordinator.navigateToSubscriptionActivation()
    }

    private func firePixel(currentTier: AIChatUserTier, requiredTier: AIChatModelPublicAccessTier, flowType: String) {
        PixelKit.fire(
            AIChatPixel.aiChatAddressBarSubscriptionUpsellTriggered(
                currentTier: currentTier.rawValue,
                requiredTier: requiredTier.rawValue,
                flowType: flowType
            ),
            frequency: .dailyAndCount,
            includeAppVersionParameter: true
        )
    }
}
