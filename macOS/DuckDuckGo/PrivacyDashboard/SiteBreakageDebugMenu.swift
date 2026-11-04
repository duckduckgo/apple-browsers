//
//  SiteBreakageDebugMenu.swift
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

import AppKit
import PrivacyDashboard

@MainActor
final class SiteBreakageDebugMenu: NSMenuItem {

    private let networkSignalsProvider: NetworkSignalsProviding

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(networkSignalsProvider: NetworkSignalsProviding) {
        self.networkSignalsProvider = networkSignalsProvider
        super.init(title: "Site Breakage", action: nil, keyEquivalent: "")
        self.submenu = makeSubmenu()
    }

    private func makeSubmenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.addItem(NSMenuItem(title: "Show Network Signals", action: #selector(showNetworkSignals), target: self))
        menu.addItem(NSMenuItem(title: "Show Page Signals", action: #selector(MainViewController.debugShowPageSignals)))
        menu.addItem(NSMenuItem(title: "Verify DNS Blocking", action: #selector(MainViewController.debugVerifyDNSBlocking)))
        return menu
    }

    @objc private func showNetworkSignals() {
        Task { @MainActor in
            let start = Date()

            // Awaits a fresh ping, since `currentSignals()` only reads the prefetched one.
            await networkSignalsProvider.prefetchSignals()?.value
            let signals = await networkSignalsProvider.currentSignals()

            let elapsedMilliseconds = Int(Date().timeIntervalSince(start) * 1000)
            let details = signals.map(Self.description(for:)) ?? "Disabled: the `pageSignals` feature flag is off."

            showAlert(message: details + "\n• Generated in: \(elapsedMilliseconds) ms")
        }
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Network Signals"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func description(for signals: NetworkSignals) -> String {
        """
        • Network Available: \(signals.isNetworkAvailable)
        • Network Type: \(signals.networkType.rawValue)
        • Low Data Mode: \(signals.isLowDataModeEnabled)
        • VPN Connectivity Issues: \(signals.hasVPNConnectivityIssues)
        • Ping Quality: \(signals.pingQuality.rawValue)
        """
    }
}
