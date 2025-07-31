//
//  SubscriptionNavigationCoordinator.swift
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

/// Protocol for showing tabs and preferences in the macOS browser.
protocol SubscriptionTabsShowing {
    func showTab(with content: Tab.TabContent)
    func showPreferencesTab(withSelectedPane pane: PreferencePaneIdentifier?)
}

extension WindowControllersManager: SubscriptionTabsShowing {}

/// macOS-specific navigation coordinator for subscription web pages.
///
/// Enables Duck.ai (SERP) to navigate within the macOS app using SubscriptionUserScript by directly
/// showing preferences tabs or opening subscription URLs in new tabs.
///
/// **Architecture:** Duck.ai → SubscriptionUserScript → This Coordinator → WindowControllersManager → Tabs/Preferences
///
/// Used as the navigation delegate for `SubscriptionUserScript` in macOS.
/// iOS uses `SubscriptionURLNavigationHandler` with notifications instead.
@MainActor
final class SubscriptionNavigationCoordinator {

    private let tabShower: SubscriptionTabsShowing
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge

    init(tabShower: SubscriptionTabsShowing,
         subscriptionManager: any SubscriptionAuthV1toV2Bridge) {
        self.tabShower = tabShower
        self.subscriptionManager = subscriptionManager
    }
}

// MARK: - SubscriptionUserScriptNavigationDelegate

extension SubscriptionNavigationCoordinator: SubscriptionUserScriptNavigationDelegate {

    /// Opens the subscription settings pane in Preferences.
    /// Called when Duck.ai need to navigate to subscription management.
    func navigateToSettings() {
        tabShower.showPreferencesTab(withSelectedPane: .subscriptionSettings)
    }

    /// Opens the subscription activation flow in a new tab.
    /// Called when Duck.ai need to restore an existing subscription.
    func navigateToSubscriptionActivation() {
        let url = subscriptionManager.url(for: .activationFlow)
        tabShower.showTab(with: .subscription(url))
    }

    /// Opens the subscription purchase flow in a new tab.
    /// Called when Duck.ai need to start a new subscription purchase.
    func navigateToSubscriptionPurchase(origin: String?, featurePage: String?) {
        var url = subscriptionManager.url(for: .purchase)
        if let featurePage {
            url = url.appendingParameter(name: "featurePage", value: featurePage)
        }
        if let origin {
            url = url.appendingParameter(name: AttributionParameter.origin, value: origin)
        }

        tabShower.showTab(with: .subscription(url))
    }
}
