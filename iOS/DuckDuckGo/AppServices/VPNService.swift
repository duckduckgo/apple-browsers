//
//  VPNService.swift
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

import VPN
import Subscription
import UIKit
import NotificationCenter
import Core

final class VPNService: NSObject {

    private let tunnelController = AppDependencyProvider.shared.networkProtectionTunnelController
    private let widgetRefreshModel = NetworkProtectionWidgetRefreshModel()
    private let tunnelDefaults = UserDefaults.networkProtectionGroupDefaults
    private let vpnFeatureVisibility: DefaultNetworkProtectionVisibility = AppDependencyProvider.shared.vpnFeatureVisibility
    private let tipKitAppEventsHandler = TipKitAppEventHandler()
    private let notificationServiceManager: NotificationServiceManaging

    private let mainCoordinator: MainCoordinator
    private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
    private let application: UIApplication
    init(mainCoordinator: MainCoordinator,
         subscriptionManager: any SubscriptionAuthV1toV2Bridge = AppDependencyProvider.shared.subscriptionAuthV1toV2Bridge,
         application: UIApplication = UIApplication.shared,
         notificationCenter: UNUserNotificationCenterRepresentable = UNUserNotificationCenter.current(),
         notificationServiceManager: NotificationServiceManaging,
    ) {
        self.mainCoordinator = mainCoordinator
        self.subscriptionManager = subscriptionManager
        self.application = application
        self.notificationServiceManager = notificationServiceManager
        
        notificationCenter.delegate = notificationServiceManager
        
        super.init()

        widgetRefreshModel.beginObservingVPNStatus()
        tipKitAppEventsHandler.appDidFinishLaunching()
    }

    // MARK: - Resume

    @MainActor
    func resume() {
        widgetRefreshModel.refreshVPNWidget()
        presentExpiredEntitlementAlertIfNeeded()
        presentExpiredEntitlementNotificationIfNeeded()

        Task {
            await stopAndRemoveVPNIfNotAuthenticated()
            await refreshVPNShortcuts()

            if #available(iOS 17.0, *) {
                await VPNSnoozeLiveActivityManager().endSnoozeActivityIfNecessary()
            }
        }
    }

    private func presentExpiredEntitlementNotificationIfNeeded() {
        let presenter = VPNNotificationsPresenterTogglableDecorator(
            settings: AppDependencyProvider.shared.vpnSettings,
            defaults: .networkProtectionGroupDefaults,
            wrappee: NetworkProtectionUNNotificationPresenter()
        )
        presenter.showEntitlementNotification()
    }

    @MainActor
    private func presentExpiredEntitlementAlertIfNeeded() {
        if tunnelDefaults.showEntitlementAlert {
            presentExpiredEntitlementAlert()
        }
    }

    @MainActor
    private func presentExpiredEntitlementAlert() {
        let alertController = CriticalAlerts.makeExpiredEntitlementAlert {
            self.mainCoordinator.segueToPrivacyPro()
        }
        application.window?.rootViewController?.present(alertController, animated: true) {
            self.tunnelDefaults.showEntitlementAlert = false
        }
    }

    private func stopAndRemoveVPNIfNotAuthenticated() async {
        // Only remove the VPN if the user is not authenticated, and it's installed:
        guard !subscriptionManager.isUserAuthenticated, await tunnelController.isInstalled else {
            return
        }

        await tunnelController.stop()
        await tunnelController.removeVPN(reason: .didBecomeActiveCheck)
    }

    // MARK: - Suspend

    func suspend() {
        Task { @MainActor in
            await refreshVPNShortcuts()
        }
    }

    @MainActor
    private func refreshVPNShortcuts() async {
        guard await vpnFeatureVisibility.shouldShowVPNShortcut(),
              let canShowVPNInUI = try? await subscriptionManager.isFeatureIncludedInSubscription(.networkProtection),
              canShowVPNInUI
        else {
            application.shortcutItems = nil
            return
        }

        application.shortcutItems = [
            UIApplicationShortcutItem(type: ShortcutKey.openVPNSettings,
                                      localizedTitle: UserText.netPOpenVPNQuickAction,
                                      localizedSubtitle: nil,
                                      icon: UIApplicationShortcutIcon(templateImageName: "VPN-16"),
                                      userInfo: nil)
        ]
    }

}
