//
//  WebExtensionMessageRouter.swift
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

/// Default implementation of WebExtensionMessageRouting that routes messages
/// based on extension identifier and feature name.
@available(macOS 15.4, iOS 18.4, *)
public final class WebExtensionMessageRouter: WebExtensionMessageRouting {

    private var handlers: [String: [String: WebExtensionMessageHandler]] = [:]
    private let lock = NSLock()

    public init() {}

    public func registerHandler(_ handler: WebExtensionMessageHandler, for extensionIdentifier: String) {
        lock.lock()
        defer { lock.unlock() }

        if handlers[extensionIdentifier] == nil {
            handlers[extensionIdentifier] = [:]
        }

        handlers[extensionIdentifier]?[handler.handledFeatureName] = handler

        Logger.webExtensions.debug("📝 Registered handler for extension '\(extensionIdentifier)' feature: \(handler.handledFeatureName)")
    }

    public func unregisterHandlers(for extensionIdentifier: String) {
        lock.lock()
        defer { lock.unlock() }

        let count = handlers[extensionIdentifier]?.count ?? 0
        handlers.removeValue(forKey: extensionIdentifier)

        Logger.webExtensions.debug("🗑️ Unregistered \(count) handler(s) for extension '\(extensionIdentifier)'")
    }

    public func routeMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult {
        let handler: WebExtensionMessageHandler?

        lock.lock()
        let extensionIdentifier = message.extensionIdentifier
        handler = handlers[extensionIdentifier]?[message.featureName]
        lock.unlock()

        guard let handler = handler else {
            Logger.webExtensions.warning("⚠️ No handler for extension '\(extensionIdentifier)' feature '\(message.featureName)'")
            return .noHandler
        }

        Logger.webExtensions.debug("📩 Routing message from extension '\(extensionIdentifier)' to handler: \(message.featureName).\(message.method)")

        return await handler.handleMessage(message)
    }
}
