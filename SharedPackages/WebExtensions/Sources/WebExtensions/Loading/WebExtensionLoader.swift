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
    @MainActor
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

    /// Identifies consent/settings failures separately from bundle and WebKit load failures.
    struct PermissionPreparationError: LocalizedError {
        let underlyingError: Error

        var errorDescription: String? { underlyingError.localizedDescription }
    }

    private let storageProvider: WebExtensionStorageProviding
    private let isInspectable: Bool
    private let backgroundPagePatcher = WebExtensionBackgroundPagePatcher()
    /// Whether the third-party scripts are on the controller, which happens when the first third-party extension loads.
    private var areThirdPartyScriptsInstalled = false
    private let permissionController: WebExtensionPermissionController?
    public weak var delegate: WebExtensionLoadingDelegate?

    public init(storageProvider: WebExtensionStorageProviding,
                isInspectable: Bool = false,
                permissionController: WebExtensionPermissionController? = nil) {
        self.storageProvider = storageProvider
        self.isInspectable = isInspectable
        self.permissionController = permissionController
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
        // before WKWebExtension reads the manifest. The patcher leaves our own extensions alone, and
        // rewrites a copy of the others, leaving the installation untouched.
        let loadableURL = backgroundPagePatcher.loadableExtensionURL(
            for: extensionURL,
            installFolder: storageProvider.extensionsDirectory.appendingPathComponent(identifier))

        let webExtension = try await WKWebExtension(resourceBaseURL: loadableURL)

        let context = try await makeContext(for: webExtension, identifier: identifier)

        // Notify delegate before loading to allow handler registration
        delegate?.webExtensionLoader(self, willLoad: context, identifier: identifier)

        try loadWithThirdPartyScripts(context, identifier: identifier, into: controller)

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
        let context = try await makeContext(for: webExtension, identifier: identifier)

        // Notify delegate before loading to allow handler registration.
        delegate?.webExtensionLoader(self, willLoad: context, identifier: identifier)

        try loadWithThirdPartyScripts(context, identifier: identifier, into: controller)
    }

    /// Scripts for the pages of third-party extensions. Each returns early in our own extensions.
    static let thirdPartyScriptSources = [WebExtensionAPICompatibilityScript.source]

    /// Loads `context`, first adding the third-party scripts when it is the first third-party extension to load.
    ///
    /// They are user scripts because one on the controller's configuration reaches every page the extension
    /// owns — background page, popup, options page and iframes — and is exempt from the page's CSP. Those are
    /// shared by every extension, so each script checks the page's manifest and returns early in our own.
    /// They are only added once a third-party extension loads, so without one, no page ever runs them. They
    /// must be added before the context loads, because a user script only reaches documents created after it.
    @MainActor
    private func loadWithThirdPartyScripts(_ context: WKWebExtensionContext, identifier: String, into controller: WKWebExtensionController) throws {
        if !declaresDuckDuckGoSettings(inManifest: context.webExtension.manifest) {
            installThirdPartyScriptsIfNeeded(on: controller)
            reportDroppedPermissions(of: context.webExtension)
        }

        do {
            try controller.load(context)
        } catch {
            permissionController?.didUnload(identifier)
            throw error
        }
    }

    private func installThirdPartyScriptsIfNeeded(on controller: WKWebExtensionController) {
        guard !areThirdPartyScriptsInstalled else { return }
        let userContentController = controller.configuration.webViewConfiguration.userContentController
        for source in Self.thirdPartyScriptSources {
            userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        areThirdPartyScriptsInstalled = true
    }

    /// WebKit drops manifest permissions it does not implement; the compatibility log lists them.
    private func reportDroppedPermissions(of webExtension: WKWebExtension) {
        let webKitPermissions = Set(webExtension.requestedPermissions.union(webExtension.optionalPermissions).map(\.rawValue))
        let dropped = WebExtensionAPICompatibilityClassifier.droppedPermissions(inManifest: webExtension.manifest,
                                                                                 webKitPermissions: webKitPermissions)
        for permission in dropped {
            WebExtensionAPICompatibilityReporter.shared.report(
                kind: .missing,
                api: WebExtensionAPICompatibilityClassifier.permissionPrefix + permission,
                extensionName: WebExtensionAPICompatibilityLog.sanitizedField(webExtension.displayName),
                version: WebExtensionAPICompatibilityLog.sanitizedField(webExtension.version)
            )
        }
    }

    @MainActor
    public func unloadExtension(identifier: String, from controller: WKWebExtensionController) throws {
        let context = controller.extensionContexts.first {
            $0.uniqueIdentifier == identifier
        }

        guard let context else {
            throw WebExtensionLoaderError.failedToFindContextForIdentifier(identifier: identifier)
        }

        try controller.unload(context)
        permissionController?.didUnload(identifier)
    }

    @MainActor
    private func makeContext(for webExtension: WKWebExtension, identifier: String) async throws -> WKWebExtensionContext {
        let context = WKWebExtensionContext(for: webExtension)

        context.uniqueIdentifier = identifier
        context.isInspectable = isInspectable

        if let permissionController {
            do {
                try await permissionController.prepare(context)
            } catch {
                throw PermissionPreparationError(underlyingError: error)
            }
            return context
        }

        let matchPatterns = webExtension.allRequestedMatchPatterns
        for pattern in matchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern, expirationDate: nil)
        }

        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission, expirationDate: nil)
        }

        context.hasAccessToPrivateData = true
        return context
    }
}
