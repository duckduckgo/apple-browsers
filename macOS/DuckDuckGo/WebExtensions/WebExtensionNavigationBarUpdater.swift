//
//  WebExtensionNavigationBarUpdater.swift
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
import Combine
import os.log
import WebExtensions
import WebKit

/// Keeps one navigation bar toolbar button per loaded web extension.
///
/// The button is also the anchor the extension popup needs:
/// `WebExtensionWindowTabProvider.presentPopup(_:for:)` finds it by the extension's
/// unique identifier, so an extension without a button shows no popup at all.
///
/// Each browser window owns its own updater, because each window has its own navigation bar.
@available(macOS 15.4, *)
@MainActor
final class WebExtensionNavigationBarUpdater: NSObject, ThemeUpdateListening {

    private enum Constants {
        static let buttonSize: CGFloat = 28
        static let iconSize = CGSize(width: 16, height: 16)
    }

    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?

    private let container: NSStackView
    private let webExtensionManager: WebExtensionManaging
    private var buttons = Set<MouseOverButton>()
    private var updateCancellable: AnyCancellable?

    init(webExtensionManager: WebExtensionManaging,
         themeManager: ThemeManaging,
         container: NSStackView) {
        self.webExtensionManager = webExtensionManager
        self.themeManager = themeManager
        self.container = container

        super.init()

        subscribeToThemeChanges()
    }

    /// Adds the buttons for the extensions loaded so far, then keeps them in sync.
    func startUpdating() {
        updateLoadedExtensions()

        updateCancellable = NotificationCenter.default
            .publisher(for: .webExtensionsDidChangeLoadedExtensions)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateLoadedExtensions()
            }
    }

    func applyThemeStyle(theme: ThemeStyleProviding) {
        for button in buttons {
            applyThemeStyle(theme: theme, to: button)
        }
    }

    // MARK: - Buttons

    private func updateLoadedExtensions() {
        // Only extensions that declare a toolbar action get a button. Our own embedded
        // extensions declare none, so they stay out of the navigation bar.
        //
        // `loadedExtensions` is a set, so sort the contexts to keep the button order
        // the same between updates and between app launches.
        let loaded = webExtensionManager.loadedExtensions
        let contexts = loaded
            .filter(\.declaresToolbarAction)
            .sorted { $0.uniqueIdentifier < $1.uniqueIdentifier }

        logLoadedExtensions(loaded, withButtons: contexts)

        removeButtons(forExtensionsRemovedFrom: contexts)
        addButtons(forExtensionsAddedTo: contexts)

        container.needsDisplay = true
    }

    /// Records which loaded extensions get a toolbar button, and which do not.
    ///
    /// An extension without a button also gets no popup, because
    /// `WebExtensionWindowTabProvider.presentPopup(_:for:)` anchors the popup to the button.
    /// This log separates "no button" from "button, but the popup fails".
    private func logLoadedExtensions(_ loaded: Set<WKWebExtensionContext>,
                                     withButtons contexts: [WKWebExtensionContext]) {
        guard !loaded.isEmpty else {
            Logger.webExtensions.debug("🧩 Navigation bar: no loaded extensions")
            return
        }

        for context in loaded.sorted(by: { $0.uniqueIdentifier < $1.uniqueIdentifier }) {
            let hasButton = contexts.contains { $0.uniqueIdentifier == context.uniqueIdentifier }
            Logger.webExtensions.debug("""
            🧩 Navigation bar: \(context.webExtension.displayName ?? "unnamed", privacy: .public) \
            \(context.uniqueIdentifier, privacy: .public) \
            manifestVersion=\(Int(context.webExtension.manifestVersion), privacy: .public) \
            declaresToolbarAction=\(context.declaresToolbarAction, privacy: .public) \
            button=\(hasButton, privacy: .public)
            """)
        }
    }

    private func removeButtons(forExtensionsRemovedFrom contexts: [WKWebExtensionContext]) {
        for button in buttons {
            guard let identifier = button.identifier?.rawValue,
                  !contexts.contains(where: { $0.uniqueIdentifier == identifier }) else {

                continue
            }

            buttons.remove(button)
            button.removeFromSuperview()
        }
    }

    private func addButtons(forExtensionsAddedTo contexts: [WKWebExtensionContext]) {
        let buttonIdentifiers = buttons.compactMap {
            $0.identifier?.rawValue
        }

        for (index, context) in contexts.enumerated() where !buttonIdentifiers.contains(context.uniqueIdentifier) {

            let newButton = toolbarButton(for: context)
            container.insertArrangedSubview(newButton, at: min(index, container.arrangedSubviews.count))

            buttons.insert(newButton)
        }
    }

    private func toolbarButton(for context: WKWebExtensionContext) -> MouseOverButton {
        let button = MouseOverButton(frame: NSRect(x: 0, y: 0, width: Constants.buttonSize, height: Constants.buttonSize))

        // `presentPopup(_:for:)` looks the button up by this identifier.
        button.identifier = NSUserInterfaceItemIdentifier(context.uniqueIdentifier)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = context.webExtension.displayActionLabel ?? context.webExtension.displayName
        button.target = self
        button.action = #selector(toolbarButtonClicked)

        // The extension supplies its own artwork, so the button keeps no tint color.
        button.image = context.webExtension.actionIcon(for: Constants.iconSize)
            ?? context.webExtension.icon(for: Constants.iconSize)

        applyThemeStyle(theme: theme, to: button)

        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            button.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
        ])

        return button
    }

    private func applyThemeStyle(theme: ThemeStyleProviding, to button: MouseOverButton) {
        button.mouseOverColor = theme.colorsProvider.buttonMouseOverColor
        button.cornerRadius = theme.toolbarButtonsCornerRadius
    }

    // MARK: - Actions

    @objc private func toolbarButtonClicked(sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else {
            assertionFailure("Web Extension toolbar button has no identifier")
            return
        }

        let context = webExtensionManager.loadedExtensions.first { context in
            context.uniqueIdentifier == identifier
        }

        guard let context else {
            assertionFailure("Navigation bar button for extension has no matching extension context")
            return
        }

        // A second click on the button of the open popup closes it.
        if let popupPresenter, popupPresenter.isShown(for: context) {
            Logger.webExtensions.debug("🧩 Click closes the open popup of \(identifier, privacy: .public)")
            popupPresenter.close()
            return
        }

        let action = context.action(for: nil)
        Logger.webExtensions.debug("""
        🧩 Click on \(identifier, privacy: .public): \
        action=\(action == nil ? "nil" : "present", privacy: .public) \
        presentsPopup=\(action?.presentsPopup ?? false, privacy: .public) \
        webView=\(action?.popupWebView == nil ? "nil" : "non-nil", privacy: .public)
        """)

        context.performAction(for: nil)
    }

    /// The presenter that hosts extension popups, owned by the manager's window/tab provider.
    private var popupPresenter: WebExtensionPopupPresenter? {
        guard let manager = webExtensionManager as? WebExtensionManager else { return nil }
        return (manager.windowTabProvider as? WebExtensionWindowTabProvider)?.popupPresenter
    }
}
