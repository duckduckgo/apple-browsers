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
    private let clearCachedScriptletsMenuItem = NSMenuItem(title: "Clear Cached Scriptlets", action: #selector(WebExtensionsDebugMenu.clearCachedScriptlets))
    private let printScriptletInfoMenuItem = NSMenuItem(title: "Print Scriptlet Info", action: #selector(WebExtensionsDebugMenu.printScriptletInfo))
    private let openExtensionsFolderMenuItem = NSMenuItem(title: "Open Extensions Folder in Finder", action: #selector(WebExtensionsDebugMenu.openExtensionsFolderInFinder))

    init(webExtensionManager: WebExtensionManaging) {
        self.webExtensionManager = webExtensionManager
        super.init(title: "")

        installExtensionMenuItem.submenu = makeInstallSubmenu()
        installExtensionMenuItem.isEnabled = true
        uninstallAllExtensionsMenuItem.target = self
        uninstallAllExtensionsMenuItem.isEnabled = true
        clearCachedScriptletsMenuItem.target = self
        clearCachedScriptletsMenuItem.isEnabled = true
        printScriptletInfoMenuItem.target = self
        printScriptletInfoMenuItem.isEnabled = true
        openExtensionsFolderMenuItem.target = self
        openExtensionsFolderMenuItem.isEnabled = true

        addItems()
    }

    private func addItems() {
        removeAllItems()

        addItem(installExtensionMenuItem)
        addItem(uninstallAllExtensionsMenuItem)
        addItem(clearCachedScriptletsMenuItem)
        addItem(printScriptletInfoMenuItem)
        addItem(.separator())
        addItem(openExtensionsFolderMenuItem)

        if !webExtensionManager.webExtensionIdentifiers.isEmpty {
            addItem(.separator())
            for identifier in webExtensionManager.webExtensionIdentifiers {
                let name = webExtensionManager.extensionName(for: identifier)
                let version = webExtensionManager.extensionVersion(for: identifier)
                let menuItem = WebExtensionMenuItem(identifier: identifier, webExtensionName: name, version: version)
                self.addItem(menuItem)
            }
        }
    }

    private func makeInstallSubmenu() -> NSMenu {
        let submenu = NSMenu()

        let browseItem = NSMenuItem(title: "Other…", action: #selector(selectAndLoadWebExtension))
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
        uninstallAllExtensionsMenuItem.isEnabled = true
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
        Task { @MainActor in
            webExtensionManager.uninstallAllExtensions()
        }
    }

    @objc func clearCachedScriptlets() {
        Task { @MainActor in
            webExtensionManager.clearCachedScriptlets()
        }
    }

    @objc func printScriptletInfo() {
        Task { @MainActor in
            let debugInfo = webExtensionManager.scriptletDebugInfo()
            if debugInfo.isEmpty {
                Logger.webExtensions.info("[Scriptlets Debug] No scriptlet data found")
                return
            }
            for info in debugInfo {
                Logger.webExtensions.info("""
                    [Scriptlets Debug] \(info.extensionType.rawValue) \
                    | cached: \(info.cachedVersion ?? "none") \
                    | installed: \(info.installedVersion ?? "none") \
                    | files: \(info.scriptletPaths.joined(separator: ", "))
                    """)
            }
        }
    }

    @objc func openExtensionsFolderInFinder() {
        let path = webExtensionManager.extensionsDirectory.path
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }
}

@available(macOS 15.4, *)
final class WebExtensionMenuItem: NSMenuItem {

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(identifier: String, webExtensionName: String?, version: String?, submenu: NSMenu? = nil) {
        let displayName = webExtensionName ?? identifier
        let title = version.map { "\(displayName) v\($0)" } ?? displayName
        super.init(title: title, action: nil, keyEquivalent: "")
        self.submenu = submenu ?? WebExtensionSubMenu(extensionIdentifier: identifier)
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

        Task { @MainActor in
            try? webExtensionManager.uninstallExtension(identifier: extensionIdentifier)
        }
    }
}
