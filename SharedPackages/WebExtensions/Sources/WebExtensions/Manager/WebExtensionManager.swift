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

import Foundation
import os.log
import WebKit

/// Manages web extensions including installation, loading, and lifecycle.
/// Platform-specific behavior is delegated to the windowTabProvider and lifecycleDelegate.
@available(macOS 15.4, iOS 18.4, *)
open class WebExtensionManager: NSObject, WebExtensionManaging {

    // MARK: - Dependencies

    public let installationStore: InstalledWebExtensionStoring
    public let storageProvider: WebExtensionStorageProviding
    public let loader: WebExtensionLoading
    public let controller: WKWebExtensionController
    public var eventsListener: WebExtensionEventsListening

    /// Platform-specific window/tab operations.
    public let windowTabProvider: WebExtensionWindowTabProviding

    /// Platform-specific lifecycle hooks.
    public private(set) weak var lifecycleDelegate: WebExtensionLifecycleDelegate?

    /// Optional internal site handler for platform-specific URL handling.
    public private(set) var internalSiteHandler: (any WebExtensionInternalSiteHandling)?

    /// Message router for handling native messages from extensions.
    public let messageRouter: WebExtensionMessageRouting

    /// Provider for creating extension-specific message handlers.
    public private(set) var handlerProvider: WebExtensionHandlerProviding?

    /// Pixel firing for analytics.
    let pixelFiring: WebExtensionPixelFiring

    // MARK: - AsyncStream

    private var continuation: AsyncStream<Void>.Continuation?
    public private(set) lazy var extensionUpdates = AsyncStream<Void> { [weak self] continuation in
        self?.continuation = continuation
    }

    // MARK: - Init

    @MainActor
    public init(configuration: WebExtensionConfigurationProviding,
                windowTabProvider: WebExtensionWindowTabProviding,
                storageProvider: WebExtensionStorageProviding,
                installationStore: InstalledWebExtensionStoring = InstalledWebExtensionStore(),
                loader: WebExtensionLoading? = nil,
                eventsListener: WebExtensionEventsListening = WebExtensionEventsListener(),
                lifecycleDelegate: WebExtensionLifecycleDelegate? = nil,
                internalSiteHandler: (any WebExtensionInternalSiteHandling)? = nil,
                pixelFiring: WebExtensionPixelFiring = NoOpWebExtensionPixelFiring(),
                messageRouter: WebExtensionMessageRouting? = nil,
                handlerProvider: WebExtensionHandlerProviding? = nil) {
        let controllerConfiguration = WKWebExtensionController.Configuration.default()
        controllerConfiguration.webViewConfiguration.applicationNameForUserAgent = configuration.applicationNameForUserAgent
        self.controller = WKWebExtensionController(configuration: controllerConfiguration)

        self.windowTabProvider = windowTabProvider
        self.storageProvider = storageProvider
        self.installationStore = installationStore
        self.loader = loader ?? WebExtensionLoader(storageProvider: storageProvider, isInspectable: configuration.isInspectable)
        self.eventsListener = eventsListener
        self.lifecycleDelegate = lifecycleDelegate
        self.internalSiteHandler = internalSiteHandler
        self.pixelFiring = pixelFiring
        self.messageRouter = messageRouter ?? WebExtensionMessageRouter()
        self.handlerProvider = handlerProvider

        super.init()

        controller.delegate = self
        self.loader.delegate = self
    }

    // MARK: - Computed Properties

    public var contexts: [WKWebExtensionContext] {
        Array(controller.extensionContexts)
    }

    public var webExtensionIdentifiers: [String] {
        installationStore.installedExtensions.map(\.uniqueIdentifier)
    }

    public var loadedExtensions: Set<WKWebExtensionContext> {
        controller.extensionContexts
    }

    public var extensionsDirectory: URL {
        storageProvider.extensionsDirectory
    }

    /// Whether the embedded autoconsent web extension is loaded and active.
    public var isAutoconsentExtensionLoaded: Bool {
        contexts.contains { $0.duckDuckGoWebExtensionType == .embedded }
    }

    // MARK: - Install/Uninstall

