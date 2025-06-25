//
//  NetworkProtectionSubscriptionEventHandler.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import AppKit
import Combine
import Common
import Foundation
import Subscription
import VPN
import NetworkProtectionUI
import PixelKit
import os.log

final class NetworkProtectionSubscriptionEventHandler {
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let tunnelController: TunnelController
    private let vpnUninstaller: VPNUninstalling
    private let userDefaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()

    init(subscriptionManager: any SubscriptionAuthV1toV2Bridge,
         tunnelController: TunnelController,
         vpnUninstaller: VPNUninstalling,
         userDefaults: UserDefaults = .netP) {
        self.subscriptionManager = subscriptionManager
        self.tunnelController = tunnelController
        self.vpnUninstaller = vpnUninstaller
        self.userDefaults = userDefaults

        subscribeToEntitlementChanges()
    }

    private func subscribeToEntitlementChanges() {
        Task {
            let hasEntitlement = await subscriptionManager.isFeatureEnabledForUser(feature: .networkProtection)
            Task {
                await handleEntitlementsChange(hasEntitlements: hasEntitlement, sourceObject: subscriptionManager)
            }

            NotificationCenter.default
                .publisher(for: .entitlementsDidChange)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] notification in
                    Logger.networkProtection.log("Entitlements did change notification received")
                    guard let self else {
                        return
                    }

                    guard let entitlements = notification.userInfo?[UserDefaultsCacheKey.subscriptionEntitlements] as? [Entitlement] else {
                        assertionFailure("Missing entitlements are truly unexpected")
                        return
                    }

                    let hasEntitlements = entitlements.contains { entitlement in
                        entitlement.product == .networkProtection
                    }

                    Task {
                        await self.handleEntitlementsChange(hasEntitlements: hasEntitlements, sourceObject: notification.object)
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func handleEntitlementsChange(hasEntitlements: Bool, sourceObject: Any?) async {
        let subscriptionManager = await NSApp.delegateTyped.subscriptionAuthV1toV2Bridge
        let isAuthV2Enabled = await NSApp.delegateTyped.isAuthV2Enabled
        let isSubscriptionActive = try? await subscriptionManager.getSubscription(cachePolicy: .cacheOnly).isActive

        if hasEntitlements {
            PixelKit.fire(
                VPNSubscriptionNotificationPixel.vpnEnabled(
                    isSubscriptionActive: isSubscriptionActive,
                    isAuthV2Enabled: isAuthV2Enabled,
                    sourceObject: sourceObject),
                frequency: .dailyAndCount)
            UserDefaults.netP.networkProtectionEntitlementsExpired = false
        } else {
            PixelKit.fire(
                VPNSubscriptionNotificationPixel.vpnDisabled(
                    isSubscriptionActive: isSubscriptionActive,
                    isAuthV2Enabled: isAuthV2Enabled,
                    sourceObject: sourceObject),
                frequency: .dailyAndCount)
            await tunnelController.stop()
            UserDefaults.netP.networkProtectionEntitlementsExpired = true
        }
    }

    func registerForSubscriptionAccountManagerEvents() {
        NotificationCenter.default
            .publisher(for: .accountDidSignIn)
            .sink { [weak self] notification in
                self?.handleAccountDidSignIn(notification)
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: .accountDidSignOut)
            .sink { [weak self] notification in
                self?.handleAccountDidSignOut(notification)
            }
            .store(in: &cancellables)
    }

    private func handleAccountDidSignIn(_ notification: Notification) {
        Task {
            guard subscriptionManager.isUserAuthenticated else {
                assertionFailure("[NetP Subscription] AccountManager signed in but token could not be retrieved")
                return
            }

            let subscriptionManager = await NSApp.delegateTyped.subscriptionAuthV1toV2Bridge
            let isAuthV2Enabled = await NSApp.delegateTyped.isAuthV2Enabled
            let isSubscriptionActive = try? await subscriptionManager.getSubscription(cachePolicy: .cacheOnly).isActive

            PixelKit.fire(
                VPNSubscriptionNotificationPixel.signedIn(
                    isSubscriptionActive: isSubscriptionActive,
                    isAuthV2Enabled: isAuthV2Enabled,
                    sourceObject: notification.object),
                frequency: .dailyAndCount)
            userDefaults.networkProtectionEntitlementsExpired = false
        }
    }

    private func handleAccountDidSignOut(_ notification: Notification) {
        Task {
            print("[NetP Subscription] Deleted NetP auth token after signing out from Privacy Pro")

            let subscriptionManager = await NSApp.delegateTyped.subscriptionAuthV1toV2Bridge
            let isAuthV2Enabled = await NSApp.delegateTyped.isAuthV2Enabled
            let isSubscriptionActive = try? await subscriptionManager.getSubscription(cachePolicy: .cacheOnly).isActive

            PixelKit.fire(
                VPNSubscriptionNotificationPixel.signedOut(
                    isSubscriptionActive: isSubscriptionActive,
                    isAuthV2Enabled: isAuthV2Enabled,
                    sourceObject: notification.object),
                frequency: .dailyAndCount)

            try? await vpnUninstaller.uninstall(removeSystemExtension: false, showNotification: true)
        }
    }

}
