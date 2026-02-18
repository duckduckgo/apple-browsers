//
//  WebExtensionHandlerProviding.swift
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
import WebKit

/// Protocol for providing extension-specific message handlers.
/// Platform-specific implementations determine which handlers to create for each extension.
@available(macOS 15.4, iOS 18.4, *)
public protocol WebExtensionHandlerProviding {

    /// Create handlers for a specific extension
    /// - Parameter context: The extension context
    /// - Returns: Array of handlers to register for this extension
    func makeHandlers(for context: WKWebExtensionContext) -> [WebExtensionMessageHandler]
}
