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
import LetsMove
import PixelKit
import Subscription
import VPNAppLauncher

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
            // The only producer of this launch URL today is the agent's menu-bar
            // expired view's Subscribe button (see VPNUIActionHandler in DuckDuckGoVPN).
            // The agent has no way to send `origin` across this IPC boundary, so we
            // hard-code the funnel origin here at the receiver. If a new agent
            // surface starts emitting this command, this assumption breaks — switch
            // to a per-surface VPNAppLaunchCommand case at that point.
            showSubscription(origin: SubscriptionFunnelOrigin.vpnMenuBarRevoked.rawValue)
        case VPNAppLaunchCommand.moveAppToApplications.launchURL:
            moveAppToApplicationsFolder()
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

    func showSubscription(origin: String? = nil) {
        let fallback = Application.appDelegate.subscriptionManager.url(for: .purchase)
        let url = origin
            .flatMap { SubscriptionURL.purchaseURLComponentsWithOrigin($0)?.url }
            ?? fallback

        windowControllersManager.showTab(with: .subscription(url))
        PixelKit.fire(SubscriptionPixel.subscriptionOfferScreenImpression(origin: origin))
    }

    func showVPNAppExclusions() {
        windowControllersManager.showPreferencesTab(withSelectedPane: .vpn)
        windowControllersManager.showVPNAppExclusions()
    }

    func showVPNDomainExclusions() {
        windowControllersManager.showPreferencesTab(withSelectedPane: .vpn)
        windowControllersManager.showVPNDomainExclusions()
    }

    func moveAppToApplicationsFolder() {
        let buildType = StandardApplicationBuildType()
        guard !buildType.isAppStoreBuild && !buildType.isDebugBuild else { return }

        // this should be run after NSApplication.shared is set
        PFMoveToApplicationsFolderIfNecessary(/*allowAlertSilencing:*/ false)
    }
}
