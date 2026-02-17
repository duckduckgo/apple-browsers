//
//  WebExtensionManager+NativeMessaging.swift
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

// MARK: - Message Handler Registration

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionManager {

    /// Register a message handler for a specific extension
    public func registerMessageHandler(_ handler: WebExtensionMessageHandler, for extensionIdentifier: String) {
        messageRouter.registerHandler(handler, for: extensionIdentifier)
    }

    func registerHandlersForExtension(identifier: String, context: WKWebExtensionContext) {
        guard let handlerProvider = handlerProvider else {
            Logger.webExtensions.debug("⚠️ No handler provider configured")
            return
        }

        let handlers = handlerProvider.makeHandlers(for: context)

        for handler in handlers {
            messageRouter.registerHandler(handler, for: identifier)
        }

        Logger.webExtensions.debug("✅ Registered \(handlers.count) handler(s) for extension '\(identifier)'")
    }

    func unregisterHandlers(for identifier: String) {
        messageRouter.unregisterHandlers(for: identifier)
    }
}

// MARK: - WebExtensionLoadingDelegate

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionManager: WebExtensionLoadingDelegate {

    public func webExtensionLoader(_ loader: WebExtensionLoading,
                                   willLoad context: WKWebExtensionContext,
                                   identifier: String) {
        registerHandlersForExtension(identifier: identifier, context: context)
    }
}

// MARK: - Native Messaging

@available(macOS 15.4, iOS 18.4, *)
extension WebExtensionManager {

    enum MessageParsingError: Error, LocalizedError {
        case invalidMessageFormat
        case missingFeatureName
        case missingMethod

        var errorDescription: String? {
            switch self {
            case .invalidMessageFormat:
                return "Message is not a valid dictionary"
            case .missingFeatureName:
                return "Message is missing required 'featureName' field"
            case .missingMethod:
                return "Message is missing required 'method' field"
            }
        }
    }

    func parseMessage(_ message: Any, extensionContext: WKWebExtensionContext) throws -> WebExtensionMessage {
        guard let messageDict = message as? [String: Any] else {
            throw MessageParsingError.invalidMessageFormat
        }

        guard let featureName = messageDict["featureName"] as? String else {
            throw MessageParsingError.missingFeatureName
        }

        guard let method = messageDict["method"] as? String else {
            throw MessageParsingError.missingMethod
        }

        let id = messageDict["id"] as? String
        let params = messageDict["params"] as? [String: Any]
        let context = messageDict["context"] as? String

        return WebExtensionMessage(
            featureName: featureName,
            method: method,
            id: id,
            params: params,
            context: context,
            extensionIdentifier: extensionContext.uniqueIdentifier

        )
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       sendMessage message: Any,
                                       toApplicationWithIdentifier applicationIdentifier: String?,
                                       for extensionContext: WKWebExtensionContext) async throws -> Any? {
        let displayName = await extensionContext.webExtension.displayName ?? "(unknown)"
        Logger.webExtensions.debug("📬 Received native message from extension: \(displayName)")

//        Logger.webExtensions.debug("🔎 Full message received: \(String(describing: message))")

        let extensionMessage: WebExtensionMessage
        do {
            extensionMessage = try parseMessage(message, extensionContext: extensionContext)
        } catch {
            Logger.webExtensions.error("❌ Message parsing failed: \(error.localizedDescription)")
            return ["error": error.localizedDescription]
        }

        let result = await messageRouter.routeMessage(extensionMessage)

        switch result {
        case .success(let response):
            return enrichResponse(response, with: extensionMessage)
        case .failure(let error):
            Logger.webExtensions.error("❌ Message handling failed: \(error.localizedDescription)")
            return nil
        case .noHandler:
            Logger.webExtensions.error("❌ No handler registered for feature: \(extensionMessage.featureName)")
            return nil
        }
    }

    private func enrichResponse(_ response: Any?, with message: WebExtensionMessage) -> Any? {
        var wrapper: [String: Any] = ["featureName": message.featureName]

        if let response {
            wrapper["result"] = response
        }

        if let id = message.id {
            wrapper["id"] = id
        }

        if let context = message.context {
            wrapper["context"] = context
        }

        return wrapper
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       connectUsing port: WKWebExtension.MessagePort,
                                       for extensionContext: WKWebExtensionContext) async throws {
        let displayName = await extensionContext.webExtension.displayName ?? "(unknown)"
        Logger.webExtensions.debug("🔗 Connected to extension: \(displayName)")

        // Not supported
    }
}
