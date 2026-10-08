//
//  WebExtensionWindowTabProvider+macOS.swift
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
import os.log
import WebExtensions
import WebKit

@available(macOS 15.4, *)
@MainActor
final class WebExtensionWindowTabProvider: WebExtensionWindowTabProviding {

    /// The action whose popover is open, so a popup that calls `window.close()` can close it.
    private weak var shownPopupAction: WKWebExtension.Action?

    /// Keeps the open popover on the app's theme while it changes.
    private var popupAppearanceObservation: NSKeyValueObservation?

    private var windowControllersManager: WindowControllersManager {
        Application.appDelegate.windowControllersManager
    }

    // MARK: - WebExtensionWindowTabProviding

    func openWindows(for context: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        var windows = windowControllersManager.mainWindowControllers
        if let focusedWindow = windowControllersManager.lastKeyMainWindowController {
            windows.removeAll { $0 === focusedWindow }
            windows.insert(focusedWindow, at: 0)
        }
        return windows
    }

    func focusedWindow(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        windowControllersManager.lastKeyMainWindowController
    }

    func openNewWindow(
        using configuration: WKWebExtension.WindowConfiguration,
        for context: WKWebExtensionContext
    ) async throws -> (any WKWebExtensionWindow)? {
        let tabs = configuration.tabURLs.map {
            Tab(content: .contentFromURL($0, source: .ui), webViewConfiguration: context.webViewConfiguration)
        }
        let burnerMode = BurnerMode(isBurner: configuration.shouldBePrivate)
        let tabCollectionViewModel = TabCollectionViewModel(
            tabCollection: TabCollection(tabs: tabs, isPopup: configuration.windowType == .popup),
            burnerMode: burnerMode,
            windowControllersManager: windowControllersManager
        )

        let mainWindow = windowControllersManager.openNewWindow(
            with: tabCollectionViewModel,
            burnerMode: burnerMode,
            droppingPoint: configuration.frame.origin,
            contentSize: configuration.frame.size,
            showWindow: configuration.shouldBeFocused,
            popUp: configuration.windowType == .popup,
            isMiniaturized: configuration.windowState == .minimized,
            isMaximized: configuration.windowState == .maximized,
            isFullscreen: configuration.windowState == .fullscreen
        )

        try? moveExistingTabs(configuration.tabs, to: tabCollectionViewModel)

        // swiftlint:disable:next force_cast
        return mainWindow?.windowController as! MainWindowController
    }

    func openNewTab(
        using configuration: WKWebExtension.TabConfiguration,
        for context: WKWebExtensionContext
    ) async throws -> (any WKWebExtensionTab)? {
        if let tabCollectionViewModel = windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel,
           let url = configuration.url {

            let content = TabContent.contentFromURL(url, source: .ui)
            let tab = Tab(content: content, burnerMode: tabCollectionViewModel.burnerMode)
            tabCollectionViewModel.append(tab: tab)
            return tab
        }

        assertionFailure("Failed to create tab based on configuration")
        return Tab(content: .newtab)
    }

    func openChromePage(_ url: URL, for context: WKWebExtensionContext) -> Bool {
        switch url.host {
        case "password-manager":
            windowControllersManager.showPreferencesTab(withSelectedPane: .autofill)
            return true
        case "extensions" where Application.appDelegate.internalUserDecider.isInternalUser:
            windowControllersManager.show(url: .webExtensions, source: .ui, newTab: true)
            return true
        default:
            return false
        }
    }

    func presentPopup(
        _ action: WKWebExtension.Action,
        for context: WKWebExtensionContext
    ) async throws {
        guard let button = buttonForContext(context) else {
            Logger.webExtensions.error("❌ No navigation bar button for \(context.uniqueIdentifier), popup not shown")
            return
        }

        guard action.presentsPopup else {
            // The extension declares an action without a popup, so the click is its own event.
            Logger.webExtensions.debug("🧩 Action of \(context.uniqueIdentifier) presents no popup")
            return
        }

        guard let popupPopover = action.popupPopover,
              let popupWebView = action.popupWebView
        else {
            Logger.webExtensions.error("❌ Action of \(context.uniqueIdentifier) has no popup popover or web view")
            return
        }

        popupWebView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        // WebKit's popover doesn't follow the app's theme on its own, so it takes the app's, also when it changes.
        popupAppearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak popupPopover, weak popupWebView] app, _ in
            MainActor.assumeIsolated {
                popupPopover?.appearance = app.effectiveAppearance
                popupWebView?.appearance = app.effectiveAppearance
            }
        }
        popupPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        shownPopupAction = action
    }

    func dismissPopup(for popupWebView: WKWebView) {
        guard let shownPopupAction, shownPopupAction.popupWebView === popupWebView else { return }
        shownPopupAction.closePopup()
    }

    // MARK: - Private Helpers

    private func moveExistingTabs(_ existingTabs: [any WKWebExtensionTab], to targetViewModel: TabCollectionViewModel) throws {
        guard !existingTabs.isEmpty else { return }

        for existingTab in existingTabs {
            guard
                let tab = existingTab as? Tab,
                let sourceViewModel = windowControllersManager.windowController(for: tab)?
                    .mainViewController.tabCollectionViewModel,
                let currentIndex = sourceViewModel.tabCollection.firstIndex(of: tab)
            else {
                assertionFailure("Failed to find tab collection view model for \(existingTab)")
                continue
            }

            sourceViewModel.moveTab(at: currentIndex, to: targetViewModel, at: targetViewModel.tabCollection.tabs.count)
        }
    }

    private func buttonForContext(_ context: WKWebExtensionContext) -> NSButton? {
        guard let mainWindowController = windowControllersManager.lastKeyMainWindowController else {
            assertionFailure("No main window controller")
            return nil
        }

        let targetIdentifier = NSUserInterfaceItemIdentifier(context.uniqueIdentifier)
        let button = mainWindowController.mainViewController.navigationBarViewController.menuButtons.arrangedSubviews
            .compactMap { $0 as? NSButton }
            .first { $0.identifier == targetIdentifier }

        return button
    }
}
