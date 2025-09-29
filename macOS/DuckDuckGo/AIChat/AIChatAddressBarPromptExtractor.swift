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

import AIChat

/// A protocol that defines a method for extracting a query string from a given value.
protocol AIChatPromptExtracting {
    /// The type of value from which a query string can be extracted.
    associatedtype ValueType

    /// Extracts AI chat content from the given value.
    ///
    /// - Parameter value: The value from which to extract the AI chat content.
    /// - Returns: An `AIChatOpenTrigger` instance containing the query and auto-submit preference.
    func extractAIChatQuery(for value: ValueType) -> AIChatOpenTrigger
}

/// A struct that implements the `AIChatPromptExtracting` protocol for extracting AI chat content
/// from values of type `AddressBarTextField.Value`.
struct AIChatAddressBarPromptExtractor: AIChatPromptExtracting {
    typealias ValueType = AddressBarTextField.Value

    public func extractAIChatQuery(for value: ValueType) -> AIChatOpenTrigger {
        // Extract query from address bar text field value
        let query: String? = queryForValue(value)

        // We don't want to auto-submit if the user is opening duck.ai from the SERP
        let shouldAutoSubmit: Bool = shouldAutoSubmitForValue(value)

        return AIChatOpenTrigger.query(query, shouldAutoSubmit: shouldAutoSubmit)
    }

    /// Extracts a query string from the given `AddressBarTextField.Value`.
    ///
    /// - Parameter value: The `AddressBarTextField.Value` from which to extract the query string.
    /// - Returns: A query string if it can be extracted from the value, otherwise `nil`.
    ///   For URL values, returns `nil` if the URL is already a duck.ai URL, otherwise returns the search query.
    ///   For text values, returns the text itself. For suggestions, returns the suggestion string.
    private func queryForValue(_ value: ValueType) -> String? {
        switch value {
        case let .text(text, _):
            return text
        case let .url(_, url, _):
            if url.isDuckAIURL {
                /// We don't want the search query if the user is already on duck.ai
                return nil
            } else {
                return url.searchQuery
            }
        case let .suggestion(suggestion):
            return suggestion.string
        }
    }

    /// Determines whether the AI chat query should be auto-submitted based on the given value.
    ///
    /// - Parameter value: The `AddressBarTextField.Value` to evaluate for auto-submission.
    /// - Returns: `true` if the query should be auto-submitted, `false` otherwise.
    ///   Returns `false` for DuckDuckGo search URLs to prevent auto-submission when navigating from SERP.
    ///   Returns `true` for all other value types.
    private func shouldAutoSubmitForValue(_ value: ValueType) -> Bool {
        if case let .url(_, url, _) = value {
            !url.isDuckDuckGoSearch
        } else {
            true
        }
    }
}
