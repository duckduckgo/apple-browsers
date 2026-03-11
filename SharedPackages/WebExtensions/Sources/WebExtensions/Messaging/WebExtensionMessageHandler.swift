//
//  WebExtensionMessageHandler.swift
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

/// Protocol for handling messages from web extensions.
/// Each handler is responsible for a specific feature domain.
@available(macOS 15.4, iOS 18.4, *)
public protocol WebExtensionMessageHandler: AnyObject {

    /// The feature name this handler is responsible for
    var handledFeatureName: String { get }

    /// Handle an incoming message from a web extension
    /// - Parameter message: The message to handle
    /// - Returns: A result indicating success, failure, or no handler
    func handleMessage(_ message: WebExtensionMessage) async -> WebExtensionMessageResult
}
