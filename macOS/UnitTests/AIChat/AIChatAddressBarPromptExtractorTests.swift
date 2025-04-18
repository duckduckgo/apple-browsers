//
//  AIChatAddressBarPromptExtractorTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class AIChatAddressBarPromptExtractorTests: XCTestCase {

    func testQueryForTextValue() {
        let query = "example query"
        let value = AddressBarTextField.Value.text(query, userTyped: false)
        let extractedQuery = AIChatAddressBarPromptExtractor().queryForValue(value)
        XCTAssertEqual(extractedQuery, query)
    }

    func testQueryForSearchURLValue() {
        let url = URL(string: "https://duckduckgo.com/?q=swift")!
        let value = AddressBarTextField.Value.url(urlString: url.absoluteString, url: url, userTyped: false)
        let extractedQuery = AIChatAddressBarPromptExtractor().queryForValue(value)
        XCTAssertEqual(extractedQuery, "swift")
    }

    func testQueryForAIChatPage() {
        let url = URL(string: "https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&duckai=2")!
        let value = AddressBarTextField.Value.url(urlString: url.absoluteString, url: url, userTyped: false)
        let extractedQuery = AIChatAddressBarPromptExtractor().queryForValue(value)
        XCTAssertNil(extractedQuery)
    }

    func testQueryForNonSearchURLValue() {
        let url = URL(string: "https://zombo.com")!
        let value = AddressBarTextField.Value.url(urlString: url.absoluteString, url: url, userTyped: false)
        let extractedQuery = AIChatAddressBarPromptExtractor().queryForValue(value)
        XCTAssertNil(extractedQuery)
    }

    func testQueryForSuggestionValue() {
        let value = "Suggestion"
        let suggestion = AddressBarTextField.Value.suggestion(SuggestionViewModel(suggestion: .phrase(phrase: value), userStringValue: value))
        let extractedQuery = AIChatAddressBarPromptExtractor().queryForValue(suggestion)
        XCTAssertEqual(extractedQuery, value)
    }
}