    public func installExtension(from sourceURL: URL) async throws {
        Logger.webExtensions.debug("🔄 Installing extension from: \(sourceURL.path)")

        let metadata = try await WKWebExtension.metadata(from: sourceURL)
        let identifier = UUID().uuidString

        if metadata.requiresExtraction {
            _ = try storageProvider.extractExtension(from: sourceURL, identifier: identifier)
        } else {
            _ = try storageProvider.copyExtension(from: sourceURL, identifier: identifier)
        }

        Logger.webExtensions.debug("🔄 Extension stored with identifier: \(identifier)")

        do {
            let loadResult = try await loader.loadWebExtension(identifier: identifier, into: controller)

            let installedExtension = InstalledWebExtension(
                uniqueIdentifier: identifier,
                filename: loadResult.filename,
                name: loadResult.displayName,
                version: loadResult.version
            )

            installationStore.add(installedExtension)

            Logger.webExtensions.info("✅ Successfully installed extension \(installedExtension.filename) v\(installedExtension.version ?? "unknown") (\(identifier))")
            pixelFiring.fire(.installed)
        } catch {
            Logger.webExtensions.error("❌ Failed to load extension '\(identifier)': \(error.localizedDescription)")
            unregisterHandlers(for: identifier)
            try? storageProvider.removeExtension(identifier: identifier)
            pixelFiring.fire(.installError(error: error))
            throw WebExtensionError.failedToLoadWebExtension(error)
        }

        notifyUpdate()
    }

    public func uninstallExtension(identifier: String) throws {
        Logger.webExtensions.debug("🔄 Uninstalling extension '\(identifier)'")

        installationStore.remove(uniqueIdentifier: identifier)

        unregisterHandlers(for: identifier)

        do {
            try loader.unloadExtension(identifier: identifier, from: controller)
            Logger.webExtensions.debug("✅ Unloaded extension '\(identifier)' from memory")
        } catch {
            Logger.webExtensions.debug("⚠️ Extension '\(identifier)' was not loaded in memory: \(error.localizedDescription)")
        }

        do {
            try storageProvider.removeExtension(identifier: identifier)
        } catch {
            Logger.webExtensions.error("❌ Failed to remove extension files for '\(identifier)': \(error.localizedDescription)")
            pixelFiring.fire(.uninstallError(error: error))
            throw WebExtensionError.failedToRemoveWebExtension(error)
        }

        Logger.webExtensions.info("✅ Successfully uninstalled extension '\(identifier)'")
        pixelFiring.fire(.uninstalled)
        notifyUpdate()
    }

