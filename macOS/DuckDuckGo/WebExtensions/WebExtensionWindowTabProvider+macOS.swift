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
import Combine
import os.log
import WebExtensions
import WebKit

@available(macOS 15.4, *)
@MainActor
final class WebExtensionWindowTabProvider: WebExtensionWindowTabProviding {

    /// Keeps the open popover on the app's theme while it changes.
    private var popupAppearanceObservation: NSKeyValueObservation?
    /// Closes the open popover when its window switches tabs, since the popup is tied to the selected tab,
    /// or when another browser window becomes active, as Chrome does.
    private var popupDismissalCancellable: AnyCancellable?

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
        // Like Chrome, a popup window holds one page: further pages open as tabs in the last active regular window.
        let isPopup = configuration.windowType == .popup
        // Only the extension's own pages load with its web view configuration; websites get a regular tab's.
        let tabs = configuration.tabURLs.map { url in
            let isExtensionPage = url.scheme == context.baseURL.scheme
            return Tab(content: .contentFromURL(url, source: .ui),
                       webViewConfiguration: isExtensionPage ? context.webViewConfiguration : nil)
        }
        let burnerMode = BurnerMode(isBurner: configuration.shouldBePrivate)
        // Looked up before the popup opens, since the popup becomes the last active window.
        let regularWindowTabs = windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel
        let tabCollectionViewModel = TabCollectionViewModel(
            tabCollection: TabCollection(tabs: isPopup ? Array(tabs.prefix(1)) : tabs, isPopup: isPopup),
            burnerMode: burnerMode,
            windowControllersManager: windowControllersManager
        )

        // WebKit reports a position or size the extension didn't specify as NaN, which means "use the default".
        let frame = configuration.frame
        let mainWindow = windowControllersManager.openNewWindow(
            with: tabCollectionViewModel,
            burnerMode: burnerMode,
            droppingPoint: frame.origin.x.isNaN || frame.origin.y.isNaN ? nil : frame.origin,
            contentSize: frame.size.width.isNaN || frame.size.height.isNaN ? nil : frame.size,
            showWindow: configuration.shouldBeFocused,
            popUp: isPopup,
            isMiniaturized: configuration.windowState == .minimized,
            isMaximized: configuration.windowState == .maximized,
            isFullscreen: configuration.windowState == .fullscreen
        )

        if isPopup, tabs.count > 1 {
            let extraTabs = Array(tabs.dropFirst())
            if let regularWindowTabs, !regularWindowTabs.isPopup, regularWindowTabs.burnerMode == burnerMode {
                extraTabs.forEach { regularWindowTabs.append(tab: $0) }
            } else {
                windowControllersManager.openNewWindow(with: TabCollectionViewModel(tabCollection: TabCollection(tabs: extraTabs),
                                                                                    burnerMode: burnerMode),
                                                       burnerMode: burnerMode,
                                                       showWindow: true)
            }
        }

        // Like Chrome, an existing tab only moves into a regular window or an empty popup.
        if !isPopup || tabs.isEmpty {
            try? moveExistingTabs(configuration.tabs, to: tabCollectionViewModel)
        }

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
            MainActor.assumeMainThread {
                popupPopover?.appearance = app.effectiveAppearance
                popupWebView?.appearance = app.effectiveAppearance
            }
        }
        popupPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)

        let selectedTabChange = (windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel
            .$selectedTabViewModel
            .map { $0?.tab }
            .removeDuplicates(by: ===)
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()) ?? Empty().eraseToAnyPublisher()
        // Only browser windows count, so the Web Inspector can open on the popup without closing it.
        let otherBrowserWindowActivation = NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .compactMap { $0.object as? NSWindow }
            .filter { [weak buttonWindow = button.window] window in
                (window is MainWindow || window is PopUpWindow) && window !== buttonWindow
            }
            .map { _ in () }
        popupDismissalCancellable = selectedTabChange.merge(with: otherBrowserWindowActivation)
            .first()
            .sink { _ in
                action.closePopup()
            }
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
