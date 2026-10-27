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

    func test_idle_hatchIsEmbeddedInBothModesIncludingEmptyStates() {
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
            XCTAssertTrue(showsEmbeddedContent(content), "\(state)")
        }
    }

    func test_syncPromo_isEmbeddedOnlyInDuckAI() {
        XCTAssertEqual(chromePlacement(mode: .aiChat, showsSyncPromo: true).syncPromo, .embedded)
        XCTAssertEqual(chromePlacement(mode: .search, showsSyncPromo: true).syncPromo, .hidden)
        XCTAssertEqual(chromePlacement(mode: .aiChat, showsSyncPromo: false).syncPromo, .hidden)
    }

    func test_absentHatch_doesNotHideEligiblePromoOrEmptyScrollView() {
        let placement = chromePlacement(mode: .aiChat, hasEscapeHatch: false, showsSyncPromo: true)

        XCTAssertEqual(placement.escapeHatch, .hidden)
        XCTAssertEqual(placement.syncPromo, .embedded)
        XCTAssertTrue(showsEmbeddedContent(.logo))
    }

    func test_typing_hidesChromeInBothModesAndFlagStates() {
        for usesScrollableEscapeHatch in [false, true] {
            for usesRedesign in [false, true] {
                for mode in TextEntryMode.allCases {
                    let placement = chromePlacement(usesScrollableEscapeHatch: usesScrollableEscapeHatch,
                                                    usesRedesign: usesRedesign,
                                                    mode: mode, isTyping: true, showsSyncPromo: true)
                    let content = UnifiedSuggestionsContentResolver.resolve(inputs(mode: mode, isTyping: true), previous: nil)

                    XCTAssertEqual(placement.escapeHatch, .hidden)
                    XCTAssertEqual(placement.syncPromo, .hidden)
                    XCTAssertFalse(showsEmbeddedContent(content, usesScrollableEscapeHatch: usesScrollableEscapeHatch, usesRedesign: usesRedesign))
                }
            }
        }
    }

    func test_fireTab_hidesChromeAndEmbeddedContentInBothFlagStates() {
        for usesScrollableEscapeHatch in [false, true] {
            for usesRedesign in [false, true] {
                for mode in TextEntryMode.allCases {
                    let placement = chromePlacement(usesScrollableEscapeHatch: usesScrollableEscapeHatch,
                                                    usesRedesign: usesRedesign,
                                                    showsRedesignedSearchModules: true,
                                                    mode: mode, isFireTab: true, showsSyncPromo: true)

                    XCTAssertEqual(placement.escapeHatch, .hidden)
                    XCTAssertEqual(placement.syncPromo, .hidden)
                }
                for content: UnifiedSuggestionsContentKind in [.favorites, .logo, .list(.recents), .list(.search), .list(.duckAI)] {
                    XCTAssertFalse(showsEmbeddedContent(content, usesScrollableEscapeHatch: usesScrollableEscapeHatch,
                                                       usesRedesign: usesRedesign, showsRedesignedSearchModules: true, isFireTab: true))
                }
            }
        }
    }

    func test_flagOffLegacy_keepsHatchAndDuckAIPromoPinned() {
        for mode in TextEntryMode.allCases {
            let placement = chromePlacement(usesScrollableEscapeHatch: false, mode: mode, showsSyncPromo: true)

            XCTAssertEqual(placement.escapeHatch, .pinned)
            XCTAssertEqual(placement.syncPromo, mode == .aiChat ? .pinned : .hidden)
        }
    }

    func test_flagOffRedesign_preservesExistingSearchHatchAndPinsOtherChrome() {
        let modules = chromePlacement(usesScrollableEscapeHatch: false, usesRedesign: true,
                                      showsRedesignedSearchModules: true, mode: .search)
        let emptySearch = chromePlacement(usesScrollableEscapeHatch: false, usesRedesign: true, mode: .search)
        let duckAI = chromePlacement(usesScrollableEscapeHatch: false, usesRedesign: true, mode: .aiChat, showsSyncPromo: true)

        XCTAssertEqual(modules.escapeHatch, .embedded)
        XCTAssertEqual(modules.syncPromo, .hidden)
        XCTAssertEqual(emptySearch.escapeHatch, .pinned)
        XCTAssertEqual(duckAI.escapeHatch, .pinned)
        XCTAssertEqual(duckAI.syncPromo, .pinned)
    }

    func test_flagOff_usesOriginalFavoritesAndRecentsOwners() {
        for content: UnifiedSuggestionsContentKind in [.favorites, .logo, .list(.recents), .list(.search), .list(.duckAI)] {
            XCTAssertEqual(showsEmbeddedContent(content, usesScrollableEscapeHatch: false), content == .favorites)
            XCTAssertFalse(showsEmbeddedContent(content, usesScrollableEscapeHatch: false, usesRedesign: true))
        }
        XCTAssertTrue(showsEmbeddedContent(.favorites, usesScrollableEscapeHatch: false,
                                          usesRedesign: true, showsRedesignedSearchModules: true))
    }

    func test_flagOn_embedsIdleChromeInBothLayouts() {
        for usesRedesign in [false, true] {
            for mode in TextEntryMode.allCases {
                let placement = chromePlacement(usesRedesign: usesRedesign, mode: mode, showsSyncPromo: true)

                XCTAssertEqual(placement.escapeHatch, .embedded)
                XCTAssertEqual(placement.syncPromo, mode == .aiChat ? .embedded : .hidden)
            }
        }
    }

    func test_idleContent_includingEmptyAndRecents_usesScrollableContent() {
        for content: UnifiedSuggestionsContentKind in [.favorites, .logo, .list(.recents)] {
            XCTAssertTrue(showsEmbeddedContent(content))
        }
        for content: UnifiedSuggestionsContentKind in [.list(.search), .list(.duckAI)] {
            XCTAssertFalse(showsEmbeddedContent(content))
        }
    }

    func test_duckAITyping_pendingRecents_preserveTheirOwnerWithoutChromeUntilResultsArrive() {
        for usesScrollableEscapeHatch in [false, true] {
            for usesRedesign in [false, true] {
                let pending = inputs(mode: .aiChat, isTyping: true, hasRecents: true, resultsPending: true)
                let pendingContent = UnifiedSuggestionsContentResolver.resolve(pending, previous: .list(.recents))
                let placement = chromePlacement(usesScrollableEscapeHatch: usesScrollableEscapeHatch, usesRedesign: usesRedesign,
                                                mode: .aiChat, isTyping: pending.isTyping, showsSyncPromo: true)

                XCTAssertEqual(pendingContent, .list(.recents))
                XCTAssertEqual(showsEmbeddedContent(pendingContent, usesScrollableEscapeHatch: usesScrollableEscapeHatch,
                                                    usesRedesign: usesRedesign), usesScrollableEscapeHatch)
                XCTAssertEqual(placement.escapeHatch, .hidden)
                XCTAssertEqual(placement.syncPromo, .hidden)

                let settled = inputs(mode: .aiChat, isTyping: true, hasRecents: true, resultsPending: false)
                let settledContent = UnifiedSuggestionsContentResolver.resolve(settled, previous: pendingContent)

                XCTAssertEqual(settledContent, .list(.duckAI))
                XCTAssertFalse(showsEmbeddedContent(settledContent, usesScrollableEscapeHatch: usesScrollableEscapeHatch,
                                                     usesRedesign: usesRedesign))

                let cleared = UnifiedSuggestionsContentResolver.resolve(inputs(mode: .aiChat, hasRecents: true), previous: settledContent)
                XCTAssertEqual(showsEmbeddedContent(cleared, usesScrollableEscapeHatch: usesScrollableEscapeHatch,
                                                    usesRedesign: usesRedesign), usesScrollableEscapeHatch)
                XCTAssertEqual(chromePlacement(usesScrollableEscapeHatch: usesScrollableEscapeHatch, usesRedesign: usesRedesign,
                                               mode: .aiChat, showsSyncPromo: true).escapeHatch,
                               usesScrollableEscapeHatch ? .embedded : .pinned)
            }
        }
    }

    private func chromePlacement(usesScrollableEscapeHatch: Bool = true,
                                 usesRedesign: Bool = false,
                                 showsRedesignedSearchModules: Bool = false,
                                 mode: TextEntryMode,
                                 isTyping: Bool = false,
                                 isFireTab: Bool = false,
                                 hasEscapeHatch: Bool = true,
                                 showsSyncPromo: Bool = false) -> (escapeHatch: FocusedContentPlacement, syncPromo: FocusedContentPlacement) {
        UnifiedSuggestionsContentResolver.resolveChromePlacement(usesScrollableEscapeHatch: usesScrollableEscapeHatch,
                                                                usesRedesignedNewTabPageLayout: usesRedesign,
                                                                showsRedesignedSearchModules: showsRedesignedSearchModules,
                                                                mode: mode,
                                                                isTyping: isTyping,
                                                                isFireTab: isFireTab,
                                                                hasEscapeHatch: hasEscapeHatch,
                                                                showsSyncPromo: showsSyncPromo)
    }

    private func showsEmbeddedContent(_ content: UnifiedSuggestionsContentKind,
                                      usesScrollableEscapeHatch: Bool = true,
                                      usesRedesign: Bool = false,
                                      showsRedesignedSearchModules: Bool = false,
                                      isFireTab: Bool = false) -> Bool {
        UnifiedSuggestionsContentResolver.showsEmbeddedContent(usesScrollableEscapeHatch: usesScrollableEscapeHatch,
                                                              usesRedesignedNewTabPageLayout: usesRedesign,
                                                              showsRedesignedSearchModules: showsRedesignedSearchModules,
                                                              isFireTab: isFireTab,
                                                              content: content)
    }
}
