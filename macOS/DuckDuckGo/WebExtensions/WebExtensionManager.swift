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

import BrowserServicesKit
import Common
import CryptoKit
import Foundation
import OSLog
import WebKit

protocol WebExtensionManaging {

    typealias WebExtensionIdentifier = String

    @available(macOS 15.4, *)
    var hasInstalledExtensions: Bool { get }

    @available(macOS 15.4, *)
    var loadedExtensions: Set<WKWebExtensionContext> { get }

    @available(macOS 15.4, *)
    @MainActor
    func loadInstalledExtensions() async

    // Adding and removing extensions
    @available(macOS 15.4, *)
    var webExtensionPaths: [String] { get }

    @available(macOS 15.4, *)
    func installExtension(path: String) async

    @available(macOS 15.4, *)
    func uninstallExtension(path: String) throws

    @available(macOS 15.4, *)
    @discardableResult
    func uninstallAllExtensions() -> [Result<Void, Error>]

    // Provides the extension name for the extension resource base path
    @available(macOS 15.4, *)
    func extensionName(from path: String) -> String?

    @available(macOS 15.4, *)
    func extensionContext(for url: URL) -> WKWebExtensionContext?

    // Controller for tabs
    @available(macOS 15.4, *)
    var controller: WKWebExtensionController { get }

    // Listening of events
    @available(macOS 15.4, *)
    var eventsListener: WebExtensionEventsListening { get }

    @available(macOS 15.4, *)
    var extensionUpdates: AsyncStream<Void> { get }

    @available(macOS 15.4, *)
    func context(forPath path: String) -> WKWebExtensionContext?

    @available(macOS 15.4, *)
    func toolbarButton(for context: WKWebExtensionContext) -> MouseOverButton
}

// Manages the initialization and ownership of key components: web extensions, contexts, and the controller
@available(macOS 15.4, *)
final class WebExtensionManager: NSObject, WebExtensionManaging {

    enum WebExtensionError: Error {
        case failedToUnloadWebExtension(_ error: Error)
    }

    private var continuation: AsyncStream<Void>.Continuation?
    private(set) lazy var extensionUpdates = AsyncStream<Void> { [weak self] continuation in
        self?.continuation = continuation
    }

    @MainActor
    init(installationStore: WebExtensionPathsStoring = WebExtensionPathsStore(),
         webExtensionLoader: WebExtensionLoading = WebExtensionLoader()) {

        self.installationStore = installationStore
        self.loader = webExtensionLoader

        let controllerConfiguration = WKWebExtensionController.Configuration.default()
        controllerConfiguration.webViewConfiguration.applicationNameForUserAgent = UserAgent.brandedDefaultSuffix
        controller = WKWebExtensionController(configuration: controllerConfiguration)

        super.init()

        controller.delegate = self
        internalSiteHandler.dataSource = self
    }

    static var areExtensionsEnabled: Bool {
        NSApp.delegateTyped.webExtensionManager != nil
    }

    // Registers extension installation paths for persistence
    var installationStore: WebExtensionPathsStoring

    // Loads web extensions after selection or application start
    var loader: WebExtensionLoading

    // Extension contexts
    var contexts: [WKWebExtensionContext] {
        Array(controller.extensionContexts)
    }

    // Controller manages a set of loaded extension contexts
    let controller: WKWebExtensionController

    // Events listening
    var eventsListener: WebExtensionEventsListening = WebExtensionEventsListener()

    // Handles native messaging
    let nativeMessagingCoordinator = NativeMessagingCoordinator()

    // Handles internal sites of web extenions
    let internalSiteHandler = WebExtensionInternalSiteHandler()

    // MARK: - Adding and removing extensions
    var webExtensionPaths: [String] {
        installationStore.paths
    }

    var hasInstalledExtensions: Bool {
        installationStore.paths.count > 0
    }

    var loadedExtensions: Set<WKWebExtensionContext> {
        controller.extensionContexts
    }

    func installExtension(path: String) async {
        installationStore.add(path)

        do {
            let loadResult = try await loader.loadWebExtension(path: path, into: controller)

            // Create and register handler if extension is known
            nativeMessagingCoordinator.createHandlerIfNeeded(for: loadResult.extensionIdentifier, context: loadResult.context)
            if let extensionIdentifier = loadResult.extensionIdentifier?.rawValue {
                Logger.webExtensions.info("[WebExtensionManager] Created native messaging handler for extension: \(extensionIdentifier, privacy: .public)")
            }
        } catch {
            // This is temporary.  The actual handling of this error should be done outside of this manager.
            assertionFailure("Failed to load web extension \(path): \(error)")
        }

        continuation?.yield()
    }

