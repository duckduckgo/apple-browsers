//
//  WebExtensionManager.swift
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

import CryptoKit
import Foundation
import WebKit

/// Manages web extensions including installation, loading, and lifecycle.
/// Platform-specific behavior is delegated to the windowTabProvider and lifecycleDelegate.
@available(macOS 15.4, *)
open class WebExtensionManager: NSObject, WebExtensionManaging {

    // MARK: - Dependencies

    public let installationStore: WebExtensionPathsStoring
    public let loader: WebExtensionLoading
    public let controller: WKWebExtensionController
    public var eventsListener: WebExtensionEventsListening

    /// Platform-specific window/tab operations.
    public let windowTabProvider: WebExtensionWindowTabProviding

    /// Platform-specific lifecycle hooks.
    public weak var lifecycleDelegate: WebExtensionLifecycleDelegate?

    /// Optional internal site handler for platform-specific URL handling.
    public var internalSiteHandler: (any WebExtensionInternalSiteHandling)?

    // MARK: - AsyncStream

    private var continuation: AsyncStream<Void>.Continuation?
    public private(set) lazy var extensionUpdates = AsyncStream<Void> { [weak self] continuation in
        self?.continuation = continuation
    }

    // MARK: - Init

    @MainActor
    public init(configuration: WebExtensionConfigurationProviding,
                windowTabProvider: WebExtensionWindowTabProviding,
                installationStore: WebExtensionPathsStoring = WebExtensionPathsStore(),
                loader: WebExtensionLoading = WebExtensionLoader(),
                eventsListener: WebExtensionEventsListening = WebExtensionEventsListener()) {
        let controllerConfiguration = WKWebExtensionController.Configuration.default()
        controllerConfiguration.webViewConfiguration.applicationNameForUserAgent = configuration.applicationNameForUserAgent
        self.controller = WKWebExtensionController(configuration: controllerConfiguration)

        self.windowTabProvider = windowTabProvider
        self.installationStore = installationStore
        self.loader = loader
        self.eventsListener = eventsListener

        super.init()

        controller.delegate = self
    }

    // MARK: - Computed Properties

    public var contexts: [WKWebExtensionContext] {
        Array(controller.extensionContexts)
    }

    public var webExtensionPaths: [String] {
        installationStore.paths
    }

    public var hasInstalledExtensions: Bool {
        !installationStore.paths.isEmpty
    }

    public var loadedExtensions: Set<WKWebExtensionContext> {
        controller.extensionContexts
    }

    // MARK: - Install/Uninstall

    public func installExtension(path: String) async {
        installationStore.add(path)

        do {
            _ = try await loader.loadWebExtension(path: path, into: controller)
        } catch {
            assertionFailure("Failed to load web extension \(path): \(error)")
        }

        notifyUpdate()
    }

    public func uninstallExtension(path: String) throws {
        installationStore.remove(path)

        do {
            try loader.unloadExtension(at: path, from: controller)
        } catch {
            throw WebExtensionError.failedToUnloadWebExtension(error)
        }

        notifyUpdate()
    }

    @discardableResult
    public func uninstallAllExtensions() -> [Result<Void, Error>] {
        installationStore.paths.map { path in
            do {
                try uninstallExtension(path: path)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
    }

    // MARK: - Loading

    @MainActor
    public func loadInstalledExtensions() async {
        eventsListener.controller = controller

        lifecycleDelegate?.webExtensionManagerWillLoadExtensions(self)

        let results = await loader.loadWebExtensions(from: installationStore.paths, into: controller)

        for result in results {
            switch result {
            case .success:
                continue
            case .failure(let failure):
                assertionFailure("Failed to load web extension: \(failure)")
            }
        }

        notifyUpdate()
    }

    // MARK: - Lookups

    public func extensionName(from path: String) -> String? {
        URL(string: path)?.lastPathComponent
    }

    public func extensionContext(for url: URL) -> WKWebExtensionContext? {
        contexts.first { url.absoluteString.hasPrefix($0.baseURL.absoluteString) }
    }

    public func context(forPath path: String) -> WKWebExtensionContext? {
        let hash = identifierHash(forPath: path)
        return contexts.first { $0.uniqueIdentifier == hash }
    }

    // MARK: - Helpers

    public func identifierHash(forPath path: String) -> String {
        let identifier = Data(path.utf8)
        let hash = SHA256.hash(data: identifier)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func notifyUpdate() {
        continuation?.yield()
        lifecycleDelegate?.webExtensionManagerDidUpdateExtensions(self)
    }
}

// MARK: - WKWebExtensionControllerDelegate

@available(macOS 15.4, *)
extension WebExtensionManager: WKWebExtensionControllerDelegate {

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        windowTabProvider.openWindows(for: extensionContext)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        windowTabProvider.focusedWindow(for: extensionContext)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
                                       for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionWindow)? {
        try await windowTabProvider.openNewWindow(using: configuration, for: extensionContext)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                       for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        try await windowTabProvider.openNewTab(using: configuration, for: extensionContext)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       openOptionsPageFor extensionContext: WKWebExtensionContext) async throws {
        throw WebExtensionControllerDelegateError.notSupported
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       presentActionPopup action: WKWebExtension.Action,
                                       for extensionContext: WKWebExtensionContext) async throws {
        try await windowTabProvider.presentPopup(action, for: extensionContext)
    }

    // MARK: - Permissions (sensible defaults)

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                       in tab: (any WKWebExtensionTab)?,
                                       for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.Permission>, Date?) {
        (permissions, nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       promptForPermissionToAccess urls: Set<URL>,
                                       in tab: (any WKWebExtensionTab)?,
                                       for extensionContext: WKWebExtensionContext) async -> (Set<URL>, Date?) {
        (urls, nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                       in tab: (any WKWebExtensionTab)?,
                                       for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        (matchPatterns, nil)
    }
}

// MARK: - WebExtensionInternalSiteHandlerDataSource

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionManager: WebExtensionInternalSiteHandlerDataSource {

    public func webExtensionContext(for url: URL) -> WKWebExtensionContext? {
        extensionContext(for: url)
    }
}

// MARK: - Errors

@available(macOS 15.4, *)
public enum WebExtensionControllerDelegateError: Error {
    case notSupported
}
