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
///
/// The updater reads the manager through a closure on every update, because the app delegate
/// releases the manager when the web extensions feature flag turns off and creates a new one when
/// it turns back on. When the closure returns `nil`, the updater removes every button.
@available(macOS 15.4, *)
@MainActor
final class WebExtensionNavigationBarUpdater: NSObject, ThemeUpdateListening, NSMenuDelegate {

    private enum Constants {
        static let buttonSize: CGFloat = 28
        static let iconSize = CGSize(width: 16, height: 16)
    }

    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?

    private let container: NSStackView
    private let webExtensionManagerProvider: () -> WebExtensionManaging?
    private let isPrivateWindow: Bool
    private var buttons = Set<MouseOverButton>()
    private var updateCancellable: AnyCancellable?

    /// Whether the toolbar buttons are shown. The navigation bar sets it from the selected tab's
    /// content, because an extension popup makes no sense on a tab without a web page.
    var buttonsAreVisible = true {
        didSet {
            guard buttonsAreVisible != oldValue else { return }
            for button in buttons {
                button.isHidden = !buttonsAreVisible
            }
        }
    }

    init(webExtensionManagerProvider: @escaping () -> WebExtensionManaging?,
         themeManager: ThemeManaging,
         container: NSStackView,
         isPrivateWindow: Bool = false) {
         self.webExtensionManagerProvider = webExtensionManagerProvider
        self.themeManager = themeManager
        self.container = container
        self.isPrivateWindow = isPrivateWindow

        super.init()

        subscribeToThemeChanges()
    }

    /// Adds the buttons for the extensions loaded so far, then keeps them in sync.
    func startUpdating() {
        updateLoadedExtensions()

        updateCancellable = NotificationCenter.default
            .publisher(for: .webExtensionsDidChangeLoadedExtensions)
            .merge(with: NotificationCenter.default.publisher(for: .webExtensionPrivateAccessDidChange))
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
        // Only third-party extensions that declare a toolbar action get a button. Our own
        // extensions stay out of the navigation bar, even Dark Reader, which declares an action popup.
        //
        // `loadedExtensions` is a set, so sort the contexts to keep the button order
        // the same between updates and between app launches.
        let loaded = webExtensionManagerProvider()?.loadedExtensions ?? []
        let contexts = loaded
            .filter { $0.needsChromeCompatibility && $0.declaresToolbarAction }
            .filter { !isPrivateWindow || $0.hasAccessToPrivateData }
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
            manifestVersion=\(context.webExtension.manifestVersion, privacy: .public) \
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
        button.isHidden = !buttonsAreVisible
        button.toolTip = context.webExtension.displayActionLabel ?? context.webExtension.displayName
        button.target = self
        button.action = #selector(toolbarButtonClicked)
        button.menu = ExtensionButtonMenu(button: button, context: context, delegate: self)

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

    /// The right-click menu of an extension button: the toolbar's own menu, plus, for internal users, the
    /// extension's API compatibility log. A button with a menu of its own would otherwise hide the toolbar's.
    private final class ExtensionButtonMenu: NSMenu {
        weak var button: NSView?
        /// The extension's name and version as the API compatibility log records them.
        let extensionName: String
        let version: String

        init(button: NSView, context: WKWebExtensionContext, delegate: NSMenuDelegate) {
            self.button = button
            self.extensionName = WebExtensionAPICompatibilityLog.sanitizedField(context.webExtension.displayName)
            self.version = WebExtensionAPICompatibilityLog.sanitizedField(context.webExtension.version)
            super.init(title: "")
            self.delegate = delegate
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    // MARK: - Actions

    @objc private func toolbarButtonClicked(sender: NSButton) {
        guard let identifier = sender.identifier?.rawValue else {
            assertionFailure("Web Extension toolbar button has no identifier")
            return
        }

        let context = webExtensionManagerProvider()?.loadedExtensions.first { context in
            context.uniqueIdentifier == identifier
        }

        guard let context, !isPrivateWindow || context.hasAccessToPrivateData else {
            assertionFailure("Navigation bar button for extension has no matching extension context")
            return
        }

        let action = context.action(for: nil)

        // A second click on the button of the open popup closes it.
        if let popupPresenter, popupPresenter.isShown(for: context) {
            Logger.webExtensions.debug("🧩 Click closes the open popup of \(identifier, privacy: .public)")
            popupPresenter.close()
            return
        }

        Logger.webExtensions.debug("""
        🧩 Click on \(identifier, privacy: .public): \
        action=\(action == nil ? "nil" : "present", privacy: .public) \
        presentsPopup=\(action?.presentsPopup ?? false, privacy: .public) \
        webView=\(action?.popupWebView == nil ? "nil" : "non-nil", privacy: .public)
        """)

        context.performAction(for: nil)
    }

    @objc private func showAPICompatibilityLog(sender: NSMenuItem) {
        guard let menu = sender.menu as? ExtensionButtonMenu else { return }
        WebExtensionAPICompatibilityLogWindowPresenter.show(extensionName: menu.extensionName, version: menu.version)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let menu = menu as? ExtensionButtonMenu else { return }
        menu.removeAllItems()

        // The toolbar fills in its own items, whose actions reach it through the responder chain.
        if let toolbarMenu = menu.button?.enclosingMenu {
            toolbarMenu.delegate?.menuNeedsUpdate?(menu)
        }

        guard NSApp.delegateTyped.internalUserDecider.isInternalUser else { return }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        let item = NSMenuItem(title: "JavaScript API Compatibility…", action: #selector(showAPICompatibilityLog))
        item.target = self
        menu.addItem(item)
    }

    /// The presenter that hosts extension popups, owned by the manager's window/tab provider.
    private var popupPresenter: WebExtensionPopupPresenter? {
        guard let manager = webExtensionManagerProvider() as? WebExtensionManager else { return nil }
        return (manager.windowTabProvider as? WebExtensionWindowTabProvider)?.popupPresenter
    }
}

private extension NSView {
    /// The menu of the nearest ancestor that has one.
    var enclosingMenu: NSMenu? {
        var view = superview
        while let current = view {
            if let menu = current.menu {
                return menu
            }
            view = current.superview
        }
        return nil
    }
}
