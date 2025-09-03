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

        if !webExtensionManager.webExtensionPaths.isEmpty {
            addItem(.separator())
            for webExtensionPath in webExtensionManager.webExtensionPaths {
                let name = webExtensionManager.extensionName(from: webExtensionPath)
                let menuItem = WebExtensionMenuItem(webExtensionPath: webExtensionPath, webExtensionName: name)
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

        let bitwardenItem = NSMenuItem(title: "Bitwarden", action: #selector(installBitwardenExtension))
        bitwardenItem.target = self
        submenu.addItem(bitwardenItem)

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
        let panel = NSOpenPanel(allowedFileTypes: [.directory, .applicationExtension], directoryURL: .downloadsDirectory)
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        guard case .OK = panel.runModal(),
              let url = panel.url else { return }

        Task {
            await webExtensionManager.installExtension(path: url.absoluteString)
        }
    }

    @objc func uninstallAllExtensions() {
        webExtensionManager.uninstallAllExtensions()
    }

    @objc func installBitwardenExtension() {
        let path = WebExtensionIdentifier.bitwarden.defaultPath
        Task {
            await webExtensionManager.installExtension(path: path)
        }
    }

}

@available(macOS 15.4, *)
final class WebExtensionMenuItem: NSMenuItem {

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(webExtensionPath: String, webExtensionName: String?) {
        super.init(title: webExtensionName ?? webExtensionPath,
                   action: nil,
                   keyEquivalent: "")
        submenu = WebExtensionSubMenu(webExtensionPath: webExtensionPath)
    }

}

@available(macOS 15.4, *)
final class WebExtensionSubMenu: NSMenu {

    private let webExtensionPath: String

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(webExtensionPath: String) {
        self.webExtensionPath = webExtensionPath
        super.init(title: "")

        buildItems {
            NSMenuItem(title: "Remove the extension", action: #selector(uninstallExtension), target: self)
        }
    }

    @objc func uninstallExtension() {
        guard let webExtensionManager = NSApp.delegateTyped.webExtensionManager else {
            return
        }

        try? webExtensionManager.uninstallExtension(path: webExtensionPath)
    }
}
