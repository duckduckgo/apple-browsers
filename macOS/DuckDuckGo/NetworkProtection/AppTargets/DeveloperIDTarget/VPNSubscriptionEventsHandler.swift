//
//  VPNSubscriptionEventsHandler.swift
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

final class VPNSubscriptionEventsHandler {
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
    }

    public func startMonitoring() {
        checkEntitlements()
        subscribeToWakeNotifications()
        subscribeToEntitlementChanges()
        registerForSubscriptionAccountManagerEvents()
    }

    /// This is a shared user default that the VPN menu app listens to to know whether it's enabled or disabled
    @MainActor
    private var lastKnownEntitlementsExpired: Bool {
        get {
            userDefaults.networkProtectionEntitlementsExpired
        }
        set {
            userDefaults.networkProtectionEntitlementsExpired = newValue
        }
    }

    private func checkEntitlements() {
        performClientCheck(trigger: .appStartup)
    }

    private func subscribeToWakeNotifications() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Logger.networkProtection.log("System wake notification received, checking entitlements")
                self?.performClientCheck(trigger: .deviceWake)
            }
            .store(in: &cancellables)
    }

    private func subscribeToEntitlementChanges() {
        NotificationCenter.default
            .publisher(for: .entitlementsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }

                Task {
                    Logger.networkProtection.log("Entitlements did change notification received")
                    guard let userInfo = notification.userInfo,
                          let payload = EntitlementsDidChangePayload(notificationUserInfo: userInfo) else {
                        assertionFailure("Missing entitlements payload")
                        Logger.subscription.fault("Missing entitlements payload")
                        return
                    }

                    let hasEntitlements = payload.entitlements.contains(.networkProtection)
                    await self.handleEntitlementsChangeNotification(hasEntitlements: hasEntitlements, sourceObject: notification.object)
                }
            }
            .store(in: &cancellables)
    }

    private func performClientCheck(trigger: VPNSubscriptionClientCheckPixel.Trigger) {
        Task {
            do {
                let hasEntitlement = try await subscriptionManager.isFeatureEnabled(.networkProtection)
                await handleEntitlementsChangeClientCheck(hasEntitlements: hasEntitlement, trigger: trigger)
            } catch {
                await handleClientCheckFailure(error: error, trigger: trigger)
            }
        }
    }

    @MainActor
    private func handleClientCheckFailure(error: Error, trigger: VPNSubscriptionClientCheckPixel.Trigger) async {
        let isAuthV2Enabled = NSApp.delegateTyped.isUsingAuthV2
        let isSubscriptionActive = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst).isActive

        PixelKit.fire(
            VPNSubscriptionClientCheckPixel.failed(
                isSubscriptionActive: isSubscriptionActive,
                isAuthV2Enabled: isAuthV2Enabled,
                trigger: trigger,
                error: error),
            frequency: .daily)
    }

    @MainActor
    private func handleEntitlementsChangeClientCheck(hasEntitlements: Bool, trigger: VPNSubscriptionClientCheckPixel.Trigger) async {
        let isAuthV2Enabled = NSApp.delegateTyped.isUsingAuthV2
        let isSubscriptionActive = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst).isActive

        // For client checks we only fire pixels if there's an actual change, because they're not guaranteed
        // to be executed only when there are changes - they'll run at every app launch.
        if hasEntitlements && lastKnownEntitlementsExpired {
            PixelKit.fire(
                VPNSubscriptionClientCheckPixel.vpnFeatureEnabled(
                    isSubscriptionActive: isSubscriptionActive,
                    isAuthV2Enabled: isAuthV2Enabled,
                    trigger: trigger),
                frequency: .dailyAndCount)

            /// This is a shared user default that the VPN menu app listens to to know whether it's enabled or disabled
            lastKnownEntitlementsExpired = false
        } else if !hasEntitlements && !lastKnownEntitlementsExpired {
            PixelKit.fire(
                VPNSubscriptionClientCheckPixel.vpnFeatureDisabled(
                    isSubscriptionActive: isSubscriptionActive,
                    isAuthV2Enabled: isAuthV2Enabled,
                    trigger: trigger),
                frequency: .dailyAndCount)

            /// This is a shared user default that the VPN menu app listens to to know whether it's enabled or disabled
            lastKnownEntitlementsExpired = true
        }
    }

    @MainActor
    private func handleEntitlementsChangeNotification(hasEntitlements: Bool, sourceObject: Any?) async {
        let isAuthV2Enabled = NSApp.delegateTyped.isUsingAuthV2
        let isSubscriptionActive = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst).isActive

        // For notifications we assume they are fired on actual changes, so we want to fire
        // pixels without additional checks.
        if hasEntitlements {
            PixelKit.fire(
                VPNSubscriptionStatusPixel.vpnFeatureEnabled(
                    isSubscriptionActive: isSubscriptionActive,
                    isAuthV2Enabled: isAuthV2Enabled,
                    sourceObject: sourceObject),
                frequency: .dailyAndCount)

            if lastKnownEntitlementsExpired {
                /// This is a shared user default that the VPN menu app listens to to know whether it's enabled or disabled
                lastKnownEntitlementsExpired = false
            }
        } else {
            PixelKit.fire(
                VPNSubscriptionStatusPixel.vpnFeatureDisabled(
                    isSubscriptionActive: isSubscriptionActive,
                    isAuthV2Enabled: isAuthV2Enabled,
                    sourceObject: sourceObject),
                frequency: .dailyAndCount)

            if !lastKnownEntitlementsExpired {
                /// This is a shared user default that the VPN menu app listens to to know whether it's enabled or disabled
                lastKnownEntitlementsExpired = true
            }
        }
    }

    private func registerForSubscriptionAccountManagerEvents() {
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
        Task { @MainActor in
            guard subscriptionManager.isUserAuthenticated else {
                assertionFailure("[NetP Subscription] AccountManager signed in but token could not be retrieved")
                return
            }

            let isAuthV2Enabled = NSApp.delegateTyped.isUsingAuthV2
            let isSubscriptionActive = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst).isActive

            PixelKit.fire(
                VPNSubscriptionStatusPixel.signedIn(
                    isSubscriptionActive: isSubscriptionActive,
                    isAuthV2Enabled: isAuthV2Enabled,
                    sourceObject: notification.object),
                frequency: .dailyAndCount)

            /// This is a shared user default that the VPN menu app listens to to know whether it's enabled or disabled
            lastKnownEntitlementsExpired = false
        }
    }

    private func handleAccountDidSignOut(_ notification: Notification) {
        Task {
            print("[NetP Subscription] Deleted NetP auth token after signing out from Privacy Pro")

            let isAuthV2Enabled = await NSApp.delegateTyped.isUsingAuthV2
            let isSubscriptionActive = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst).isActive

            PixelKit.fire(
                VPNSubscriptionStatusPixel.signedOut(
                    isSubscriptionActive: isSubscriptionActive,
                    isAuthV2Enabled: isAuthV2Enabled,
                    sourceObject: notification.object),
                frequency: .dailyAndCount)

            try? await vpnUninstaller.uninstall(removeSystemExtension: false, showNotification: true)
        }
    }

}
