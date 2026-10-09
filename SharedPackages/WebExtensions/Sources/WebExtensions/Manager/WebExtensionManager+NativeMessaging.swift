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
#if os(macOS)
        // Saved shortcuts are in place before the extension runs.
        MainActor.assumeMainThread {
            commandShortcuts.apply(to: [context])
        }
#endif
        if context.webExtension.duckDuckGoWebExtensionType == .embedded {
            MainActor.assumeIsolated {
                cpmDiagnosticsRecorder?.contextWillLoad(context)
            }
        }
    }
}

// MARK: - Native Messaging

/// This needs to be on the MainActor because accessing extension properties can cause concurrency problems.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
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
        let displayName = extensionContext.webExtension.displayName ?? "(unknown)"
        Logger.webExtensions.debug("📬 Received native message from extension: \(displayName)")

//        Logger.webExtensions.debug("🔎 Full message received: \(String(describing: message))")

        let extensionMessage: WebExtensionMessage
        do {
            extensionMessage = try parseMessage(message, extensionContext: extensionContext)
        } catch {
            guard extensionContext.needsChromeCompatibility else {
                Logger.webExtensions.error("❌ Message parsing failed: \(error.localizedDescription)")
                return ["error": error.localizedDescription]
            }

            // A message we cannot parse comes from a third-party extension that expects its own native host.
            Logger.webExtensions.debug("📬 Message is not ours, so it goes to the native host: \(error.localizedDescription)")
            return try await sendToNativeHost(message,
                                              applicationIdentifier: applicationIdentifier,
                                              for: extensionContext)
        }

        let result = await messageRouter.routeMessage(extensionMessage)

        switch result {
        case .success(let response):
            return enrichResponse(response, with: extensionMessage)
        case .failure(let error):
            Logger.webExtensions.error("❌ Message handling failed: \(error.localizedDescription)")
            return nil
        case .noHandler:
            guard extensionContext.needsChromeCompatibility else {
                Logger.webExtensions.error("❌ No handler registered for feature: \(extensionMessage.featureName)")
                return nil
            }

            Logger.webExtensions.debug("📬 No handler for \(extensionMessage.featureName), so it goes to the native host")
            return try await sendToNativeHost(message,
                                              applicationIdentifier: applicationIdentifier,
                                              for: extensionContext)
        }
    }

    private func sendToNativeHost(_ message: Any,
                                  applicationIdentifier: String?,
                                  for extensionContext: WKWebExtensionContext) async throws -> Any? {
        guard let nativeMessagingHandler else {
            Logger.webExtensions.error("❌ No native messaging handler, so the message is dropped")
            return nil
        }

        return try await nativeMessagingHandler.sendMessage(message,
                                                            applicationIdentifier: applicationIdentifier,
                                                            for: extensionContext)
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

    /// Hands a new native messaging port to the handler.
    ///
    /// Uses the completion-handler form of the delegate method so a message handler is installed
    /// synchronously, before WebKit processes the extension's next message. WebKit drops a port
    /// message that arrives while the port has no handler, and an extension usually posts its first
    /// message in the same turn as `connectNative()`. Messages that arrive while the host process
    /// is starting are kept in order and replayed once the handler has installed its own.
    public func webExtensionController(_ controller: WKWebExtensionController,
                                       connectUsing port: WKWebExtension.MessagePort,
                                       for extensionContext: WKWebExtensionContext,
                                       completionHandler: @escaping (Error?) -> Void) {
        let displayName = extensionContext.webExtension.displayName ?? "(unknown)"

        // Our own extensions have no native host: the port stays unsupported.
        guard extensionContext.needsChromeCompatibility else {
            Logger.webExtensions.debug("🔗 Connected to extension: \(displayName)")
            completionHandler(nil)
            return
        }

        let applicationIdentifier = port.applicationIdentifier ?? "(none)"
        Logger.webExtensions.debug("🔗 \(displayName) opens a port to \(applicationIdentifier, privacy: .public)")

        guard let nativeMessagingHandler else {
            Logger.webExtensions.error("❌ No native messaging handler, so the port of \(displayName) stays silent")
            completionHandler(nil)
            return
        }

        let pending = PendingPortMessages()
        port.messageHandler = { message, error in
            pending.append(message: message, error: error)
        }

        Task { @MainActor in
            do {
                try await nativeMessagingHandler.connect(port,
                                                         applicationIdentifier: port.applicationIdentifier,
                                                         for: extensionContext)
                // The handler has installed its own message handler, and nothing can slip in before the replay.
                let replayed = pending.drain()
                for (message, error) in replayed {
                    port.messageHandler?(message, error)
                }
                if !replayed.isEmpty {
                    Logger.webExtensions.debug("🔗 Replayed \(replayed.count, privacy: .public) message(s) that \(displayName) posted before its host was up")
                }
                completionHandler(nil)
            } catch {
                // WebKit only disconnects the port, so this is the one place the failure is recorded.
                Logger.webExtensions.error("❌ Port of \(displayName) to \(applicationIdentifier, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
            }
        }
    }
}

/// Holds port messages that arrive before a native messaging host is ready for them.
@available(macOS 15.4, iOS 18.4, *)
private final class PendingPortMessages: @unchecked Sendable {
    private var messages: [(message: Any?, error: Error?)] = []

    func append(message: Any?, error: Error?) {
        messages.append((message, error))
    }

    func drain() -> [(message: Any?, error: Error?)] {
        defer { messages.removeAll() }
        return messages
    }
}
