//
//  WebExtensionMessage.swift
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

/// Represents a message sent from a web extension to the native app.
@available(macOS 15.4, iOS 18.4, *)
public struct WebExtensionMessage {

    /// The feature namespace of the message (e.g., "contentBlocking", "duckPlayer")
    public let featureName: String

    /// The method/command within the feature
    public let method: String

    /// Optional parameters data
    public let params: [String: Any]?

    /// The extension identifier that sent the message
    public let context: String

    public init(
        featureName: String,
        method: String,
        params: [String: Any]? = nil,
        context: String
    ) {
        self.featureName = featureName
        self.method = method
        self.params = params
        self.context = context
    }
}