    @discardableResult
    public func uninstallAllExtensions() -> [Result<Void, Error>] {
        let identifiers = installationStore.installedExtensions.map(\.uniqueIdentifier)
        Logger.webExtensions.debug("🔄 Uninstalling all extensions (count: \(identifiers.count))")

        let results: [Result<Void, Error>] = identifiers.map { identifier in
            do {
                try uninstallExtension(identifier: identifier)
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        let successCount = results.filter { if case .success = $0 { return true } else { return false } }.count
        let failureCount = results.count - successCount
        if failureCount > 0 {
            Logger.webExtensions.error("❌ Uninstall all completed with errors: \(successCount) succeeded, \(failureCount) failed")
            if let firstError = results.compactMap({ result -> Error? in
                if case .failure(let error) = result { return error }
                return nil
            }).first {
                pixelFiring.fire(.uninstallAllError(error: firstError))
            }
        } else {
            Logger.webExtensions.info("✅ Uninstall all completed: \(successCount) extensions removed")
            pixelFiring.fire(.uninstalledAll)
        }

        storageProvider.cleanupOrphanedExtensions(keeping: [])

        return results
    }

    @MainActor
    public func unloadAllExtensions() {
        let contexts = controller.extensionContexts
        Logger.webExtensions.debug("🔄 Unloading all extensions from memory (count: \(contexts.count))")

        var successCount = 0
        var failureCount = 0

        for context in contexts {
            let identifier = context.uniqueIdentifier
            do {
                try controller.unload(context)
                unregisterHandlers(for: identifier)
                successCount += 1
            } catch {
                Logger.webExtensions.error("❌ Failed to unload extension '\(identifier)': \(error.localizedDescription)")
                failureCount += 1
            }
        }

        if failureCount > 0 {
            Logger.webExtensions.warning("⚠️ Unload all completed with \(failureCount) error(s): \(successCount) succeeded, \(failureCount) failed")
        } else {
            Logger.webExtensions.debug("✅ Successfully unloaded \(successCount) extension(s) from memory")
        }
    }

    @MainActor
    public func reloadExtension(identifier: String) async throws {
        Logger.webExtensions.debug("🔄 Reloading extension '\(identifier)'")

        try loader.unloadExtension(identifier: identifier, from: controller)
        unregisterHandlers(for: identifier)

        _ = try await loader.loadWebExtension(identifier: identifier, into: controller)

        Logger.webExtensions.info("✅ Reloaded extension '\(identifier)'")
        notifyUpdate()
    }

    // MARK: - Loading

    @MainActor
    public func loadInstalledExtensions() async {
        eventsListener.controller = controller

        lifecycleDelegate?.webExtensionManagerWillLoadExtensions(self)

        let extensions = installationStore.installedExtensions
        Logger.webExtensions.debug("🔄 Loading installed extensions (count: \(extensions.count))")

        let identifiers = extensions.map(\.uniqueIdentifier)
        let results = await loader.loadWebExtensions(identifiers: identifiers, into: controller)

        var failedIdentifiers: [String] = []
        var successCount = 0
        for (installedExtension, result) in zip(extensions, results) {
            switch result {
            case .success:
                Logger.webExtensions.debug("✅ Loaded extension `\(installedExtension.name ?? "")` v\(installedExtension.version ?? "unknown") | \(installedExtension.filename) | \(installedExtension.uniqueIdentifier)")
                successCount += 1
            case .failure(let failure):
                Logger.webExtensions.error("❌ Failed to load web extension \(installedExtension.filename) (\(installedExtension.uniqueIdentifier)): \(failure.localizedDescription)")
                failedIdentifiers.append(installedExtension.uniqueIdentifier)
            }
        }

        for identifier in failedIdentifiers {
            do {
                try uninstallExtension(identifier: identifier)
            } catch {
                Logger.webExtensions.error("❌ Failed to uninstall broken extension '\(identifier)': \(error.localizedDescription)")
            }
        }

        if failedIdentifiers.isEmpty {
            Logger.webExtensions.info("✅ Extension loading completed: \(successCount) loaded")
            if successCount > 0 {
                pixelFiring.fire(.loaded)
            }
        } else {
            Logger.webExtensions.error("❌ Extension loading completed with errors: \(successCount) loaded, \(failedIdentifiers.count) failed and removed")
            if let firstError = results.compactMap({ result -> Error? in
                if case .failure(let error) = result { return error }
                return nil
            }).first {
                pixelFiring.fire(.loadError(error: firstError))
            }
        }

        let knownIdentifiers = Set(installationStore.installedExtensions.map(\.uniqueIdentifier))
        storageProvider.cleanupOrphanedExtensions(keeping: knownIdentifiers)

        notifyUpdate()
    }

    // MARK: - Lookups

    public func extensionName(for identifier: String) -> String? {
        contexts.first { $0.uniqueIdentifier == identifier }?.webExtension.displayName
    }

    public func extensionVersion(for identifier: String) -> String? {
        installationStore.installedExtension(withUniqueIdentifier: identifier)?.version
    }

    public func extensionContext(for url: URL) -> WKWebExtensionContext? {
        contexts.first { url.absoluteString.hasPrefix($0.baseURL.absoluteString) }
    }

    public func context(for identifier: String) -> WKWebExtensionContext? {
        contexts.first { $0.uniqueIdentifier == identifier }
    }

    func notifyUpdate() {
        continuation?.yield()
        lifecycleDelegate?.webExtensionManagerDidUpdateExtensions(self)
    }
}

// MARK: - WKWebExtensionControllerDelegate

@available(macOS 15.4, iOS 18.4, *)
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

@available(macOS 15.4, iOS 18.4, *)
public enum WebExtensionControllerDelegateError: Error {
    case notSupported
}
