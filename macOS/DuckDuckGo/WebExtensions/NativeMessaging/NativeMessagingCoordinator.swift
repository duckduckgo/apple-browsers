//
//  NativeMessagingCoordinator.swift
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
import LocalAuthentication

@available(macOS 15.4, *)
final class NativeMessagingCoordinator {

    // Context to handler mappings
    private var contextHandlers: [WKWebExtensionContext: NativeMessagingHandling] = [:]

    // MARK: - Handler Registration

    func registerHandler(_ handler: NativeMessagingHandling, for context: WKWebExtensionContext) {
        contextHandlers[context] = handler
    }

    func unregisterHandler(for context: WKWebExtensionContext) {
        contextHandlers.removeValue(forKey: context)
    }

    func createHandlerIfNeeded(for extensionIdentifier: WebExtensionIdentifier?, context: WKWebExtensionContext) {
        guard let extensionIdentifier = extensionIdentifier,
              let handler = NativeMessagingHandlerFactory.makeHandler(for: extensionIdentifier) else {
            return
        }
        registerHandler(handler, for: context)
    }

    private func handler(for context: WKWebExtensionContext) -> NativeMessagingHandling? {
        return contextHandlers[context]
    }

    func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, to applicationIdentifier: String?, for extensionContext: WKWebExtensionContext) async throws -> Any? {
        // Route to the registered handler for this context
        if let handler = handler(for: extensionContext) {
            return try await handler.handleMessage(message, to: applicationIdentifier, for: extensionContext)
        }

        // No handler registered for this context
        throw NSError(domain: "NativeMessagingCoordinator", code: 1, userInfo: [NSLocalizedDescriptionKey: "No native messaging handler registered for this extension"])
    }

    func webExtensionController(_ controller: WKWebExtensionController, connectUsingMessagePort port: WKWebExtension.MessagePort, for extensionContext: WKWebExtensionContext) throws {
        // Route to the registered handler for this context
        if let handler = handler(for: extensionContext) {
            try handler.handleConnection(using: port, for: extensionContext)
            return
        }

        // No handler registered for this context
        throw NSError(domain: "NativeMessagingCoordinator", code: 2, userInfo: [NSLocalizedDescriptionKey: "No native messaging handler registered for this extension"])
    }
}
