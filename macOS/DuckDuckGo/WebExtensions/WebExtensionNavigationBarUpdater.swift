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
        static let alertIconSize = CGSize(width: 64, height: 64)
    }

    let themeManager: ThemeManaging
    var themeUpdateCancellable: AnyCancellable?

    private let container: NSStackView
    private let webExtensionManagerProvider: () -> WebExtensionManaging?
    private let isPrivateWindow: Bool
    private let selectedTabProvider: () -> WKWebExtensionTab?
    private var buttons = Set<ExtensionButton>()
    private var updateCancellable: AnyCancellable?
    private var actionCancellable: AnyCancellable?

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
         isPrivateWindow: Bool = false,
         selectedTabProvider: @escaping () -> WKWebExtensionTab? = { nil }) {
         self.webExtensionManagerProvider = webExtensionManagerProvider
        self.selectedTabProvider = selectedTabProvider
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

        actionCancellable = NotificationCenter.default
            .publisher(for: .webExtensionActionDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self, let context = notification.object as? WKWebExtensionContext else { return }
                for button in self.buttons where button.identifier?.rawValue == context.uniqueIdentifier {
                    self.applyAction(of: context, to: button)
                }
            }
    }

    /// Shows each extension's action for the selected tab, since an extension can set a different
    /// icon on every tab.
    func refreshActions() {
        let loaded = webExtensionManagerProvider()?.loadedExtensions ?? []
        for button in buttons {
            guard let context = loaded.first(where: { $0.uniqueIdentifier == button.identifier?.rawValue }) else { continue }
            applyAction(of: context, to: button)
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
        // extensions (even though most of them declare none) are forced out of the
        // navigation bar by the logic in `declaresToolbarAction`.
        //
        // `loadedExtensions` is a set, so sort the contexts to keep the button order
        // the same between updates and between app launches.
        let loaded = webExtensionManagerProvider()?.loadedExtensions ?? []
        let contexts = loaded
            .filter(\.declaresToolbarAction)
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

    /// The extension's action for the selected tab, or its default action when no tab is selected.
    private func currentAction(of context: WKWebExtensionContext) -> WKWebExtension.Action? {
        selectedTabProvider().flatMap { context.action(for: $0) } ?? context.action(for: nil)
    }

    /// Shows the extension's current action for the selected tab, which its JavaScript can change,
    /// falling back to its manifest.
    /// The extension supplies its own artwork, so the button keeps no tint color.
    private func applyAction(of context: WKWebExtensionContext, to button: ExtensionButton) {
        let action = currentAction(of: context)
        button.image = action?.icon(for: Constants.iconSize)
            ?? context.webExtension.actionIcon(for: Constants.iconSize)
            ?? context.webExtension.icon(for: Constants.iconSize)
        let label = action?.label ?? ""
        button.toolTip = !label.isEmpty ? label : (context.webExtension.displayActionLabel ?? context.webExtension.displayName)
        button.isEnabled = action?.isEnabled ?? true
        button.badgeText = action?.badgeText ?? ""
    }

    private func toolbarButton(for context: WKWebExtensionContext) -> ExtensionButton {
        let button = ExtensionButton(frame: NSRect(x: 0, y: 0, width: Constants.buttonSize, height: Constants.buttonSize))

        // `presentPopup(_:for:)` looks the button up by this identifier.
        button.identifier = NSUserInterfaceItemIdentifier(context.uniqueIdentifier)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.isHidden = !buttonsAreVisible
        button.target = self
        button.action = #selector(toolbarButtonClicked)
        button.menuProvider = { [weak self, weak context] in
            guard let self, let context else { return nil }
            return self.contextMenu(for: context)
        }

        applyAction(of: context, to: button)

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

    // MARK: - Added Popover

    func showAddedPopover(forChromeWebStoreID id: String, parent: NSViewController) {
        let storeIdentity = WebExtensionStoreIdentity(store: .chromeWebStore, id: id)
        guard let manager = webExtensionManagerProvider(),
              let identifier = manager.webExtensionIdentifiers.first(where: { manager.installedExtension(identifier: $0)?.storeIdentity == storeIdentity }) else { return }
        showAddedPopover(forExtensionWithIdentifier: identifier, parent: parent)
    }

    private func showAddedPopover(forExtensionWithIdentifier identifier: String, parent: NSViewController) {
        // The button update for this install may still be queued on the main queue.
        updateLoadedExtensions()

        guard let button = buttons.first(where: { $0.identifier?.rawValue == identifier }), !button.isHidden,
              let context = webExtensionManagerProvider()?.loadedExtensions.first(where: { $0.uniqueIdentifier == identifier }) else { return }

        let popover = WebExtensionAddedPopoverViewController(extensionName: Self.displayName(of: context),
                                                             iconProvider: context.webExtension.icon(for:),
                                                             themeManager: themeManager)
        popover.show(onParent: parent, relativeTo: button)
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

        let selectedTab = selectedTabProvider()
        let action = currentAction(of: context)

        // A second click on the button of the open popup closes it.
        if let action, action.popupPopover?.isShown == true {
            Logger.webExtensions.debug("🧩 Click closes the open popup of \(identifier, privacy: .public)")
            action.closePopup()
            return
        }

        Logger.webExtensions.debug("""
        🧩 Click on \(identifier, privacy: .public): \
        action=\(action == nil ? "nil" : "present", privacy: .public) \
        presentsPopup=\(action?.presentsPopup ?? false, privacy: .public) \
        webView=\(action?.popupWebView == nil ? "nil" : "non-nil", privacy: .public)
        """)

        context.performAction(for: selectedTab)
    }

    @objc private func showAPICompatibilityLog(sender: NSMenuItem) {
        guard let context = sender.representedObject as? WKWebExtensionContext else { return }
        WebExtensionAPICompatibilityLogWindowPresenter.show(
            extensionName: WebExtensionAPICompatibilityLog.sanitizedField(context.webExtension.displayName),
            version: WebExtensionAPICompatibilityLog.sanitizedField(context.webExtension.version)
        )
    }

    /// Asks the user to confirm, then uninstalls the extension. Removing its button follows from
    /// the manager's change notification.
    @objc private func removeExtension(sender: NSMenuItem) {
        guard let context = sender.representedObject as? WKWebExtensionContext else { return }
        let identifier = context.uniqueIdentifier
        let window = buttons.first { $0.identifier?.rawValue == identifier }?.window

        let alert = NSAlert()
        alert.messageText = String(format: UserText.chromeWebStoreRemoveTitle, Self.displayName(of: context))
        if let icon = context.webExtension.icon(for: Constants.alertIconSize) {
            alert.icon = icon
        }
        alert.addButton(withTitle: UserText.webExtensionRemoveButton)
        alert.addButton(withTitle: UserText.cancel)

        Task { @MainActor [weak self] in
            let response = await Self.present(alert, in: window)
            guard response == .alertFirstButtonReturn, let manager = self?.webExtensionManagerProvider() else { return }

            do {
                try manager.uninstallExtension(identifier: identifier)
            } catch {
                Logger.webExtensions.error("❌ Failed to remove extension \(identifier, privacy: .public): \(error.localizedDescription)")
                let errorAlert = NSAlert()
                errorAlert.messageText = UserText.chromeWebStoreErrorTitle
                errorAlert.informativeText = UserText.webExtensionRemoveErrorMessage
                errorAlert.addButton(withTitle: UserText.ok)
                _ = await Self.present(errorAlert, in: window)
            }
        }
    }

    private static func present(_ alert: NSAlert, in window: NSWindow?) async -> NSApplication.ModalResponse {
        if let window, window.attachedSheet == nil {
            return await alert.beginSheetModal(for: window)
        }
        return await alert.runModal()
    }

    private static func displayName(of context: WKWebExtensionContext) -> String {
        context.webExtension.displayName ?? context.webExtension.displayShortName ?? UserText.webExtensionUnnamedExtension
    }

    // MARK: - Context Menu

    /// The right-click menu of an extension button: a header with the extension's name, the items the
    /// extension adds with `contextMenus.create({ contexts: ["action"] })`, the item that removes the extension,
    /// plus, for internal users, the extension's API compatibility log.
    /// WebKit can change the extension's items at any time, so the menu is built on demand.
    private func contextMenu(for context: WKWebExtensionContext) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: Self.displayName(of: context)))
        (currentAction(of: context)?.menuItems ?? []).forEach(menu.addItem)

        menu.addItem(.separator())
        let removeItem = NSMenuItem(title: UserText.webExtensionRemoveMenuItem, action: #selector(removeExtension))
        removeItem.target = self
        removeItem.representedObject = context
        menu.addItem(removeItem)

        if NSApp.delegateTyped.internalUserDecider.isInternalUser {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Extension Compatibility Log…", action: #selector(showAPICompatibilityLog))
            item.target = self
            item.representedObject = context
            menu.addItem(item)
        }

        return menu
    }
}

