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

@available(macOS 15.4, *)
final class WebExtensionsDebugMenu: NSMenu {

    private let webExtensionManager: WebExtensionManaging

    private let installExtensionMenuItem = NSMenuItem(title: "Install web extension", action: nil)
    private let uninstallAllExtensionsMenuItem = NSMenuItem(title: "Uninstall all extensions", action: #selector(WebExtensionsDebugMenu.uninstallAllExtensions))

    init(webExtensionManager: WebExtensionManaging = WebExtensionManager.shared) {
        self.webExtensionManager = webExtensionManager
        super.init(title: "")

        installExtensionMenuItem.submenu = makeInstallSubmenu()
        installExtensionMenuItem.isEnabled = webExtensionManager.areExtenstionsEnabled
        uninstallAllExtensionsMenuItem.target = self
        uninstallAllExtensionsMenuItem.isEnabled = webExtensionManager.areExtenstionsEnabled && webExtensionManager.hasInstalledExtensions

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

        installExtensionMenuItem.isEnabled = webExtensionManager.areExtenstionsEnabled
        uninstallAllExtensionsMenuItem.isEnabled = webExtensionManager.areExtenstionsEnabled && webExtensionManager.hasInstalledExtensions
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
    private let webExtensionManager: WebExtensionManaging

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(webExtensionPath: String, webExtensionManager: WebExtensionManaging = WebExtensionManager.shared) {
        self.webExtensionManager = webExtensionManager
        self.webExtensionPath = webExtensionPath
        super.init(title: "")

        buildItems {
            NSMenuItem(title: "Remove the extension", action: #selector(uninstallExtension), target: self)
            NSMenuItem(title: "Open Background Inspector", action: #selector(openBackgroundInspector), target: self)
        }
    }

    @objc func uninstallExtension() {
        try? webExtensionManager.uninstallExtension(path: webExtensionPath)
    }

    @MainActor
    @objc func openBackgroundInspector() {
        guard let context = webExtensionManager.context(forPath: webExtensionPath) else {
            print("No context found for path: \(webExtensionPath)")
            return
        }

        guard let webViewConfiguration = context.webViewConfiguration else {
            print("No webViewConfiguration available for context")
            return
        }

        // Construct the URL for background.html
        let backgroundURL = context.baseURL.appendingPathComponent("background.html")

        // Use WindowsManager to create a standard popup window
        let tabCollection = TabCollectionViewModel()
        if let window = WindowsManager.openNewWindow(with: tabCollection) {
            let webView = WebView(frame: .zero, configuration: webViewConfiguration)
            window.contentViewController?.view = webView
            window.setContentSize(NSSize(width: 800, height: 600))
            window.title = "Background Inspector"
            window.makeKeyAndOrderFront(nil)

            // Load the URL in the new WebView
            let request = URLRequest(url: backgroundURL)
            webView.load(request)

            // Open the developer tools to show the inspector
            webView.openDeveloperTools()
        } else {
            print("Failed to create a new window using WindowsManager")
        }
    }

}
