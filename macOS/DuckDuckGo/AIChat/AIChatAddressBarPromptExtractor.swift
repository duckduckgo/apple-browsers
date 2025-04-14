//
//  AIChatAddressBarPromptExtractor.swift
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

/// A protocol that defines a method for extracting a query string from a given value.
protocol AIChatPromptExtracting {
    /// The type of value from which a query string can be extracted.
    associatedtype ValueType

    /// Extracts a query string from the given value.
    ///
    /// - Parameter value: The value from which to extract the query string.
    /// - Returns: A query string if it can be extracted from the value, otherwise `nil`.
    func queryForValue(_ value: ValueType) -> String?
}

/// A struct that implements the `QueryExtractable` protocol for extracting query strings
/// from values of type `AddressBarTextField.Value`.
struct AIChatAddressBarPromptExtractor: AIChatPromptExtracting {
    typealias ValueType = AddressBarTextField.Value

    /// Extracts a query string from the given `AddressBarTextField.Value`.
    ///
    /// - Parameter value: The `AddressBarTextField.Value` from which to extract the query string.
    /// - Returns: A query string if it can be extracted from the value, otherwise `nil`.
    func queryForValue(_ value: ValueType) -> String? {
        switch value {
        case let .text(text, _):
            return text
        case let .url(_, url, _):
            if url.isAIChatURL {
                /// We don't want the search query if the user is already on duck.ai
                return nil
            } else {
                return url.searchQuery
            }
        case let .suggestion(suggestion):
            return suggestion.string
        }
    }
}
