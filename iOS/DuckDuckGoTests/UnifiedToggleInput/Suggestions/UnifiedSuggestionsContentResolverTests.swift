//
//  UnifiedSuggestionsContentResolverTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import XCTest
@testable import DuckDuckGo

final class UnifiedSuggestionsContentResolverTests: XCTestCase {

    private func inputs(mode: TextEntryMode,
                        isTyping: Bool = false,
                        hasFavorites: Bool = false,
                        hasMessages: Bool = false,
                        hasRecents: Bool = false,
                        resultsPending: Bool = false) -> UnifiedSuggestionsInputs {
        UnifiedSuggestionsInputs(mode: mode,
                                 isTyping: isTyping,
                                 hasFavorites: hasFavorites,
                                 hasMessages: hasMessages,
                                 hasRecents: hasRecents,
                                 resultsPending: resultsPending)
    }

    func test_searchEmpty_withFavorites_isFavorites() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .search, hasFavorites: true), previous: nil)
        XCTAssertEqual(kind, .favorites)
    }

    func test_searchEmpty_noFavoritesButHasMessages_isFavorites() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .search, hasFavorites: false, hasMessages: true), previous: nil)
        XCTAssertEqual(kind, .favorites)
    }

    func test_searchEmpty_noFavoritesNoMessages_isLogo() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .search, hasFavorites: false, hasMessages: false), previous: nil)
        XCTAssertEqual(kind, .logo)
    }

    func test_searchTyping_isSearchList() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .search, isTyping: true), previous: nil)
        XCTAssertEqual(kind, .list(.search))
    }

    func test_duckAIEmpty_withRecents_isRecentsList() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .aiChat, hasRecents: true), previous: nil)
        XCTAssertEqual(kind, .list(.recents))
    }

    func test_duckAIEmpty_noRecents_isLogo() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .aiChat, hasRecents: false), previous: nil)
        XCTAssertEqual(kind, .logo)
    }

    func test_duckAITyping_settled_isDuckAIList() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .aiChat, isTyping: true, resultsPending: false), previous: nil)
        XCTAssertEqual(kind, .list(.duckAI))
    }

    func test_duckAITyping_pending_holdsPrevious_noFlashToLogo() {
        let previous: UnifiedSuggestionsContentKind = .list(.duckAI)
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .aiChat, isTyping: true, resultsPending: true), previous: previous)
        XCTAssertEqual(kind, .list(.duckAI))
    }

    func test_duckAITyping_pending_withNoPrevious_fallsBackToDuckAIList_notLogo() {
        let kind = UnifiedSuggestionsContentResolver.resolve(
            inputs(mode: .aiChat, isTyping: true, resultsPending: true), previous: nil)
        XCTAssertEqual(kind, .list(.duckAI))
    }
}
