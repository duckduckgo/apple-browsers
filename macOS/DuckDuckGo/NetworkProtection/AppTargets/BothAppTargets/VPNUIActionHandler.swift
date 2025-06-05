//
//  VPNUIActionHandler.swift
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

import AppLauncher
import Foundation
import NetworkProtection
import NetworkProtectionIPC
import NetworkProtectionProxy
import NetworkProtectionUI
import SwiftUI
import VPNAppLauncher
import VPNAppState

/// Main App's VPN UI action handler
///
final class VPNUIActionHandler {

    private let vpnIPCClient: VPNControllerXPCClient
    private let proxySettings: TransparentProxySettings
    private let tunnelController: TunnelController
    private let vpnAppState: VPNAppState
    private let vpnURLEventHandler: VPNURLEventHandler

    init(vpnIPCClient: VPNControllerXPCClient = .shared,
         vpnURLEventHandler: VPNURLEventHandler,
         tunnelController: TunnelController,
         proxySettings: TransparentProxySettings,
         vpnAppState: VPNAppState) {

        self.vpnIPCClient = vpnIPCClient
        self.vpnURLEventHandler = vpnURLEventHandler
        self.tunnelController = tunnelController
        self.proxySettings = proxySettings
        self.vpnAppState = vpnAppState
    }

    func askUserToReportIssues(withDomain domain: String) async {
        let parentWindow = await windowControllerManager.lastKeyMainWindowController?.window
        await ReportSiteIssuesPresenter(userDefaults: .netP).show(withDomain: domain, in: parentWindow)
    }

    @MainActor
    private var windowControllerManager: WindowControllersManager {
        Application.appDelegate.windowControllersManager
    }
}

extension VPNUIActionHandler: VPNUIActionHandling {

    func moveAppToApplications() async {
#if !APPSTORE && !DEBUG
        await vpnURLEventHandler.moveAppToApplicationsFolder()
#endif
    }

    func setExclusion(_ exclude: Bool, forDomain domain: String) async {
        proxySettings.setExclusion(exclude, forDomain: domain)
        try? await vpnIPCClient.command(.restartAdapter)

        if exclude {
            await askUserToReportIssues(withDomain: domain)
        }

        await vpnURLEventHandler.reloadTab(showingDomain: domain)
    }

    func shareFeedback() async {
        await vpnURLEventHandler.showShareFeedback()
    }

    func showVPNLocations() async {
        await vpnURLEventHandler.showLocations()
    }

    func showPrivacyPro() async {
        await vpnURLEventHandler.showPrivacyPro()
    }

    @MainActor
    func willStopVPN() async -> Bool {
        guard vpnAppState.isUsingSystemExtension && !vpnAppState.dontAskAgainExclusionSuggestion,
              let parentWindow = windowControllerManager.lastKeyMainWindowController?.window else {
            return true
        }

        var userAction: VPNExclusionSuggestionAlert.UserAction = .stopVPN
        let binding = Binding<VPNExclusionSuggestionAlert.UserAction> {
            userAction
        } set: { newValue in
            userAction = newValue
        }

        var dontAskAgain = false
        let dontAskAgainBinding = Binding<Bool> {
            dontAskAgain
        } set: { newValue in
            dontAskAgain = newValue
        }

        let modalAlert = VPNExclusionSuggestionAlert(userAction: binding, dontAskAgain: dontAskAgainBinding)
        await modalAlert.show(in: parentWindow)

        if dontAskAgain {
            vpnAppState.dontAskAgainExclusionSuggestion = true
        }

        switch userAction {
        case .stopVPN:
            return true
        case .excludeApp:
            Application.appDelegate.windowControllersManager.showVPNAppExclusions(addApp: true)
            return false
        case .excludeWebsite:
            let domain = windowControllerManager.activeDomain ?? ""
            windowControllerManager.showVPNDomainExclusions(domain: domain)
            return false
        }
    }
}
