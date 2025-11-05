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

    func testExtractAIChatQueryForTextValue() {
        let query = "example query"
        let value = AddressBarTextField.Value.text(query, userTyped: false)
        let result = AIChatAddressBarPromptExtractor().extractAIChatQuery(for: value)

        if case let .query(extractedQuery, shouldAutoSubmit) = result {
            XCTAssertEqual(extractedQuery, query)
            XCTAssertTrue(shouldAutoSubmit)
        } else {
            XCTFail("Expected .query case")
        }
    }

    func testExtractAIChatQueryForSearchURLValue() {
        let url = URL(string: "https://duckduckgo.com/?q=swift")!
        let value = AddressBarTextField.Value.url(urlString: url.absoluteString, url: url, userTyped: false)
        let result = AIChatAddressBarPromptExtractor().extractAIChatQuery(for: value)

        if case let .query(extractedQuery, shouldAutoSubmit) = result {
            XCTAssertEqual(extractedQuery, "swift")
            XCTAssertFalse(shouldAutoSubmit) // Should not auto-submit for DuckDuckGo search URLs
        } else {
            XCTFail("Expected .query case")
        }
    }

    func testExtractAIChatQueryForAIChatPage() {
        let url = URL(string: "https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&duckai=2")!
        let value = AddressBarTextField.Value.url(urlString: url.absoluteString, url: url, userTyped: false)
        let result = AIChatAddressBarPromptExtractor().extractAIChatQuery(for: value)

        if case let .query(extractedQuery, shouldAutoSubmit) = result {
            XCTAssertNil(extractedQuery)
            XCTAssertFalse(shouldAutoSubmit) // Should not auto-submit for DuckDuckGo search URLs
        } else {
            XCTFail("Expected .query case")
        }
    }

    func testExtractAIChatQueryForNonSearchURLValue() {
        let url = URL(string: "https://zombo.com")!
        let value = AddressBarTextField.Value.url(urlString: url.absoluteString, url: url, userTyped: false)
        let result = AIChatAddressBarPromptExtractor().extractAIChatQuery(for: value)

        if case let .query(extractedQuery, shouldAutoSubmit) = result {
            XCTAssertNil(extractedQuery)
            XCTAssertTrue(shouldAutoSubmit) // Should auto-submit for non-DuckDuckGo URLs
        } else {
            XCTFail("Expected .query case")
        }
    }

    func testExtractAIChatQueryForSuggestionValue() {
        let value = "Suggestion"
        let suggestion = AddressBarTextField.Value.suggestion(SuggestionViewModel(suggestion: .phrase(phrase: value), userStringValue: value))
        let result = AIChatAddressBarPromptExtractor().extractAIChatQuery(for: suggestion)

        if case let .query(extractedQuery, shouldAutoSubmit) = result {
            XCTAssertEqual(extractedQuery, value)
            XCTAssertTrue(shouldAutoSubmit)
        } else {
            XCTFail("Expected .query case")
        }
    }

    func testExtractAIChatQueryForEmptyTextValue() {
        let query = ""
        let value = AddressBarTextField.Value.text(query, userTyped: false)
        let result = AIChatAddressBarPromptExtractor().extractAIChatQuery(for: value)

        if case let .query(extractedQuery, shouldAutoSubmit) = result {
            XCTAssertEqual(extractedQuery, query)
            XCTAssertTrue(shouldAutoSubmit)
        } else {
            XCTFail("Expected .query case")
        }
    }

    func testExtractAIChatQueryForAIBangURL() {
        let url = URL(string: "https://duckduckgo.com/?q=!ai+test+query")!
        let value = AddressBarTextField.Value.url(urlString: url.absoluteString, url: url, userTyped: false)
        let result = AIChatAddressBarPromptExtractor().extractAIChatQuery(for: value)

        if case let .query(extractedQuery, shouldAutoSubmit) = result {
            XCTAssertNil(extractedQuery) // Should be nil for duck.ai URLs
            XCTAssertFalse(shouldAutoSubmit) // Should not auto-submit for DuckDuckGo search URLs
        } else {
            XCTFail("Expected .query case")
        }
    }

    func testExtractAIChatQueryForDuckAIChatURL() {
        let url = URL(string: "https://duckduckgo.com/?q=example&ia=chat")!
        let value = AddressBarTextField.Value.url(urlString: url.absoluteString, url: url, userTyped: false)
        let result = AIChatAddressBarPromptExtractor().extractAIChatQuery(for: value)

        if case let .query(extractedQuery, shouldAutoSubmit) = result {
            XCTAssertNil(extractedQuery) // Should be nil for duck.ai URLs
            XCTAssertFalse(shouldAutoSubmit) // Should not auto-submit for DuckDuckGo search URLs
        } else {
            XCTFail("Expected .query case")
        }
    }
}
