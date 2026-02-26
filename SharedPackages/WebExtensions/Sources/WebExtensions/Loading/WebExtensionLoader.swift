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
}

@available(macOS 15.4, iOS 18.4, *)
public final class WebExtensionLoader: WebExtensionLoading {

    enum WebExtensionLoaderError: Error {
        case extensionNotFound(identifier: String)
        case failedToFindContextForIdentifier(identifier: String)
    }

    private let storageProvider: WebExtensionStorageProviding
    private let isInspectable: Bool
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

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionURL)

        let context = makeContext(for: webExtension, identifier: identifier)

        // Notify delegate before loading to allow handler registration
        delegate?.webExtensionLoader(self, willLoad: context, identifier: identifier)

        try controller.load(context)

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
            do {
                let loadResult = try await loadWebExtension(identifier: identifier, into: controller)
                result.append(.success(loadResult))
            } catch {
                result.append(.failure(error))
            }
        }

        return result
    }

    public func unloadExtension(identifier: String, from controller: WKWebExtensionController) throws {
        let context = controller.extensionContexts.first {
            $0.uniqueIdentifier == identifier
        }

        guard let context else {
            throw WebExtensionLoaderError.failedToFindContextForIdentifier(identifier: identifier)
        }

        try controller.unload(context)
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
        return context
    }
}
