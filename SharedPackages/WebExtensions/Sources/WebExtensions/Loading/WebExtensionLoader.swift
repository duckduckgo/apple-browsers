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

@available(macOS 15.4, iOS 18.4, *)
public protocol WebExtensionLoading: AnyObject {
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

    public init(storageProvider: WebExtensionStorageProviding) {
        self.storageProvider = storageProvider
    }

    @MainActor
    public func loadWebExtension(identifier: String, into controller: WKWebExtensionController) async throws -> WebExtensionLoadResult {
        guard let extensionURL = storageProvider.resolveInstalledExtension(identifier: identifier) else {
            throw WebExtensionLoaderError.extensionNotFound(identifier: identifier)
        }

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionURL)

        let context = makeContext(for: webExtension, identifier: identifier)
        try controller.load(context)

        return WebExtensionLoadResult(context: context, identifier: identifier)
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
}
