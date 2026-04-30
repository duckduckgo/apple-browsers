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
import WebExtensions

@MainActor
final class AdBlockingDebugMenu: NSMenuItem, NSMenuDelegate {

    private static let scriptletDebugInfoTag = 1000

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
        return menu
    }

    // MARK: - NSMenuDelegate

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeMainThread {
            rebuildScriptletDebugInfoItems(in: menu)
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

    // MARK: - Scriptlet Debug Info

    private func rebuildScriptletDebugInfoItems(in menu: NSMenu) {
        menu.items
            .filter { $0.tag == Self.scriptletDebugInfoTag }
            .forEach { menu.removeItem($0) }

        guard #available(macOS 15.4, *) else { return }

        for item in scriptletDebugInfoItems() {
            item.tag = Self.scriptletDebugInfoTag
            menu.addItem(item)
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

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
