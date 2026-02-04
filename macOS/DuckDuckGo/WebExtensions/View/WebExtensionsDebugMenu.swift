//
//  WebExtensionsDebugMenu.swift
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

import AppKit
import OSLog
import WebExtensions

@available(macOS 15.4, *)
final class WebExtensionsDebugMenu: NSMenu {

    private let webExtensionManager: WebExtensionManaging

    private let installExtensionMenuItem = NSMenuItem(title: "Install web extension", action: nil)
    private let uninstallAllExtensionsMenuItem = NSMenuItem(title: "Uninstall all extensions", action: #selector(WebExtensionsDebugMenu.uninstallAllExtensions))

    init(webExtensionManager: WebExtensionManaging) {
        self.webExtensionManager = webExtensionManager
        super.init(title: "")

        installExtensionMenuItem.submenu = makeInstallSubmenu()
        installExtensionMenuItem.isEnabled = true
        uninstallAllExtensionsMenuItem.target = self
        uninstallAllExtensionsMenuItem.isEnabled = webExtensionManager.hasInstalledExtensions

        addItems()
    }

    private func addItems() {
        removeAllItems()

        addItem(installExtensionMenuItem)
        addItem(uninstallAllExtensionsMenuItem)

        if !webExtensionManager.webExtensionIdentifiers.isEmpty {
            addItem(.separator())
            for identifier in webExtensionManager.webExtensionIdentifiers {
                let name = webExtensionManager.extensionName(for: identifier)
                let menuItem = WebExtensionMenuItem(identifier: identifier, webExtensionName: name)
                self.addItem(menuItem)
            }
        }
    }

    private func makeInstallSubmenu() -> NSMenu {
        let submenu = NSMenu()

        let browseItem = NSMenuItem(title: "Other...", action: #selector(selectAndLoadWebExtension))
        browseItem.target = self
        submenu.addItem(browseItem)

        submenu.addItem(.separator())

        return submenu
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update() {
        super.update()

        addItems()

        installExtensionMenuItem.isEnabled = true
        uninstallAllExtensionsMenuItem.isEnabled = webExtensionManager.hasInstalledExtensions
    }

    @objc func selectAndLoadWebExtension() {
        let panel = NSOpenPanel(allowedFileTypes: [.directory, .zip, .applicationExtension], directoryURL: .downloadsDirectory)
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        guard case .OK = panel.runModal(),
              let url = panel.url else { return }

        Task {
            try? await webExtensionManager.installExtension(from: url)
        }
    }

    @objc func uninstallAllExtensions() {
        webExtensionManager.uninstallAllExtensions()
    }
}

@available(macOS 15.4, *)
final class WebExtensionMenuItem: NSMenuItem {

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(identifier: String, webExtensionName: String?) {
        super.init(title: webExtensionName ?? identifier,
                   action: nil,
                   keyEquivalent: "")
        submenu = WebExtensionSubMenu(extensionIdentifier: identifier)
    }

}

@available(macOS 15.4, *)
final class WebExtensionSubMenu: NSMenu {

    private let extensionIdentifier: String

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(extensionIdentifier: String) {
        self.extensionIdentifier = extensionIdentifier
        super.init(title: "")

        buildItems {
            NSMenuItem(title: "Remove the extension", action: #selector(uninstallExtension), target: self)
        }
    }

    @objc func uninstallExtension() {
        guard let webExtensionManager = NSApp.delegateTyped.webExtensionManager else {
            return
        }

        try? webExtensionManager.uninstallExtension(identifier: extensionIdentifier)
    }
}
