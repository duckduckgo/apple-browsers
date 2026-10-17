//
//  OSSupportDebugMenu.swift
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
import AppKitExtensions

final class OSSupportDebugMenu: NSMenu {

    private let osUpgradeCapabilityOverridePersistor = OSUpgradeCapabilityOverridePersistor()
    private let osUpgradeCapabilityOverrideMenu = NSMenu(title: "")

    init() {
        super.init(title: "")

        buildItems {
            NSMenuItem(title: "OS Upgrade Capability Override")
                .submenu(osUpgradeCapabilityOverrideMenu)
                .withAccessibilityIdentifier("OSSupportDebugMenu.osUpgradeCapabilityOverride")
            NSMenuItem.separator()
            NSMenuItem(title: "Reset Big Sur End-of-Support “Don’t Show Again”",
                       action: #selector(resetBigSurEndOfSupportDismissed),
                       target: self)
                .withAccessibilityIdentifier("OSSupportDebugMenu.resetBigSurEndOfSupportDismissed")
        }

        for override in OSUpgradeCapabilityOverride.allCases {
            let item = NSMenuItem(title: override.title, action: #selector(setOSUpgradeCapabilityOverride(_:)), target: self)
            item.representedObject = override
            item.withAccessibilityIdentifier("OSSupportDebugMenu.osUpgradeCapabilityOverride.\(override.rawValue)")
            osUpgradeCapabilityOverrideMenu.addItem(item)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update() {
        updateOSUpgradeCapabilityOverrideMenu()
    }

    private func updateOSUpgradeCapabilityOverrideMenu() {
        let current = osUpgradeCapabilityOverridePersistor.current
        for item in osUpgradeCapabilityOverrideMenu.items {
            guard let override = item.representedObject as? OSUpgradeCapabilityOverride else { continue }
            item.state = override == current ? .on : .off
        }
    }

    @objc func setOSUpgradeCapabilityOverride(_ sender: NSMenuItem) {
        guard let override = sender.representedObject as? OSUpgradeCapabilityOverride else { return }
        osUpgradeCapabilityOverridePersistor.current = override
        updateOSUpgradeCapabilityOverrideMenu()
        NSApp.delegateTyped.remoteMessagingClient.refreshRemoteMessages()
    }

    @objc func resetBigSurEndOfSupportDismissed() {
        var persistor = BigSurEndOfSupportNoticePersistor(keyValueStore: NSApp.delegateTyped.keyValueStore)
        persistor.dismissed = false
    }
}