/// The toolbar button of one web extension, with the extension's badge and context menu.
@available(macOS 15.4, *)
private final class ExtensionButton: MouseOverButton {

    private enum Constants {
        static let badgeHeight: CGFloat = 12
        static let badgeHorizontalPadding: CGFloat = 3
        static let badgeFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
    }

    /// Builds the right-click menu when the user opens it. `nil` shows no menu.
    var menuProvider: (() -> NSMenu?)?

    /// The text the extension sets with `action.setBadgeText`. An empty string hides the badge.
    var badgeText: String = "" {
        didSet {
            guard badgeText != oldValue else { return }
            badgeLabel.stringValue = badgeText
            badgeView.isHidden = badgeText.isEmpty
        }
    }

    private let badgeView = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpBadge()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Only the extension's menu applies to its button, not the toolbar's.
    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }

    override func rightMouseDown(with event: NSEvent) {
        // Without a menu, `super` passes the event on to the toolbar, which shows its own menu.
        guard let menu = menu(for: event) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func setUpBadge() {
        badgeLabel.font = Constants.badgeFont
        badgeLabel.textColor = .white
        badgeLabel.alignment = .center
        badgeLabel.lineBreakMode = .byClipping
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        badgeView.wantsLayer = true
        badgeView.layer?.backgroundColor = NSColor.systemRed.cgColor
        badgeView.layer?.cornerRadius = Constants.badgeHeight / 2
        badgeView.isHidden = true
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.addSubview(badgeLabel)
        addSubview(badgeView)

        NSLayoutConstraint.activate([
            badgeLabel.leadingAnchor.constraint(equalTo: badgeView.leadingAnchor, constant: Constants.badgeHorizontalPadding),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: -Constants.badgeHorizontalPadding),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),

            badgeView.heightAnchor.constraint(equalToConstant: Constants.badgeHeight),
            badgeView.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.badgeHeight),
            badgeView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            badgeView.trailingAnchor.constraint(equalTo: trailingAnchor),
            badgeView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
