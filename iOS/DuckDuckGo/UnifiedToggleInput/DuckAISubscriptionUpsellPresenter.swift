//
//  DuckAISubscriptionUpsellPresenter.swift
//  DuckDuckGo
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
import Foundation
import os.log
import Subscription

/// Routes the Duck.ai subscription purchase / upgrade flows triggered by tapping a gated
/// model or reasoning level.
protocol DuckAISubscriptionUpselling {
    func presentPurchaseFlow(source: SubscriptionFlowSource, isAITabState: Bool)
    func presentUpgradeFlow(source: SubscriptionFlowSource, isAITabState: Bool)
}

extension DuckAISubscriptionUpselling {

    /// Routes a gated Duck.ai control selection (a model or a reasoning level) to the matching
    /// subscription upsell and fires the upsell-triggered pixel. Returns `true` when a flow was
    /// presented
    @discardableResult
    func routeGatedSelection(
        requiredTier: AIChatModelPublicAccessTier,
        userTier: AIChatUserTier,
        source: SubscriptionFlowSource,
        isAITabState: Bool
    ) -> Bool {
        switch userTier.upgradeFlow(for: requiredTier) {
        case .purchase:
            UnifiedToggleInputCoordinatorPixelHelper.fireSubscriptionUpsellTriggeredPixel(
                source: source,
                currentTier: userTier,
                requiredTier: requiredTier,
                flowType: .purchase,
                isAITabState: isAITabState
            )
            presentPurchaseFlow(source: source, isAITabState: isAITabState)
            return true
        case .upgrade:
            UnifiedToggleInputCoordinatorPixelHelper.fireSubscriptionUpsellTriggeredPixel(
                source: source,
                currentTier: userTier,
                requiredTier: requiredTier,
                flowType: .upgrade,
                isAITabState: isAITabState
            )
            presentUpgradeFlow(source: source, isAITabState: isAITabState)
            return true
        case .none:
            switch source {
            case .modelPicker:
                Logger.unifiedInputState.debug("No native subscription flow for gated model")
            case .reasoningPicker:
                Logger.unifiedInputState.debug("No native subscription flow for gated reasoning mode")
            }
            return false
        }
    }
}

struct DuckAISubscriptionUpsellPresenter: DuckAISubscriptionUpselling {

    private static let subscriptionFeaturePage = "duckai"

    private let notificationCenter: NotificationCenter

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    func presentPurchaseFlow(source: SubscriptionFlowSource, isAITabState: Bool) {
        notificationCenter.post(
            name: .settingsDeepLinkNotification,
            object: SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow(
                redirectURLComponents: makeRedirectURLComponents(source: source, isAITabState: isAITabState)
            )
        )
    }

    func presentUpgradeFlow(source: SubscriptionFlowSource, isAITabState: Bool) {
        notificationCenter.post(
            name: .settingsDeepLinkNotification,
            object: SettingsViewModel.SettingsDeepLinkSection.subscriptionPlanChangeFlow(
                redirectURLComponents: makeRedirectURLComponents(source: source, isAITabState: isAITabState)
            )
        )
    }

    private func makeRedirectURLComponents(source: SubscriptionFlowSource, isAITabState: Bool) -> URLComponents {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "featurePage", value: Self.subscriptionFeaturePage),
            URLQueryItem(name: AttributionParameter.origin, value: origin(for: source, isAITabState: isAITabState).rawValue)
        ]
        return components
    }

    private func origin(for source: SubscriptionFlowSource, isAITabState: Bool) -> SubscriptionFunnelOrigin {
        switch (isAITabState, source) {
        case (true, .modelPicker):
            return .duckAIModelPicker
        case (true, .reasoningPicker):
            return .duckAIReasoningPicker
        case (false, .modelPicker):
            return .addressBarModelPicker
        case (false, .reasoningPicker):
            return .addressBarReasoningPicker
        }
    }
}
