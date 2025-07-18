//
//  NewTabPageDataModelSuggestionTests.swift
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
@testable import NewTabPage

final class NewTabPageDataModelSuggestionTests: XCTestCase {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Helper to round-trip
    private func roundTrip(_ suggestion: NewTabPageDataModel.Suggestion) throws -> NewTabPageDataModel.Suggestion {
        let data = try encoder.encode(suggestion)
        return try decoder.decode(NewTabPageDataModel.Suggestion.self, from: data)
    }

    func testPhraseRoundTrip() throws {
        let original = NewTabPageDataModel.Suggestion.phrase(phrase: "hello")
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
    }

    func testWebsiteRoundTrip() throws {
        let original = NewTabPageDataModel.Suggestion.website(url: "https://duckduckgo.com")
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
    }

    func testBookmarkRoundTrip() throws {
        let original = NewTabPageDataModel.Suggestion.bookmark(
            title: "DDG",
            url: "https://duckduckgo.com",
            isFavorite: true,
            score: 42
        )
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
    }

    func testHistoryEntryRoundTrip() throws {
        let original = NewTabPageDataModel.Suggestion.historyEntry(
            title: nil,
            url: "https://example.com",
            score: 10
        )
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
    }

    func testInternalPageRoundTrip() throws {
        let original = NewTabPageDataModel.Suggestion.internalPage(
            title: "Internal",
            url: "app://internal",
            score: 5
        )
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
    }

    func testOpenTabRoundTrip() throws {
        let original = NewTabPageDataModel.Suggestion.openTab(
            title: "MyTab",
            tabId: "tab-123",
            score: 7
        )
        let decoded = try roundTrip(original)
        XCTAssertEqual(decoded, original)
    }

    func testDecodingFromRawJSON() throws {
        let json: [String: Any] = [
            "kind": "website",
            "url": "https://example.com"
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try decoder.decode(NewTabPageDataModel.Suggestion.self, from: data)
        XCTAssertEqual(decoded, .website(url: "https://example.com"))
    }
}
