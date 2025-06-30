//
//  SubscriptionURLNavigationHandler.swift
//  DuckDuckGo
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
import Core
import BrowserServicesKit
import Subscription

/// iOS-specific navigation handler for subscription web pages.
///
/// Enables Duck.ai (SERP) to navigate to specific sections within the app using SubscriptionUserScript
/// by posting `settingsDeepLinkNotification` that `MainViewController` handles.
///
/// **Architecture:** Duck.ai → SubscriptionUserScript → This Handler → NotificationCenter → MainViewController → Settings
///
/// Used in `UserScripts.swift` as the navigation delegate for `SubscriptionUserScript`.
/// macOS uses `SubscriptionNavigationCoordinator` instead of notifications.
@MainActor
final class SubscriptionURLNavigationHandler: SubscriptionUserScriptNavigationDelegate {

    /// Navigates to the subscription settings section.
    /// Called when Duck.ai need to navigate to subscription management.
    func navigateToSettings() {
        NotificationCenter.default.post(
            name: .settingsDeepLinkNotification,
            object: SettingsViewModel.SettingsDeepLinkSection.subscriptionSettings
        )
    }

    /// Navigates to the subscription restore/activation flow.
    /// Called when Duck.ai need to restore an existing subscription.
    func navigateToSubscriptionActivation() {
        NotificationCenter.default.post(
            name: .settingsDeepLinkNotification,
            object: SettingsViewModel.SettingsDeepLinkSection.restoreFlow
        )
    }

    /// Navigates to the subscription purchase flow.
    /// Called when Duck.ai need to start a new subscription purchase.
    func navigateToSubscriptionPurchase() {
        NotificationCenter.default.post(
            name: .settingsDeepLinkNotification,
            object: SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow()
        )
    }
}
