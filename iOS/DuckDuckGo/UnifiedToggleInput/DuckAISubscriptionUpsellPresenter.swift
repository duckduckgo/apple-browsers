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

import Foundation
import Subscription

/// Routes the Duck.ai subscription purchase / upgrade flows triggered by tapping a gated
/// model or reasoning level. The flows are decoupled via NotificationCenter
/// (`.settingsDeepLinkNotification`) so this needs no presenting view controller — which lets
/// the iPhone `UnifiedToggleInputCoordinator` and the iPad omnibar controllers share it.
protocol DuckAISubscriptionUpselling {
    func presentPurchaseFlow(source: SubscriptionFlowSource, isAITabState: Bool)
    func presentUpgradeFlow(source: SubscriptionFlowSource, isAITabState: Bool)
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
