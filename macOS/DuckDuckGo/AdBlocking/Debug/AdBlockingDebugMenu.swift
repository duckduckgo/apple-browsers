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
import ConcurrencyExtensions
import PrivacyConfig
import Persistence
import WebExtensions

@MainActor
final class AdBlockingDebugMenu: NSMenuItem, NSMenuDelegate {

    private static let duckPlayerModeDefaultsKey = "preferences.duck-player"

    private var settings: any KeyedStoring<YouTubeAdBlockingSettings> {
        UserDefaults.standard.keyedStoring()
    }

    private var featureFlagger: FeatureFlagger {
        Application.appDelegate.featureFlagger
    }

    private var rolloutDefaultsActive: Bool {
        featureFlagger.isFeatureOn(.adBlockingExtensionEnabledByDefault)
    }

    private let scriptletsItem = NSMenuItem(title: "Scriptlets", action: nil, keyEquivalent: "")
    private let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
    private let youTubeAdBlockingEnabledItem = NSMenuItem(title: "youTubeAdBlockingEnabled", action: nil, keyEquivalent: "")
    private let duckPlayerModeItem = NSMenuItem(title: "duckPlayerMode", action: nil, keyEquivalent: "")
    private let flagsItem = NSMenuItem(title: "Flags", action: nil, keyEquivalent: "")
    private let analyticsItem = NSMenuItem(title: "youTubeAnalyticsEnabled", action: nil, keyEquivalent: "")
    private let disclosureItem = NSMenuItem(title: "shouldHideDisclosure", action: nil, keyEquivalent: "")
    private let unavailableNoticeItem = NSMenuItem(title: "Unavailable notice shown", action: nil, keyEquivalent: "")

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

        let settingsSubmenu = NSMenu(title: "Settings")

        let youTubeAdBlockingEnabledSubmenu = NSMenu(title: "youTubeAdBlockingEnabled")
        youTubeAdBlockingEnabledSubmenu.addItem(NSMenuItem(title: "Set to `true`",
                                                          action: #selector(setYouTubeAdBlockingEnabledTrue),
                                                          target: self))
        youTubeAdBlockingEnabledSubmenu.addItem(NSMenuItem(title: "Set to `false`",
                                                          action: #selector(setYouTubeAdBlockingEnabledFalse),
                                                          target: self))
        youTubeAdBlockingEnabledSubmenu.addItem(NSMenuItem(title: "Reset (delete key)",
                                                          action: #selector(resetYouTubeAdBlockingEnabled),
                                                          target: self))
        youTubeAdBlockingEnabledItem.submenu = youTubeAdBlockingEnabledSubmenu
        settingsSubmenu.addItem(youTubeAdBlockingEnabledItem)

        let duckPlayerModeSubmenu = NSMenu(title: "duckPlayerMode")
        duckPlayerModeSubmenu.addItem(NSMenuItem(title: "Set to `.enabled`",
                                                 action: #selector(setDuckPlayerModeEnabled),
                                                 target: self))
        duckPlayerModeSubmenu.addItem(NSMenuItem(title: "Set to `.disabled`",
                                                 action: #selector(setDuckPlayerModeDisabled),
                                                 target: self))
        duckPlayerModeSubmenu.addItem(NSMenuItem(title: "Reset (delete key — `.alwaysAsk`)",
                                                 action: #selector(resetDuckPlayerMode),
                                                 target: self))
        duckPlayerModeItem.submenu = duckPlayerModeSubmenu
        settingsSubmenu.addItem(duckPlayerModeItem)

        settingsItem.submenu = settingsSubmenu
        menu.addItem(settingsItem)

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

        let noticeSubmenu = NSMenu(title: "Unavailable notice shown")
        noticeSubmenu.addItem(NSMenuItem(title: "Reset (delete key)",
                                         action: #selector(resetUnavailableNoticeShown),
                                         target: self))
        unavailableNoticeItem.submenu = noticeSubmenu
        flagsSubmenu.addItem(unavailableNoticeItem)

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

    @objc private func setYouTubeAdBlockingEnabledTrue() {
        var settings = self.settings
        settings.youTubeAdBlockingEnabled = true
        notifyYouTubeAdBlockingEnabledChanged()
    }

    @objc private func setYouTubeAdBlockingEnabledFalse() {
        var settings = self.settings
        settings.youTubeAdBlockingEnabled = false
        notifyYouTubeAdBlockingEnabledChanged()
    }

    @objc private func resetYouTubeAdBlockingEnabled() {
        var settings = self.settings
        settings.removeValue(for: \.youTubeAdBlockingEnabled)
        notifyYouTubeAdBlockingEnabledChanged()
    }

    @objc private func setDuckPlayerModeEnabled() {
        UserDefaults.standard.set(true, forKey: Self.duckPlayerModeDefaultsKey)
        notifyDuckPlayerModeChanged()
    }

    @objc private func setDuckPlayerModeDisabled() {
        UserDefaults.standard.set(false, forKey: Self.duckPlayerModeDefaultsKey)
        notifyDuckPlayerModeChanged()
    }

    @objc private func resetDuckPlayerMode() {
        UserDefaults.standard.removeObject(forKey: Self.duckPlayerModeDefaultsKey)
        notifyDuckPlayerModeChanged()
    }

    private func notifyYouTubeAdBlockingEnabledChanged() {
        NotificationCenter.default.post(
            name: YouTubeAdBlockingPreferences.youTubeAdBlockingEnabledDidChangeNotification,
            object: nil
        )
    }

    private func notifyDuckPlayerModeChanged() {
        NotificationCenter.default.post(
            name: DuckPlayerPreferences.duckPlayerModeDidChangeNotification,
            object: nil
        )
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

    @objc private func resetUnavailableNoticeShown() {
        var settings = self.settings
        settings.removeValue(for: \.youTubeAdBlockUnavailableNoticeShown)
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
        youTubeAdBlockingEnabledItem.title = title(for: "youTubeAdBlockingEnabled",
                                                   value: settings.youTubeAdBlockingEnabled,
                                                   defaultLabel: rolloutDefaultsActive ? "true" : "false")
        duckPlayerModeItem.title = title(for: "duckPlayerMode",
                                         value: duckPlayerModeLabel(for: UserDefaults.standard.object(forKey: Self.duckPlayerModeDefaultsKey) as? Bool),
                                         defaultLabel: rolloutDefaultsActive ? ".disabled" : ".alwaysAsk")
        analyticsItem.title = "youTubeAnalyticsEnabled: \(string(for: settings.youTubeAnalyticsEnabled))"
        disclosureItem.title = "shouldHideDisclosure: \(string(for: settings.shouldHideYouTubeAdBlockingDisclosure))"
        unavailableNoticeItem.title = "Unavailable notice shown: \(string(for: settings.youTubeAdBlockUnavailableNoticeShown))"
    }

    private func title(for name: String, value: Bool?, defaultLabel: String) -> String {
        let raw = string(for: value)
        return value == nil ? "\(name): \(raw) (default: \(defaultLabel))" : "\(name): \(raw)"
    }

    private func title(for name: String, value: String, defaultLabel: String) -> String {
        return value == "nil" ? "\(name): \(value) (default: \(defaultLabel))" : "\(name): \(value)"
    }

    private func duckPlayerModeLabel(for stored: Bool?) -> String {
        switch stored {
        case true?: return ".enabled"
        case false?: return ".disabled"
        case nil: return "nil"
        }
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
