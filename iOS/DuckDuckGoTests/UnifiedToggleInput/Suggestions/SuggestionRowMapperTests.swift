//
//  SuggestionRowMapperTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
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
    }

    func test_searchRow_hasFindIcon_andSearchSubtitle() {
        let row = SuggestionRowMapper.searchRow(query: "weather", idPrefix: "search")
        XCTAssertEqual(row.title, "weather")
        XCTAssertEqual(row.subtitle, UserText.autocompleteSearchDuckDuckGo)
    }
}
