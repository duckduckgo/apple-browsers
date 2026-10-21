//
//  AIChatMentionPickerFilterTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import AppKit
@testable import DuckDuckGo_Privacy_Browser

final class AIChatMentionPickerFilterTests: XCTestCase {

    // MARK: - Helpers

    private func makeTab(id: String, title: String, url: String) -> AIChatTabAttachment {
        AIChatTabAttachment(id: id, title: title, url: URL(string: url)!, favicon: nil)
    }

    private func ids(_ tabs: [AIChatTabAttachment]) -> [String] {
        tabs.map(\.id)
    }

    // MARK: - Empty query

    func testEmptyQuery_ReturnsAllTabsUnchanged() {
        let input = [
            makeTab(id: "1", title: "GitHub", url: "https://github.com"),
            makeTab(id: "2", title: "Wikipedia", url: "https://wikipedia.org"),
            makeTab(id: "3", title: "Hacker News", url: "https://news.ycombinator.com")
        ]
        XCTAssertEqual(ids(AIChatMentionPickerFilter.filter(input, query: "")), ["1", "2", "3"])
    }

    // MARK: - Title matches

    func testTitleSubstring_CaseInsensitive() {
        let input = [
            makeTab(id: "1", title: "GitHub", url: "https://example.com"),
            makeTab(id: "2", title: "Wikipedia", url: "https://example.org")
        ]
        XCTAssertEqual(ids(AIChatMentionPickerFilter.filter(input, query: "wiki")), ["2"])
        XCTAssertEqual(ids(AIChatMentionPickerFilter.filter(input, query: "WIKI")), ["2"])
        XCTAssertEqual(ids(AIChatMentionPickerFilter.filter(input, query: "hub")), ["1"])
    }

    // MARK: - URL matches

    func testUrlSubstring_CaseInsensitive() {
        let input = [
            makeTab(id: "1", title: "Source Code Search", url: "https://github.com/duckduckgo"),
            makeTab(id: "2", title: "Encyclopedia", url: "https://wikipedia.org")
        ]
        // No title contains "github", but url does — should still match.
        XCTAssertEqual(ids(AIChatMentionPickerFilter.filter(input, query: "github")), ["1"])
        XCTAssertEqual(ids(AIChatMentionPickerFilter.filter(input, query: "GITHUB")), ["1"])
    }

    // MARK: - Scoring (title beats url)

    func testTitleMatchScoresHigherThanUrlOnlyMatch() {
        // Tab A: title contains "foo". Tab B: only url contains "foo". A should sort first.
        let input = [
            makeTab(id: "url-only", title: "Generic", url: "https://example.com/foo"),
            makeTab(id: "title-hit", title: "Foo Bar", url: "https://other.com")
        ]
        XCTAssertEqual(ids(AIChatMentionPickerFilter.filter(input, query: "foo")), ["title-hit", "url-only"])
    }

    func testTitleAndUrlBothMatchScoresHighestAndComesFirst() {
        let input = [
            makeTab(id: "url-only", title: "Generic", url: "https://example.com/foo"),
            makeTab(id: "title-only", title: "Foo Title", url: "https://other.com"),
            makeTab(id: "both", title: "Foo Page", url: "https://foo.example")
        ]
        // "both" gets 2 (title) + 1 (url) = 3 — wins. "title-only" gets 2. "url-only" gets 1.
        XCTAssertEqual(
            ids(AIChatMentionPickerFilter.filter(input, query: "foo")),
            ["both", "title-only", "url-only"]
        )
    }

    // MARK: - Stable tie-breaking

    func testTieScoresPreserveInputOrder() {
        let input = [
            makeTab(id: "second", title: "Wikipedia - Article B", url: "https://en.wikipedia.org/B"),
            makeTab(id: "first", title: "Wikipedia - Article A", url: "https://en.wikipedia.org/A")
        ]
        // Both score 3 (title+url). Tie → preserve original order: ["second", "first"].
        XCTAssertEqual(ids(AIChatMentionPickerFilter.filter(input, query: "wikipedia")), ["second", "first"])
    }

    // MARK: - No matches

    func testNoMatches_ReturnsEmpty() {
        let input = [
            makeTab(id: "1", title: "GitHub", url: "https://github.com"),
            makeTab(id: "2", title: "Wikipedia", url: "https://wikipedia.org")
        ]
        XCTAssertTrue(AIChatMentionPickerFilter.filter(input, query: "xyz123abc").isEmpty)
    }

    // MARK: - Empty input

    func testEmptyInput_ReturnsEmpty() {
        XCTAssertTrue(AIChatMentionPickerFilter.filter([], query: "anything").isEmpty)
    }

    // MARK: - Current-tab pinning

    func testCurrentTabPinnedAtTop_WithEmptyQuery() {
        let input = [
            makeTab(id: "1", title: "GitHub", url: "https://github.com"),
            makeTab(id: "2", title: "Wikipedia", url: "https://wikipedia.org"),
            makeTab(id: "3", title: "Hacker News", url: "https://news.ycombinator.com")
        ]
        // Empty query → list unchanged except current tab hoisted to index 0.
        XCTAssertEqual(
            ids(AIChatMentionPickerFilter.filter(input, query: "", currentTabId: "2")),
            ["2", "1", "3"]
        )
    }

    func testCurrentTabPinnedAtTop_WhenItMatchesTheQuery() {
        let input = [
            makeTab(id: "first-match", title: "Apple Pages", url: "https://apple.com/pages"),
            makeTab(id: "current", title: "Apple Plus", url: "https://apple.com/plus")
        ]
        // Both match "apple"; without pinning, `first-match` (input index 0) would win the
        // stable tie. With current pinning, `current` (index 1) hoists to the top.
        XCTAssertEqual(
            ids(AIChatMentionPickerFilter.filter(input, query: "apple", currentTabId: "current")),
            ["current", "first-match"]
        )
    }

    func testCurrentTabNotIncluded_WhenItDoesNotMatchTheQuery() {
        let input = [
            makeTab(id: "github", title: "GitHub", url: "https://github.com"),
            makeTab(id: "current", title: "Hacker News", url: "https://news.ycombinator.com")
        ]
        // Current tab doesn't match "github" — pinning must not resurrect it.
        XCTAssertEqual(
            ids(AIChatMentionPickerFilter.filter(input, query: "github", currentTabId: "current")),
            ["github"]
        )
    }

    func testCurrentTabIdNil_LeavesOrderingAsBefore() {
        let input = [
            makeTab(id: "1", title: "GitHub", url: "https://github.com"),
            makeTab(id: "2", title: "Wikipedia", url: "https://wikipedia.org")
        ]
        XCTAssertEqual(
            ids(AIChatMentionPickerFilter.filter(input, query: "", currentTabId: nil)),
            ["1", "2"]
        )
    }
}
