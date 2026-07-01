//
//  ChromeExtensionDebugMenu.swift
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
import FeatureFlags
import PrivacyConfig

final class ChromeExtensionDebugMenu: NSMenu {

    private let featureFlagger: FeatureFlagger
    private let installer: ThirdPartyBrowserExtensionInstalling
    private let featureFlagHintMenuItem = NSMenuItem(title: "Enable onboardingChromeExtension feature flag")
    private let eligibilityMenuItem = NSMenuItem(title: "")
    private let installSearchExtensionMenuItem = NSMenuItem(title: "Install search extension", action: #selector(installSearchExtension))

    init(featureFlagger: FeatureFlagger, installer: ThirdPartyBrowserExtensionInstalling) {
        self.featureFlagger = featureFlagger
        self.installer = installer
        super.init(title: "")

        autoenablesItems = false
        installSearchExtensionMenuItem.target = self
        featureFlagHintMenuItem.isEnabled = false

        buildItems {
            featureFlagHintMenuItem
            eligibilityMenuItem
            installSearchExtensionMenuItem
        }

        updateMenuItemsState()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update() {
        updateMenuItemsState()
    }

    @objc private func installSearchExtension() {
        let installationSucceeded = installer.installDDGExtension()
        let alert = NSAlert()
        alert.messageText = installationSucceeded ? "Search extension installed" : "Search extension installation failed"
        alert.alertStyle = installationSucceeded ? .informational : .warning
        alert.runModal()

        updateMenuItemsState()
    }

    private func updateMenuItemsState() {
        let isFeatureEnabled = featureFlagger.isFeatureOn(.onboardingChromeExtension)
        featureFlagHintMenuItem.isHidden = isFeatureEnabled
        eligibilityMenuItem.isHidden = !isFeatureEnabled
        installSearchExtensionMenuItem.isHidden = !isFeatureEnabled

        if isFeatureEnabled {
            let canInstallExtension = installer.canInstallDDGExtension
            eligibilityMenuItem.title = canInstallExtension ? "Chrome extension: eligible" : "Chrome extension: not eligible"
            eligibilityMenuItem.isEnabled = false
            installSearchExtensionMenuItem.isEnabled = canInstallExtension
        }
    }
}
