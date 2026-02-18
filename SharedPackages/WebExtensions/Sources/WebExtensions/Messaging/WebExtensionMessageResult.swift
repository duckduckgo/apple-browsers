//
//  WebExtensionMessageResult.swift
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

/// Represents the result of handling a web extension message.
@available(macOS 15.4, iOS 18.4, *)
public enum WebExtensionMessageResult {

    /// Handler successfully processed the message
    case success(Any?)

    /// Handler encountered an error while processing
    case failure(Error)

    /// No handler registered for the message's feature
    case noHandler
}

/// Errors that can occur during message handling
@available(macOS 15.4, iOS 18.4, *)
public enum WebExtensionMessageHandlerError: LocalizedError {

    case unknownMethod(String)
    case missingParameter(String)
    case invalidParameterType(String, expected: String)

    public var errorDescription: String? {
        switch self {
        case .unknownMethod(let method):
            return "Unknown method: \(method)"
        case .missingParameter(let parameter):
            return "Missing required parameter: \(parameter)"
        case .invalidParameterType(let parameter, let expected):
            return "Invalid type for parameter '\(parameter)': expected \(expected)"
        }
    }
}
