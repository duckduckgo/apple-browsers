//
//  WebExtensionManager.swift
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

#if WEB_EXTENSIONS_ENABLED

import Foundation
import Common
import WebKit
import os.log
import BrowserServicesKit

@available(macOS 15.4, *)
protocol WebExtensionManaging {

    var areExtenstionsEnabled: Bool { get }

    @MainActor
    func loadWebExtensions() async

    // Adding and removing extensions
    var webExtensionPaths: [String] { get }
    func addExtension(path: String)
    func removeExtension(path: String)

    // Provides the extension name for the extension resource base path
    func extensionName(from path: String) -> String?

    // Controller for tabs
    var controller: WKWebExtensionController? { get }

    // Listening of events
    var eventsListener: WebExtensionEventsListening { get }

}

// Manages the initialization and ownership of key components: web extensions, contexts, and the controller
@available(macOS 15.4, *)
final class WebExtensionManager: NSObject, WebExtensionManaging {

    static let shared = WebExtensionManager()

    init(webExtensionPathsCache: WebExtensionPathsCaching = WebExtensionPathsCache(),
         webExtensionLoader: WebExtensionLoading = WebExtensionLoader(),
         internalUserDecider: InternalUserDecider = NSApp.delegateTyped.internalUserDecider,
         featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger) {
        self.pathsCache = webExtensionPathsCache
        self.internalUserDecider = internalUserDecider
        self.featureFlagger = featureFlagger
        self.loader = webExtensionLoader
        super.init()

        internalSiteHandler.dataSource = self
    }

    private let internalUserDecider: InternalUserDecider
    private let featureFlagger: FeatureFlagger

    var areExtenstionsEnabled: Bool {
        return internalUserDecider.isInternalUser && featureFlagger.isFeatureOn(.webExtensions)
    }

    // Caches paths to selected web extensions
    var pathsCache: WebExtensionPathsCaching

    // Loads web extensions after selection or application start
    var loader: WebExtensionLoading

    // Loaded extensions
    var extensions: [WKWebExtension] = []

    // Context manages the extension's permissions and allows it to inject content, run background logic, show popovers, and display other web-based UI to the user.
    var contexts: [WKWebExtensionContext] = []

    // Controller manages a set of loaded extension contexts
    var controller: WKWebExtensionController?

    // Events listening
    var eventsListener: WebExtensionEventsListening = WebExtensionEventsListener()

    // Handles native messaging
    let nativeMessagingHandler = NativeMessagingHandler()

    // Handles internal sites of web extenions
    let internalSiteHandler = WebExtensionInternalSiteHandler()

    // MARK: - Adding and removing extensions
    var webExtensionPaths: [String] {
        pathsCache.cache
    }

    func addExtension(path: String) {
        pathsCache.add(path)
    }

    func removeExtension(path: String) {
        pathsCache.remove(path)
    }

    func extensionName(from path: String) -> String? {
        if let extensionURL = URL(string: path) {
            return extensionURL.lastPathComponent
        }
        return nil
    }

    // MARK: - Lifecycle

    @MainActor
    func loadWebExtensions() async {
        guard areExtenstionsEnabled else { return }

        // Load extensions
        extensions = await loader.loadWebExtensions(from: pathsCache.cache)

        // Make contexts
        contexts = extensions.compactMap {
            makeContext(for: $0)
        }

        // Make controller and load extension contexts
        let controller = WKWebExtensionController()
        do {
            try contexts.forEach {
                try controller.load($0)
            }
        } catch {
            assertionFailure("Failed to load extension context: \(error)")
            return
        }

        controller.delegate = self
        eventsListener.controller = controller
        self.controller = controller
    }

    private func makeContext(for webExtension: WKWebExtension) -> WKWebExtensionContext? {
        let context = WKWebExtensionContext(for: webExtension)

        // Temporary fix to have the same state on multiple browser sessions
        context.uniqueIdentifier = UUID(uuidString: "36dbd1f8-27c7-43fd-a206-726958a1018d")!.uuidString

        // In future, we should grant only what the extension requests.
        let matchPatterns = context.webExtension.allRequestedMatchPatterns
        for pattern in matchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern, expirationDate: nil)
        }
        let permissions: [WKWebExtension.Permission] = (["activeTab", "alarms", "clipboardWrite", "contextMenus", "cookies", "declarativeNetRequest", "declarativeNetRequestFeedback", "declarativeNetRequestWithHostAccess", "menus", "nativeMessaging", "notifications", "scripting", "sidePanel", "storage", "tabs", "unlimitedStorage", "webNavigation", "webRequest"]).map {
            WKWebExtension.Permission($0)
        }
        for permission in permissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission, expirationDate: nil)
        }

        // For debugging purposes
        context.isInspectable = true
        return context
    }

    // MARK: - UI

    static let buttonSize: CGFloat = 28

    func toolbarButtons() -> [MouseOverButton] {
        return contexts.enumerated().map { (index, context) in
            let image = context.webExtension.icon(for: CGSize(width: Self.buttonSize, height: Self.buttonSize)) ?? NSImage(named: "Web")!
            let button = MouseOverButton(image: image, target: self, action: #selector(WebExtensionManager.toolbarButtonClicked))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: Self.buttonSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: Self.buttonSize).isActive = true
            button.tag = index
            return button
        }
    }

    @MainActor
    @objc func toolbarButtonClicked(sender: NSButton) {
        let index = sender.tag
        let context = contexts[index]

        // If the popover is already open
        if let popover = context.action(for: nil)?.popupPopover, popover.isShown {
            // Close it
            popover.close()

            // If the sender button is in a different window, open the popover there
            if sender.window != popover.mainWindow {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2/3) {
                    context.performAction(for: nil)
                }
            }
            return
        }
        // Show dashboard - perform default action
        context.performAction(for: nil)
    }

    @MainActor
    func buttonForContext(_ context: WKWebExtensionContext) -> NSButton? {
        guard let index = contexts.firstIndex(of: context) else {
            assertionFailure("Unknown context")
            return nil
        }

        guard let mainWindowController = WindowControllersManager.shared.lastKeyMainWindowController else {
            assertionFailure("No main window controller")
            return nil
        }

        let button = mainWindowController.mainViewController.navigationBarViewController.menuButtons.arrangedSubviews[index] as? NSButton
        return button
    }

}

