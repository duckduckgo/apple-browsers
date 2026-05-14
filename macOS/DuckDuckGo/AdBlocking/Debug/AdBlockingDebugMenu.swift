//
//  AdBlockingDebugMenu.swift
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
import Persistence
import WebExtensions

@MainActor
final class AdBlockingDebugMenu: NSMenuItem, NSMenuDelegate {

    private var settings: any KeyedStoring<YouTubeAdBlockingSettings> {
        UserDefaults.standard.keyedStoring()
    }

    private let scriptletsItem = NSMenuItem(title: "Scriptlets", action: nil, keyEquivalent: "")
    private let flagsItem = NSMenuItem(title: "Flags", action: nil, keyEquivalent: "")
    private let analyticsItem = NSMenuItem(title: "youTubeAnalyticsEnabled", action: nil, keyEquivalent: "")
    private let disclosureItem = NSMenuItem(title: "shouldHideDisclosure", action: nil, keyEquivalent: "")

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public init() {
        super.init(title: "Ad Blocking", action: nil, keyEquivalent: "")
        self.submenu = makeSubmenu()
    }

    private func makeSubmenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.delegate = self

        menu.addItem(NSMenuItem(title: "Trigger `YouTube Ad Block On` address bar animation",
                                action: #selector(showYouTubeAdBlockOnAnimation),
                                target: self))

        menu.addItem(.separator())

        scriptletsItem.submenu = NSMenu(title: "Scriptlets")
        menu.addItem(scriptletsItem)

        let flagsSubmenu = NSMenu(title: "Flags")

        let analyticsSubmenu = NSMenu(title: "youTubeAnalyticsEnabled")
        analyticsSubmenu.addItem(NSMenuItem(title: "Reset (delete key)",
                                            action: #selector(resetYouTubeAnalyticsEnabled),
                                            target: self))
        analyticsItem.submenu = analyticsSubmenu
        flagsSubmenu.addItem(analyticsItem)

        let disclosureSubmenu = NSMenu(title: "shouldHideDisclosure")
        disclosureSubmenu.addItem(NSMenuItem(title: "Set to `true`",
                                             action: #selector(setShouldHideDisclosureTrue),
                                             target: self))
        disclosureSubmenu.addItem(NSMenuItem(title: "Set to `false`",
                                             action: #selector(setShouldHideDisclosureFalse),
                                             target: self))
        disclosureSubmenu.addItem(NSMenuItem(title: "Reset (delete key)",
                                             action: #selector(resetShouldHideDisclosure),
                                             target: self))
        disclosureItem.submenu = disclosureSubmenu
        flagsSubmenu.addItem(disclosureItem)

        flagsItem.submenu = flagsSubmenu
        menu.addItem(flagsItem)

        return menu
    }

    // MARK: - NSMenuDelegate

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeMainThread {
            updateScriptletsSubmenu()
            updatePreferenceTitles()
        }
    }

    // MARK: - Actions

    @objc func showYouTubeAdBlockOnAnimation() {
        guard let mainVC = Application.appDelegate.windowControllersManager
            .lastKeyMainWindowController?.mainViewController else { return }
        mainVC.navigationBarViewController
            .addressBarViewController?
            .addressBarButtonsViewController?
            .showBadgeNotification(.youTubeAdBlockOn)
    }

    @objc private func setShouldHideDisclosureTrue() {
        var settings = self.settings
        settings.shouldHideYouTubeAdBlockingDisclosure = true
    }

    @objc private func setShouldHideDisclosureFalse() {
        var settings = self.settings
        settings.shouldHideYouTubeAdBlockingDisclosure = false
    }

    @objc private func resetShouldHideDisclosure() {
        var settings = self.settings
        settings.removeValue(for: \.shouldHideYouTubeAdBlockingDisclosure)
    }

    @objc private func resetYouTubeAnalyticsEnabled() {
        var settings = self.settings
        settings.removeValue(for: \.youTubeAnalyticsEnabled)
    }

    // MARK: - Scriptlets submenu

    private func updateScriptletsSubmenu() {
        guard let submenu = scriptletsItem.submenu else { return }
        submenu.removeAllItems()
        guard #available(macOS 15.4, *) else {
            submenu.addItem(disabledItem("Scriptlets: macOS 15.4 required"))
            return
        }
        for item in scriptletDebugInfoItems() {
            submenu.addItem(item)
        }
    }

    @available(macOS 15.4, *)
    private func scriptletDebugInfoItems() -> [NSMenuItem] {
        guard let manager = Application.appDelegate.webExtensionManager else {
            return [disabledItem("Scriptlets: Web Extensions not initialized")]
        }

        let debugInfos = manager.scriptletDebugInfo()

        guard !debugInfos.isEmpty else {
            return [disabledItem("Scriptlets: No data available")]
        }

        return debugInfos.flatMap { info -> [NSMenuItem] in
            let header = disabledItem("[\(info.extensionType.rawValue)] Scriptlets")
            let cached = disabledItem("  Cached version: \(info.cachedVersion ?? "none")")
            let installed = disabledItem("  Installed version: \(info.installedVersion ?? "none")")
            let paths = info.scriptletPaths.sorted().map { disabledItem("    • \($0)") }
            return [header, cached, installed] + paths
        }
    }

    // MARK: - Preference titles

    private func updatePreferenceTitles() {
        let settings = self.settings
        analyticsItem.title = "youTubeAnalyticsEnabled: \(string(for: settings.youTubeAnalyticsEnabled))"
        disclosureItem.title = "shouldHideDisclosure: \(string(for: settings.shouldHideYouTubeAdBlockingDisclosure))"
    }

    private func string(for value: Bool?) -> String {
        value.map(String.init(describing:)) ?? "nil"
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