    @discardableResult
    func uninstallAllExtensions() -> [Result<Void, Error>] {
        installationStore.paths.map { path in
            do {
                try uninstallExtension(path: path)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
    }

    func uninstallExtension(path: String) throws {
        installationStore.remove(path)

        // Find the context to unregister from coordinator before unloading
        let identifierHash = identifierHash(forPath: path)
        if let context = controller.extensionContexts.first(where: { $0.uniqueIdentifier == identifierHash }) {
            nativeMessagingCoordinator.unregisterHandler(for: context)
            Logger.webExtensions.info("[WebExtensionManager] Unregistered native messaging handler for extension")
        }

        do {
            try loader.unloadExtension(at: path, from: controller)
        } catch {
            throw WebExtensionError.failedToUnloadWebExtension(error)
        }

        continuation?.yield()
    }

    func extensionName(from path: String) -> String? {
        if let extensionURL = URL(string: path) {
            return extensionURL.lastPathComponent
        }
        return nil
    }

    private func identifierHash(forPath path: String) -> String {
        let identifier = Data(path.utf8)
        let hash = SHA256.hash(data: identifier)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return hashString
    }

    // MARK: - Lifecycle

    @MainActor
    func loadInstalledExtensions() async {
        eventsListener.controller = controller

        let results = await loader.loadWebExtensions(from: installationStore.paths, into: controller)
        continuation?.yield()

        for result in results {
            switch result {
            case .success(let loadResult):
                nativeMessagingCoordinator.createHandlerIfNeeded(for: loadResult.extensionIdentifier, context: loadResult.context)
                if let extensionIdentifier = loadResult.extensionIdentifier?.rawValue {
                    Logger.webExtensions.info("[WebExtensionManager] Created native messaging handler for extension: \(extensionIdentifier, privacy: .public)")
                }
            case .failure(let failure):
                // If this is blocking from starting up the app, disable this
                // assertion then go to Debug Menu > Web Extensions > Uninstall all extensions
                assertionFailure("Failed to load web extension: \(failure)")
            }
        }
    }

    // MARK: - UI

    static let buttonSize: CGFloat = 28

    func toolbarButton(for context: WKWebExtensionContext) -> MouseOverButton {
        let image = context.webExtension.icon(for: CGSize(width: Self.buttonSize, height: Self.buttonSize)) ?? NSImage(named: "Web")!
        let button = MouseOverButton(image: image, target: self, action: #selector(WebExtensionManager.toolbarButtonClicked))

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

        guard let mainWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController else {
            assertionFailure("No main window controller")
            return nil
        }

        let button = mainWindowController.mainViewController.navigationBarViewController.menuButtons.arrangedSubviews[index] as? NSButton
        return button
    }

    func extensionContext(for url: URL) -> WKWebExtensionContext? {
        return contexts.first { context in
            url.absoluteString.hasPrefix(context.baseURL.absoluteString)
        }
    }

    func context(forPath path: String) -> WKWebExtensionContext? {
        let identifierHash = identifierHash(forPath: path)
        return contexts.first { $0.uniqueIdentifier == identifierHash }
    }
}

@available(macOS 15.4, *)
@MainActor
extension WebExtensionManager: WKWebExtensionControllerDelegate {

    enum WKWebExtensionControllerDelegateError: Error {
        case notSupported
    }

    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        var windows = Application.appDelegate.windowControllersManager.mainWindowControllers
        if let focusedWindow = Application.appDelegate.windowControllersManager.lastKeyMainWindowController {
            // Ensure focusedWindow is the first item
            windows.removeAll { $0 === focusedWindow }
            windows.insert(focusedWindow, at: 0)
        }
        return windows
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        return Application.appDelegate.windowControllersManager.lastKeyMainWindowController
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration, for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionWindow)? {

        // Extract options
        let tabs = configuration.tabURLs.map { Tab(content: .contentFromURL($0, source: .ui), webViewConfiguration: extensionContext.webViewConfiguration) }
        let burnerMode = BurnerMode(isBurner: configuration.shouldBePrivate)
        let tabCollectionViewModel = TabCollectionViewModel(
            tabCollection: TabCollection(tabs: tabs),
            burnerMode: burnerMode
        )

        // Create new window
        let mainWindow = Application.appDelegate.windowControllersManager.openNewWindow(
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
                let sourceViewModel = Application.appDelegate.windowControllersManager.windowController(for: tab)?
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
        if let tabCollectionViewModel = Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.mainViewController.tabCollectionViewModel,
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

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.Permission>, Date?) {
        return (permissions, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<URL>, Date?) {
        return (urls, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>, in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        return (matchPatterns, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action, for context: WKWebExtensionContext) async throws {

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
    }
/*
    func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, toApplicationWithIdentifier applicationIdentifier: String?, for extensionContext: WKWebExtensionContext) async throws -> Any? {

        try await nativeMessagingCoordinator.webExtensionController(controller,
                                                          sendMessage: message,
                                                          to: applicationIdentifier,
                                                          for: extensionContext)
    }

    func webExtensionController(_ controller: WKWebExtensionController, connectUsing port: WKWebExtension.MessagePort, for extensionContext: WKWebExtensionContext) async throws {

        try nativeMessagingCoordinator.webExtensionController(controller, connectUsingMessagePort: port, for: extensionContext)
    }*/
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
