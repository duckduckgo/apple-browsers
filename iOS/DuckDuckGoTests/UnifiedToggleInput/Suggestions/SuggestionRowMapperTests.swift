//
//  SuggestionRowMapperTests.swift
//  DuckDuckGo
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

import Suggestions
import AIChat
import XCTest
@testable import DuckDuckGo

final class SuggestionRowMapperTests: XCTestCase {

    func test_website_mapsTitleToFormattedURL_noSubtitle() {
        let url = URL(string: "https://example.com/path")!
        let row = SuggestionRowMapper.row(for: .website(url: url), query: "exa", idPrefix: "url")
        XCTAssertEqual(row.title, url.formattedForSuggestion())
        XCTAssertNil(row.subtitle)
        XCTAssertEqual(row.accessory, .none)
        XCTAssertEqual(row.icon, .globe)
        // Websites render plain (no bold-completion) like legacy — only `.phrase` passes `query`.
        XCTAssertNil(row.query)
    }

    func test_bookmark_mapsTitleAndURLSubtitle() {
        let url = URL(string: "https://example.com")!
        let row = SuggestionRowMapper.row(for: .bookmark(title: "Bm", url: url, isFavorite: false, score: 0),
                                          query: nil, idPrefix: "url")
        XCTAssertEqual(row.title, "Bm")
        XCTAssertEqual(row.subtitle, url.formattedForSuggestion())
    }

    func test_serpHistory_usesSearchQueryTitle_andSearchSubtitle() {
        let url = URL(string: "https://duckduckgo.com/?q=swift")!
        let row = SuggestionRowMapper.row(for: .historyEntry(title: nil, url: url, score: 0),
                                          query: nil, idPrefix: "url")
        XCTAssertEqual(row.title, url.searchQuery ?? "")
        XCTAssertEqual(row.subtitle, UserText.autocompleteSearchDuckDuckGo)
    }

    func test_history_deleteAccessory_offByDefault_onWhenRequested() {
        let url = URL(string: "https://example.com/page")!
        let off = SuggestionRowMapper.row(for: .historyEntry(title: "T", url: url, score: 0),
                                          query: nil, idPrefix: "url")
        XCTAssertEqual(off.accessory, .none)
        let on = SuggestionRowMapper.row(for: .historyEntry(title: "T", url: url, score: 0),
                                         query: nil, idPrefix: "url", includesDeleteAccessory: true)
        XCTAssertEqual(on.accessory, .delete)
    }

    func test_openTab_subtitlePrefixedWithSwitchToTab() {
        let url = URL(string: "https://example.com")!
        let row = SuggestionRowMapper.row(for: .openTab(title: "Tab", url: url, tabId: "1", score: 0),
                                          query: nil, idPrefix: "url")
        XCTAssertEqual(row.title, "Tab")
        XCTAssertEqual(row.subtitle, "\(UserText.autocompleteSwitchToTab) · \(url.formattedForSuggestion())")
    }

    func test_chat_pinnedUsesPinIcon_titleAndId() {
        let chat = AIChatSuggestion(id: "abc", title: "Hello", isPinned: true, chatId: "c1")
        let row = SuggestionRowMapper.row(for: chat)
        XCTAssertEqual(row.id, "chat-abc")
        XCTAssertEqual(row.title, "Hello")
        XCTAssertNil(row.subtitle)
        XCTAssertEqual(row.accessory, .none)
        XCTAssertEqual(row.icon, .pin)
    }

    func test_searchRow_hasFindIcon_andSearchSubtitle() {
        let row = SuggestionRowMapper.searchRow(query: "weather", idPrefix: "search")
        XCTAssertEqual(row.title, "weather")
        XCTAssertEqual(row.subtitle, UserText.autocompleteSearchDuckDuckGo)
    }
}
