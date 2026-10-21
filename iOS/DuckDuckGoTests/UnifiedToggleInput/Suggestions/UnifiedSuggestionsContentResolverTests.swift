//
//  UnifiedSuggestionsContentResolverTests.swift
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

    func test_legacyIdle_hatchIsEmbeddedInBothModesIncludingEmptyStates() {
        let states = [
            inputs(mode: .search),
            inputs(mode: .search, hasFavorites: true),
            inputs(mode: .search, hasMessages: true),
            inputs(mode: .aiChat),
            inputs(mode: .aiChat, hasRecents: true)
        ]
        for state in states {
            let content = UnifiedSuggestionsContentResolver.resolve(state, previous: nil)
            let placement = chromePlacement(mode: state.mode)

            XCTAssertEqual(placement.escapeHatch, .embedded, "\(state)")
            XCTAssertTrue(showsEmbeddedLegacyContent(content), "\(state)")
        }
    }

    func test_syncPromo_isEmbeddedOnlyInLegacyDuckAI() {
        XCTAssertEqual(chromePlacement(mode: .aiChat, showsSyncPromo: true).syncPromo, .embedded)
        XCTAssertEqual(chromePlacement(mode: .search, showsSyncPromo: true).syncPromo, .hidden)
        XCTAssertEqual(chromePlacement(mode: .aiChat, showsSyncPromo: false).syncPromo, .hidden)
    }

    func test_absentHatch_doesNotHideEligiblePromoOrEmptyScrollView() {
        let placement = chromePlacement(mode: .aiChat, hasEscapeHatch: false, showsSyncPromo: true)

        XCTAssertEqual(placement.escapeHatch, .hidden)
        XCTAssertEqual(placement.syncPromo, .embedded)
        XCTAssertTrue(showsEmbeddedLegacyContent(.logo))
    }

    func test_typing_hidesChromeInBothModesAndLayouts() {
        for usesRedesign in [false, true] {
            for mode in TextEntryMode.allCases {
                let placement = chromePlacement(usesRedesign: usesRedesign, mode: mode, isTyping: true, showsSyncPromo: true)
                let content = UnifiedSuggestionsContentResolver.resolve(inputs(mode: mode, isTyping: true), previous: nil)

                XCTAssertEqual(placement.escapeHatch, .hidden)
                XCTAssertEqual(placement.syncPromo, .hidden)
                XCTAssertFalse(showsEmbeddedLegacyContent(content, usesRedesign: usesRedesign))
            }
        }
    }

    func test_fireTab_hidesChromeAndEmbeddedContentInBothLayouts() {
        for usesRedesign in [false, true] {
            for mode in TextEntryMode.allCases {
                let placement = chromePlacement(usesRedesign: usesRedesign, mode: mode, isFireTab: true, showsSyncPromo: true)

                XCTAssertEqual(placement.escapeHatch, .hidden)
                XCTAssertEqual(placement.syncPromo, .hidden)
            }
            for content: UnifiedSuggestionsContentKind in [.favorites, .logo, .list(.recents), .list(.search), .list(.duckAI)] {
                XCTAssertFalse(showsEmbeddedLegacyContent(content, usesRedesign: usesRedesign, isFireTab: true))
            }
        }
    }

    func test_redesignedLayout_preservesPinnedChromeExceptHatchInSearchModules() {
        let emptySearch = chromePlacement(usesRedesign: true, mode: .search)
        let searchModules = chromePlacement(usesRedesign: true, showsRedesignedSearchModules: true, mode: .search)
        let duckAI = chromePlacement(usesRedesign: true, mode: .aiChat, showsSyncPromo: true)

        XCTAssertEqual(emptySearch.escapeHatch, .pinned)
        XCTAssertEqual(emptySearch.syncPromo, .hidden)
        XCTAssertEqual(searchModules.escapeHatch, .embedded)
        XCTAssertEqual(searchModules.syncPromo, .hidden)
        XCTAssertEqual(duckAI.escapeHatch, .pinned)
        XCTAssertEqual(duckAI.syncPromo, .pinned)
        for content: UnifiedSuggestionsContentKind in [.favorites, .logo, .list(.recents), .list(.search), .list(.duckAI)] {
            XCTAssertFalse(showsEmbeddedLegacyContent(content, usesRedesign: true))
        }
    }

    func test_duckAITyping_pendingRecents_stayEmbeddedWithoutChromeUntilResultsArrive() {
        let pending = inputs(mode: .aiChat, isTyping: true, hasRecents: true, resultsPending: true)
        let pendingContent = UnifiedSuggestionsContentResolver.resolve(pending, previous: .list(.recents))
        let placement = chromePlacement(mode: .aiChat, isTyping: pending.isTyping, showsSyncPromo: true)

        XCTAssertEqual(pendingContent, .list(.recents))
        XCTAssertTrue(showsEmbeddedLegacyContent(pendingContent))
        XCTAssertEqual(placement.escapeHatch, .hidden)
        XCTAssertEqual(placement.syncPromo, .hidden)

        let settled = inputs(mode: .aiChat, isTyping: true, hasRecents: true, resultsPending: false)
        let settledContent = UnifiedSuggestionsContentResolver.resolve(settled, previous: pendingContent)

        XCTAssertEqual(settledContent, .list(.duckAI))
        XCTAssertFalse(showsEmbeddedLegacyContent(settledContent))

        let cleared = UnifiedSuggestionsContentResolver.resolve(inputs(mode: .aiChat, hasRecents: true), previous: settledContent)
        XCTAssertTrue(showsEmbeddedLegacyContent(cleared))
        XCTAssertEqual(chromePlacement(mode: .aiChat, showsSyncPromo: true).escapeHatch, .embedded)
    }

    private func chromePlacement(usesRedesign: Bool = false,
                                 showsRedesignedSearchModules: Bool = false,
                                 mode: TextEntryMode,
                                 isTyping: Bool = false,
                                 isFireTab: Bool = false,
                                 hasEscapeHatch: Bool = true,
                                 showsSyncPromo: Bool = false) -> (escapeHatch: FocusedContentPlacement, syncPromo: FocusedContentPlacement) {
        UnifiedSuggestionsContentResolver.resolveChromePlacement(usesRedesignedNewTabPageLayout: usesRedesign,
                                                                showsRedesignedSearchModules: showsRedesignedSearchModules,
                                                                mode: mode,
                                                                isTyping: isTyping,
                                                                isFireTab: isFireTab,
                                                                hasEscapeHatch: hasEscapeHatch,
                                                                showsSyncPromo: showsSyncPromo)
    }

    private func showsEmbeddedLegacyContent(_ content: UnifiedSuggestionsContentKind,
                                            usesRedesign: Bool = false,
                                            isFireTab: Bool = false) -> Bool {
        UnifiedSuggestionsContentResolver.showsEmbeddedLegacyContent(usesRedesignedNewTabPageLayout: usesRedesign,
                                                                    isFireTab: isFireTab,
                                                                    content: content)
    }
}