@available(macOS 15.4, *)
@MainActor
extension WebExtensionManager: WKWebExtensionControllerDelegate {

    enum WKWebExtensionControllerDelegateError: Error {
        case notSupported
    }

    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        var windows = WindowControllersManager.shared.mainWindowControllers
        if let focusedWindow = WindowControllersManager.shared.lastKeyMainWindowController {
            // Ensure focusedWindow is the first item
            windows.removeAll { $0 === focusedWindow }
            windows.insert(focusedWindow, at: 0)
        }
        return windows
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        return WindowControllersManager.shared.lastKeyMainWindowController
    }

    private func webExtensionController(_ controller: WKWebExtensionController!, openNewWindowUsingConfiguration configuration: WKWebExtension.WindowConfiguration!, for extensionContext: WKWebExtensionContext!) async throws -> any WKWebExtensionWindow {
        // Extract options
        let tabs = configuration.tabURLs.map { Tab(content: .contentFromURL($0, source: .ui)) }
        let burnerMode = BurnerMode(isBurner: configuration.shouldBePrivate)
        let tabCollectionViewModel = TabCollectionViewModel(
            tabCollection: TabCollection(tabs: tabs),
            burnerMode: burnerMode
        )

        // Create new window
        let mainWindow = WindowControllersManager.shared.openNewWindow(
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

        // Move existing tabs if necessary
        try? moveExistingTabs(configuration.tabs, to: tabCollectionViewModel)

        // swiftlint:disable:next force_cast
        return mainWindow?.windowController as! MainWindowController
    }

    private func moveExistingTabs(_ existingTabs: [any WKWebExtensionTab], to targetViewModel: TabCollectionViewModel) throws {
        guard !existingTabs.isEmpty else { return }

        for existingTab in existingTabs {
            guard
                let tab = existingTab as? Tab,
                let sourceViewModel = WindowControllersManager.shared.windowController(for: tab)?
                    .mainViewController.tabCollectionViewModel,
                let currentIndex = sourceViewModel.tabCollection.tabs.firstIndex(of: tab)
            else {
                assertionFailure("Failed to find tab collection view model for \(existingTab)")
                continue
            }

            sourceViewModel.moveTab(at: currentIndex, to: targetViewModel, at: targetViewModel.tabs.count)
        }
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration, for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        if let tabCollectionViewModel = WindowControllersManager.shared.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel,
           let url = configuration.url {

            let content = TabContent.contentFromURL(url, source: .ui)
            let tab = Tab(content: content,
                          burnerMode: tabCollectionViewModel.burnerMode)
            tabCollectionViewModel.append(tab: tab)
            return tab
        }

        assertionFailure("Failed create tab based on configuration")
        return Tab(content: .newtab)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext) async throws {
        throw WKWebExtensionControllerDelegateError.notSupported
    }

    private func webExtensionController(_ controller: WKWebExtensionController!, promptForPermissions permissions: Set<WKWebExtension.Permission>!, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext!) async -> (Set<WKWebExtension.Permission>?, Date?) {
        return (permissions, nil)
    }

    private func webExtensionController(_ controller: WKWebExtensionController!, promptForPermissionToAccessURLs urls: Set<URL>!, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext!) async -> (Set<URL>?, Date?) {
        return (urls, nil)
    }

    private func webExtensionController(_ controller: WKWebExtensionController!, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>!, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext!) async -> (Set<WKWebExtension.MatchPattern>?, Date?) {
        return (matchPatterns, nil)
    }

    private func webExtensionController(_ controller: WKWebExtensionController!, presentPopupFor action: WKWebExtension.Action!, for context: WKWebExtensionContext!) async throws {
        guard let button = buttonForContext(context) else {
            return
        }

        guard action.presentsPopup,
              let popupPopover = action.popupPopover,
              let popupWebView = action.popupWebView
        else {
            return
        }

        popupWebView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        popupPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)

        popupWebView.reload()
    }

    func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, toApplicationWithIdentifier applicationIdentifier: String?, for extensionContext: WKWebExtensionContext, replyHandler: ((Any?, (any Error)?) -> Void)) {
        // Uncomment when sending messages is implemented in the NativeMessagingHandler
//        try nativeMessagingHandler.webExtensionController(controller,
//                                                          sendMessage: message,
//                                                          to: applicationIdentifier,
//                                                          for: extensionContext)
        replyHandler(nil, nil)
    }

    private func webExtensionController(_ controller: WKWebExtensionController!, connectUsingMessagePort port: WKWebExtension.MessagePort!, for extensionContext: WKWebExtensionContext!) async throws {
        try await nativeMessagingHandler.webExtensionController(controller, connectUsingMessagePort: port, for: extensionContext)
    }

}

@available(macOS 15.4, *)
extension WebExtensionManager: WebExtensionInternalSiteHandlerDataSource {

    func webExtensionContextForUrl(_ url: URL) -> WKWebExtensionContext? {
        guard let context = contexts.first(where: {
            return url.absoluteString.hasPrefix($0.baseURL.absoluteString)
        }) else {
            assertionFailure("No context for \(url)")
            return nil
        }

        return context
    }

}

#endif
