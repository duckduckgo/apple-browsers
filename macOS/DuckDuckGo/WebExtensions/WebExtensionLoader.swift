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

#if WEB_EXTENSIONS_ENABLED

import CryptoKit

@available(macOS 15.4, *)
protocol WebExtensionLoading: AnyObject {
    @discardableResult
    func loadWebExtension(path: String, into controller: WKWebExtensionController) async throws -> WKWebExtensionContext
    func loadWebExtensions(from paths: [String], into controller: WKWebExtensionController) async -> [Result<WKWebExtensionContext, Error>]
    func unloadExtension(at path: String, from controller: WKWebExtensionController) throws
}

@available(macOS 15.4, *)
final class WebExtensionLoader: WebExtensionLoading {

    enum WebExtensionLoaderError: Error {
        case failedToCreateURLFromPath(path: String)
        case failedToFindContextForPath(path: String)
    }

    func loadWebExtension(path: String, into controller: WKWebExtensionController) async throws -> WKWebExtensionContext {
        guard let extensionURL = URL(string: path) else {
            assertionFailure("Failed to create URL from path: \(path)")
            throw WebExtensionLoaderError.failedToCreateURLFromPath(path: path)
        }

        let webExtension = try await WKWebExtension(resourceBaseURL: extensionURL)
        let context = makeContext(for: webExtension, at: path)
        try await controller.load(context)
        return context
    }

    func loadWebExtensions(from paths: [String], into controller: WKWebExtensionController) async -> [Result<WKWebExtensionContext, Error>] {
        var result = [Result<WKWebExtensionContext, Error>]()
        for path in paths {
            do {
                let context = try await loadWebExtension(path: path, into: controller)
                result.append(.success(context))
            } catch {
                result.append(.failure(error))
            }
        }

        return result
    }

    func unloadExtension(at path: String, from controller: WKWebExtensionController) throws {
        let context = controller.extensionContexts.first {
            $0.uniqueIdentifier == identifierHash(forPath: path)
        }

        guard let context else {
            throw WebExtensionLoaderError.failedToFindContextForPath(path: path)
        }

        try controller.unload(context)
    }

    private func identifierHash(forPath path: String) -> String {
        let identifier = Data(path.utf8)
        let hash = SHA256.hash(data: identifier)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

        return hashString
    }

    private func makeContext(for webExtension: WKWebExtension, at path: String) -> WKWebExtensionContext {
        let context = WKWebExtensionContext(for: webExtension)

        context.uniqueIdentifier = identifierHash(forPath: path)

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

#endif
