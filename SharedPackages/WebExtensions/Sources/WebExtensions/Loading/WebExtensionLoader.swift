//
//  WebExtensionLoader.swift
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

import os.log
import WebKit

/// Delegate protocol for receiving notifications about extension loading lifecycle.
@available(macOS 15.4, iOS 18.4, *)
public protocol WebExtensionLoadingDelegate: AnyObject {
    /// Called immediately before an extension context is loaded into the controller.
    /// This is the appropriate time to register message handlers or perform other setup.
    /// - Parameters:
    ///   - loader: The loader about to load the extension
    ///   - context: The extension context that will be loaded
    ///   - identifier: The unique identifier for the extension
    func webExtensionLoader(_ loader: WebExtensionLoading,
                            willLoad context: WKWebExtensionContext,
                            identifier: String)
}

@available(macOS 15.4, iOS 18.4, *)
public protocol WebExtensionLoading: AnyObject {
    var delegate: WebExtensionLoadingDelegate? { get set }

    @discardableResult
    func loadWebExtension(identifier: String, into controller: WKWebExtensionController) async throws -> WebExtensionLoadResult
    func loadWebExtensions(identifiers: [String], into controller: WKWebExtensionController) async -> [Result<WebExtensionLoadResult, Error>]
    func unloadExtension(identifier: String, from controller: WKWebExtensionController) throws

    /// Reloads an already-parsed extension into the controller, reusing the in-memory
    /// `WKWebExtension` to skip disk resolution and manifest parsing.
    func reloadWebExtension(_ webExtension: WKWebExtension, identifier: String, into controller: WKWebExtensionController) async throws
}

@available(macOS 15.4, iOS 18.4, *)
public final class WebExtensionLoader: WebExtensionLoading {

    enum WebExtensionLoaderError: Error {
        case extensionNotFound(identifier: String)
        case failedToFindContextForIdentifier(identifier: String)
    }

    private let storageProvider: WebExtensionStorageProviding
    private let isInspectable: Bool
    private let backgroundPagePatcher = WebExtensionBackgroundPagePatcher()
    /// The API stub script added for each loaded third-party extension, by identifier.
    private var stubScripts: [String: WKUserScript] = [:]
    public weak var delegate: WebExtensionLoadingDelegate?

    public init(storageProvider: WebExtensionStorageProviding, isInspectable: Bool = false) {
        self.storageProvider = storageProvider
        self.isInspectable = isInspectable
    }

    @MainActor
    @discardableResult
    public func loadWebExtension(identifier: String, into controller: WKWebExtensionController) async throws -> WebExtensionLoadResult {
        // Check if extension is already loaded (idempotent operation)
        if let existingContext = controller.extensionContexts.first(where: { $0.uniqueIdentifier == identifier }) {
            Logger.webExtensions.debug("✓ Extension '\(identifier)' already loaded, skipping")

            guard let extensionURL = storageProvider.resolveInstalledExtension(identifier: identifier) else {
                throw WebExtensionLoaderError.extensionNotFound(identifier: identifier)
            }

            return WebExtensionLoadResult(
                identifier: identifier,
                filename: extensionURL.lastPathComponent,
                displayName: existingContext.webExtension.displayName,
                version: existingContext.webExtension.version
            )
        }

        guard let extensionURL = storageProvider.resolveInstalledExtension(identifier: identifier) else {
            throw WebExtensionLoaderError.extensionNotFound(identifier: identifier)
        }

        // Every install path (installExtension(from:), installEmbeddedExtension) funnels into this
        // method, so patching here covers all of them — and does so after the files have landed but
        // before WKWebExtension reads the manifest. The patcher leaves our own extensions alone.
        backgroundPagePatcher.patchIfNeeded(installedExtensionURL: extensionURL)

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionURL)

        let context = makeContext(for: webExtension, identifier: identifier)

        // Notify delegate before loading to allow handler registration
        delegate?.webExtensionLoader(self, willLoad: context, identifier: identifier)

        try loadWithStubScript(context, identifier: identifier, into: controller)

