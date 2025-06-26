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

protocol SubscriptionTabsShowing {
    func showTab(with content: Tab.TabContent)
    func showPreferencesTab(withSelectedPane pane: PreferencePaneIdentifier?)
}

extension WindowControllersManager: SubscriptionTabsShowing {}

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

    func navigateToSettings() {
        tabShower.showPreferencesTab(withSelectedPane: .subscriptionSettings)
    }

    func navigateToSubscriptionActivation() {
        let url = subscriptionManager.url(for: .activationFlow)
        tabShower.showTab(with: .subscription(url))
    }

    func navigateToSubscriptionPurchase() {
        let url = subscriptionManager.url(for: .purchase)
        tabShower.showTab(with: .subscription(url))
    }
}
