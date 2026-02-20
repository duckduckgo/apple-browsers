//
//  VPNURLEventHandler.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import PixelKit
import VPNAppLauncher

#if !APPSTORE
import LetsMove
#endif

@MainActor
final class VPNURLEventHandler {

    private let windowControllersManager: WindowControllersManager

    init(windowControllersManager: WindowControllersManager? = nil) {
        self.windowControllersManager = windowControllersManager ?? Application.appDelegate.windowControllersManager
    }

    /// Handles VPN event URLs
    ///
    func handle(_ url: URL) async {
        switch url {
        case VPNAppLaunchCommand.manageExcludedApps.launchURL:
            windowControllersManager.showVPNAppExclusions()
        case VPNAppLaunchCommand.manageExcludedDomains.launchURL:
            windowControllersManager.showVPNDomainExclusions()
        case VPNAppLaunchCommand.showStatus.launchURL:
            await showStatus()
        case VPNAppLaunchCommand.showSettings.launchURL:
            showPreferences()
        case VPNAppLaunchCommand.shareFeedback.launchURL:
            showShareFeedback()
        case VPNAppLaunchCommand.justOpen.launchURL:
            showMainWindow()
        case VPNAppLaunchCommand.showVPNLocations.launchURL:
            showLocations()
        case VPNAppLaunchCommand.showSubscription.launchURL:
            showSubscription()
#if !APPSTORE && !DEBUG
        case VPNAppLaunchCommand.moveAppToApplications.launchURL:
            moveAppToApplicationsFolder()
#endif
        default:
            return
        }
    }

    func reloadTab(showingDomain domain: String) {
        windowControllersManager.selectedTab?.reload()
    }

    func showStatus() async {
        await windowControllersManager.showNetworkProtectionStatus()
    }

    func showPreferences() {
        windowControllersManager.showPreferencesTab(withSelectedPane: .vpn)
    }

    func showShareFeedback() {
        windowControllersManager.showShareFeedbackModal(source: .vpn)
    }

    func showMainWindow() {
        windowControllersManager.showMainWindow()
    }

    func showLocations() {
        windowControllersManager.showPreferencesTab(withSelectedPane: .vpn)
        windowControllersManager.showLocationPickerSheet()
    }

    func showSubscription() {
        let url = Application.appDelegate.subscriptionManager.url(for: .purchase)
        windowControllersManager.showTab(with: .subscription(url))

        PixelKit.fire(SubscriptionPixel.subscriptionOfferScreenImpression)
    }

    func showVPNAppExclusions() {
        windowControllersManager.showPreferencesTab(withSelectedPane: .vpn)
        windowControllersManager.showVPNAppExclusions()
    }

    func showVPNDomainExclusions() {
        windowControllersManager.showPreferencesTab(withSelectedPane: .vpn)
        windowControllersManager.showVPNDomainExclusions()
    }

#if !APPSTORE && !DEBUG
    func moveAppToApplicationsFolder() {
        // this should be run after NSApplication.shared is set
        PFMoveToApplicationsFolderIfNecessary(false)
    }
#endif
}
