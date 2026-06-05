//
//  UnifiedSuggestionsInputsMergerTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import XCTest
@testable import DuckDuckGo

final class UnifiedSuggestionsInputsMergerTests: XCTestCase {

    private typealias Merger = UnifiedSuggestionsInputsMerger

    func test_search_blank_withFavorites_resolvesFavoritesInputs() {
        let i = Merger.merge(
            mode: .search, text: "",
            search: .init(hasFavorites: true, hasMessages: false),
            duckAI: nil)
        XCTAssertEqual(i, UnifiedSuggestionsInputs(
            mode: .search, isTyping: false,
            hasFavorites: true, hasMessages: false,
            hasRecents: false, resultsPending: false))
    }

    func test_search_typing_isTyping_andNeverHasRecents() {
        let i = Merger.merge(
            mode: .search, text: "abc",
            search: .init(hasFavorites: true, hasMessages: true),
            duckAI: .init(hasRecents: true, settled: false))
        XCTAssertTrue(i.isTyping)
        XCTAssertFalse(i.hasRecents)
        XCTAssertFalse(i.resultsPending)
        XCTAssertEqual(i.mode, .search)
    }

    func test_aichat_blank_withRecents_setsHasRecents() {
        let i = Merger.merge(
            mode: .aiChat, text: "",
            search: .init(hasFavorites: false, hasMessages: false),
            duckAI: .init(hasRecents: true, settled: true))
        XCTAssertEqual(i.mode, .aiChat)
        XCTAssertTrue(i.hasRecents)
        XCTAssertFalse(i.isTyping)
        XCTAssertFalse(i.resultsPending)
    }

    func test_aichat_typing_unsettled_setsResultsPending() {
        let i = Merger.merge(
            mode: .aiChat, text: "foo",
            search: .init(hasFavorites: false, hasMessages: false),
            duckAI: .init(hasRecents: false, settled: false))
        XCTAssertTrue(i.isTyping)
        XCTAssertTrue(i.resultsPending)
    }

    func test_aichat_typing_settled_clearsResultsPending() {
        let i = Merger.merge(
            mode: .aiChat, text: "foo",
            search: .init(hasFavorites: false, hasMessages: false),
            duckAI: .init(hasRecents: false, settled: true))
        XCTAssertTrue(i.isTyping)
        XCTAssertFalse(i.resultsPending)
    }

    func test_aichat_withoutDuckAISource_hasNoRecentsOrPending() {
        let i = Merger.merge(
            mode: .aiChat, text: "foo",
            search: .init(hasFavorites: true, hasMessages: false),
            duckAI: nil)
        XCTAssertFalse(i.hasRecents)
        XCTAssertFalse(i.resultsPending)
        XCTAssertFalse(i.hasFavorites) // search facts never leak into aichat
    }
}
