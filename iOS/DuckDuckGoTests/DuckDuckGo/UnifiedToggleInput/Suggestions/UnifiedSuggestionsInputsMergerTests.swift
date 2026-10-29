//
//  UnifiedSuggestionsInputsMergerTests.swift
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

import XCTest
@testable import DuckDuckGo

final class UnifiedSuggestionsInputsMergerTests: XCTestCase {

    private typealias Merger = UnifiedSuggestionsInputsMerger

    func test_search_blank_withFavorites_resolvesFavoritesInputs() {
        let i = Merger.merge(
            mode: .search, text: "",
            hasUserInteractedWithText: false,
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
            hasUserInteractedWithText: true,
            search: .init(hasFavorites: true, hasMessages: true),
            duckAI: .init(hasRecents: true, settled: false))
        XCTAssertTrue(i.isTyping)
        XCTAssertFalse(i.hasRecents)
        XCTAssertFalse(i.resultsPending)
        XCTAssertEqual(i.mode, .search)
    }

    // A typed (non-URL) query shows suggestions immediately — the interaction flag isn't required.
    func test_search_typedNonURL_isTyping_withoutInteractionFlag() {
        let i = Merger.merge(
            mode: .search, text: "cats",
            hasUserInteractedWithText: false,
            search: .init(hasFavorites: true, hasMessages: false),
            duckAI: nil)
        XCTAssertTrue(i.isTyping)
    }

    // Pre-filled, unedited URL (omnibar tapped on a loaded page) stays not-typing so favorites show.
    func test_search_prefilledURL_notInteracted_isNotTyping() {
        let i = Merger.merge(
            mode: .search, text: "https://example.com",
            hasUserInteractedWithText: false,
            search: .init(hasFavorites: true, hasMessages: false),
            duckAI: nil)
        XCTAssertFalse(i.isTyping)
    }

    // Once the user edits the pre-filled URL, suggestions take over.
    func test_search_prefilledURL_afterInteraction_isTyping() {
        let i = Merger.merge(
            mode: .search, text: "https://example.com",
            hasUserInteractedWithText: true,
            search: .init(hasFavorites: true, hasMessages: false),
            duckAI: nil)
        XCTAssertTrue(i.isTyping)
    }

    func test_aichat_blank_withRecents_setsHasRecents() {
        let i = Merger.merge(
            mode: .aiChat, text: "",
            hasUserInteractedWithText: false,
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
            hasUserInteractedWithText: true,
            search: .init(hasFavorites: false, hasMessages: false),
            duckAI: .init(hasRecents: false, settled: false))
        XCTAssertTrue(i.isTyping)
        XCTAssertTrue(i.resultsPending)
    }

    func test_aichat_typing_settled_clearsResultsPending() {
        let i = Merger.merge(
            mode: .aiChat, text: "foo",
            hasUserInteractedWithText: true,
            search: .init(hasFavorites: false, hasMessages: false),
            duckAI: .init(hasRecents: false, settled: true))
        XCTAssertTrue(i.isTyping)
        XCTAssertFalse(i.resultsPending)
    }

    func test_aichat_withoutDuckAISource_hasNoRecentsOrPending() {
        let i = Merger.merge(
            mode: .aiChat, text: "foo",
            hasUserInteractedWithText: true,
            search: .init(hasFavorites: true, hasMessages: false),
            duckAI: nil)
        XCTAssertFalse(i.hasRecents)
        XCTAssertFalse(i.resultsPending)
        XCTAssertFalse(i.hasFavorites) // search facts never leak into aichat
    }
}
