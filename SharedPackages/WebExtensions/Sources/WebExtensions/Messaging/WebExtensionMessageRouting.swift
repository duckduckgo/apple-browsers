//
//  WebExtensionMessageRouting.swift
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

/// Protocol for routing messages to appropriate handlers.
@available(macOS 15.4, iOS 18.4, *)
public protocol WebExtensionMessageRouting: AnyObject {

    /// Register a handler for a specific extension and feature
    /// - Parameters:
    ///   - handler: The handler to register
    ///   - extensionIdentifier: The unique identifier of the extension
    func registerHandler(_ handler: WebExtensionMessageHandler, for extensionIdentifier: String)

    /// Unregister all handlers for a specific extension
    /// - Parameter extensionIdentifier: The unique identifier of the extension
    func unregisterHandlers(for extensionIdentifier: String)

    /// Route a message to the appropriate handler
    /// - Parameter message: The message to route
    /// - Returns: The result of handling the message
    func routeMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult
}
