//
//  WebExtensionManager+macOS.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import WebKit

// MARK: - macOS-specific WebExtensionManager Extensions

@available(macOS 15.4, *)
extension WebExtensionManager {

    /// Whether web extensions are enabled in the app.
    static var areExtensionsEnabled: Bool {
        NSApp.delegateTyped.webExtensionManager != nil
    }

    // MARK: - UI

    static let buttonSize: CGFloat = 28

    func toolbarButton(for context: WKWebExtensionContext) -> MouseOverButton {
        let image = context.webExtension.icon(for: CGSize(width: Self.buttonSize, height: Self.buttonSize)) ?? NSImage(named: "Web")!
        let button = MouseOverButton(image: image, target: self, action: #selector(toolbarButtonClicked))

        button.identifier = NSUserInterfaceItemIdentifier(context.uniqueIdentifier)
        button.bezelStyle = .shadowlessSquare
        button.cornerRadius = 4
        button.normalTintColor = .button
        button.translatesAutoresizingMaskIntoConstraints = false

        button.widthAnchor.constraint(equalToConstant: Self.buttonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: Self.buttonSize).isActive = true

        return button
    }

    @MainActor
    @objc func toolbarButtonClicked(sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else {
            assertionFailure("Web Extension toolbar button has no identifier")
            return
        }

        let context = contexts.first { context in
            context.uniqueIdentifier == identifier
        }

        guard let context else {
            assertionFailure("Navigation bar button for extension has no matching extension context")
            return
        }

        if let popover = context.action(for: nil)?.popupPopover, popover.isShown {
            popover.close()

            if sender.window != popover.mainWindow {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2/3) {
                    context.performAction(for: nil)
                }
            }
            return
        }

        context.performAction(for: nil)
    }
}

// MARK: - Factory

@available(macOS 15.4, *)
enum WebExtensionManagerFactory {

    /// Creates a fully configured WebExtensionManager with all macOS-specific providers.
    @MainActor
    static func makeManager() -> WebExtensionManager {
        let windowTabProvider = WebExtensionWindowTabProvider()
        let lifecycleDelegate = AppWebExtensionLifecycleDelegate()

        let manager = WebExtensionManager(
            configuration: WebExtensionConfigurationProvider(),
            windowTabProvider: windowTabProvider
        )

        manager.lifecycleDelegate = lifecycleDelegate

        let internalSiteHandler = WebExtensionInternalSiteHandler()
        internalSiteHandler.dataSource = manager
        manager.internalSiteHandler = internalSiteHandler

        return manager
    }
}