        return WebExtensionLoadResult(
            identifier: identifier,
            filename: extensionURL.lastPathComponent,
            displayName: webExtension.displayName,
            version: webExtension.version
        )
    }

    public func loadWebExtensions(identifiers: [String], into controller: WKWebExtensionController) async -> [Result<WebExtensionLoadResult, Error>] {
        var result = [Result<WebExtensionLoadResult, Error>]()
        for identifier in identifiers {
            // Yield between extensions so the main run loop can service system
            // events, preventing cumulative WKWebExtension file I/O from
            // triggering the iOS watchdog (0x8badf00d).
            await Task.yield()

            do {
                let loadResult = try await loadWebExtension(identifier: identifier, into: controller)
                result.append(.success(loadResult))
            } catch {
                result.append(.failure(error))
            }
        }

        return result
    }

    /// Reloads an already-parsed extension into the controller, reusing the in-memory
    /// `WKWebExtension` to skip disk resolution and manifest parsing. Used when re-loading an
    /// extension that is unchanged on disk (e.g. after clearing browser data).
    @MainActor
    public func reloadWebExtension(_ webExtension: WKWebExtension,
                                   identifier: String,
                                   into controller: WKWebExtensionController) async throws {
        let context = makeContext(for: webExtension, identifier: identifier)

        // Notify delegate before loading to allow handler registration.
        delegate?.webExtensionLoader(self, willLoad: context, identifier: identifier)

        try loadWithStubScript(context, identifier: identifier, into: controller)
    }

    /// Loads `context`, adding the API stub script for its pages first when it is a third-party extension.
    ///
    /// WebKit lacks several Chrome APIs (`notifications`, `offscreen`, `idle`, …), and a top-level
    /// reference to one aborts an extension's background script; the stub script defines them. It is
    /// a user script because one on the controller's configuration reaches every page the extension
    /// owns — background page, popup, options page and, with `forMainFrameOnly: false`, the offscreen
    /// iframe the stubs create — and is exempt from the page's CSP. The controller's user scripts are
    /// shared by every extension, so the script is limited to this extension's base URL: our own
    /// extensions never run it. It must be added before the context loads, because a user script
    /// only reaches documents created after it was added.
    private func loadWithStubScript(_ context: WKWebExtensionContext, identifier: String, into controller: WKWebExtensionController) throws {
        removeStubScript(for: identifier, from: controller)

        if !declaresDuckDuckGoSettings(inManifest: context.webExtension.manifest) {
            addStubScript(for: context, identifier: identifier, to: controller)
        }

        do {
            try controller.load(context)
        } catch {
            removeStubScript(for: identifier, from: controller)
            throw error
        }
    }

    private func addStubScript(for context: WKWebExtensionContext, identifier: String, to controller: WKWebExtensionController) {
        // The base URL is new for every context, so the pattern is too.
        let pattern = context.baseURL.absoluteString + "*"
        guard let script = WebExtensionScopedUserScript.make(source: WebExtensionAPIStubScript.source,
                                                             injectionTime: .atDocumentStart,
                                                             forMainFrameOnly: false,
                                                             includeMatchPatterns: [pattern]) else {
            Logger.webExtensions.error("❌ Could not create the API stub script for \(identifier, privacy: .public)")
            return
        }

        controller.configuration.webViewConfiguration.userContentController.addUserScript(script)
        stubScripts[identifier] = script
    }

    /// Removes the extension's stub script, which would otherwise stay on the shared controller after the extension unloads.
    private func removeStubScript(for identifier: String, from controller: WKWebExtensionController) {
        guard let script = stubScripts.removeValue(forKey: identifier) else { return }
        WebExtensionScopedUserScript.remove(script, from: controller.configuration.webViewConfiguration.userContentController)
    }

    public func unloadExtension(identifier: String, from controller: WKWebExtensionController) throws {
        let context = controller.extensionContexts.first {
            $0.uniqueIdentifier == identifier
        }

        guard let context else {
            throw WebExtensionLoaderError.failedToFindContextForIdentifier(identifier: identifier)
        }

        try controller.unload(context)
        removeStubScript(for: identifier, from: controller)
    }

    private func makeContext(for webExtension: WKWebExtension, identifier: String) -> WKWebExtensionContext {
        let context = WKWebExtensionContext(for: webExtension)

        context.uniqueIdentifier = identifier

        let matchPatterns = webExtension.allRequestedMatchPatterns
        for pattern in matchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern, expirationDate: nil)
        }

        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission, expirationDate: nil)
        }

        context.isInspectable = isInspectable
        context.hasAccessToPrivateData = true
        return context
    }
}
