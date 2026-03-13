//
//  UTIRenderStateTests.swift
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

@MainActor
final class UTIRenderStateTests: XCTestCase {

    private var sut: UnifiedToggleInputCoordinator!

    override func setUp() {
        super.setUp()
        sut = UnifiedToggleInputCoordinator(isToggleEnabled: true)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Hidden

    func test_hidden_renderState() {
        let state = sut.computeRenderState()
        XCTAssertFalse(state.isInputVisible)
        XCTAssertFalse(state.isContentVisible)
        XCTAssertFalse(state.isExpanded)
        XCTAssertFalse(state.isFloatingSubmitVisible)
        XCTAssertEqual(state.headerDisplayMode, .hidden)
        XCTAssertFalse(state.inactiveAppearance)
    }

    // MARK: - AI Tab Collapsed

    func test_aiTabCollapsed_renderState() {
        sut.showCollapsed()
        let state = sut.computeRenderState()
        XCTAssertTrue(state.isInputVisible)
        XCTAssertFalse(state.isContentVisible)
        XCTAssertFalse(state.isExpanded)
        XCTAssertEqual(state.headerDisplayMode, .hidden)
    }

    // MARK: - AI Tab Expanded

    func test_aiTabExpanded_aiChat_onAITab_hidesContent() {
        sut.showExpanded(inputMode: .aiChat)
        let state = sut.computeRenderState(isOnAITab: true)
        XCTAssertTrue(state.isInputVisible)
        XCTAssertFalse(state.isContentVisible)
        XCTAssertTrue(state.isExpanded)
        XCTAssertEqual(state.headerDisplayMode, .hidden)
    }

    func test_aiTabExpanded_search_onAITab_showsContentAndHeader() {
        sut.showExpanded(inputMode: .search)
        let state = sut.computeRenderState(isOnAITab: true)
        XCTAssertTrue(state.isContentVisible)
        XCTAssertEqual(state.headerDisplayMode, .active)
    }

    func test_aiTabExpanded_aiChat_notOnAITab_showsContent() {
        sut.showExpanded(inputMode: .aiChat)
        let state = sut.computeRenderState(isOnAITab: false)
        XCTAssertTrue(state.isContentVisible)
        XCTAssertEqual(state.headerDisplayMode, .hidden)
    }

    func test_aiTabExpanded_search_onAITab_keyboardHidden_showsInactive() {
        sut.showExpanded(inputMode: .search)
        sut.updateOmnibarInputVisibility(false)
        let state = sut.computeRenderState(isOnAITab: true)
        XCTAssertTrue(state.inactiveAppearance)
        XCTAssertEqual(state.headerDisplayMode, .inactive)
    }

    func test_aiTabExpanded_search_onAITab_keyboardShown_showsActive() {
        sut.showExpanded(inputMode: .search)
        sut.updateOmnibarInputVisibility(false)
        sut.updateOmnibarInputVisibility(true)
        let state = sut.computeRenderState(isOnAITab: true)
        XCTAssertFalse(state.inactiveAppearance)
        XCTAssertEqual(state.headerDisplayMode, .active)
    }

    func test_aiTabExpanded_search_afterPriorKeyboardDismiss_startsActive() {
        sut.showExpanded(inputMode: .search)
        sut.updateOmnibarInputVisibility(false)
        sut.showCollapsed()
        sut.showExpanded(inputMode: .search)
        let state = sut.computeRenderState(isOnAITab: true)
        XCTAssertFalse(state.inactiveAppearance)
        XCTAssertEqual(state.headerDisplayMode, .active)
    }

    // MARK: - Omnibar Active

    func test_omnibarActive_renderState() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        let state = sut.computeRenderState()
        XCTAssertTrue(state.isInputVisible)
        XCTAssertTrue(state.isContentVisible)
        XCTAssertTrue(state.isExpanded)
        XCTAssertEqual(state.headerDisplayMode, .active)
        XCTAssertFalse(state.inactiveAppearance)
    }

    func test_omnibarActive_topPosition_setsOmnibarProperties() {
        sut.activateFromOmnibar(cardPosition: .top)
        let state = sut.computeRenderState()
        XCTAssertEqual(state.cardPosition, .top)
        XCTAssertTrue(state.usesOmnibarMargins)
        XCTAssertTrue(state.showsDismissButton)
        XCTAssertTrue(state.isToolbarSubmitHidden)
    }

    func test_omnibarActive_bottomPosition_setsOmnibarProperties() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        let state = sut.computeRenderState()
        XCTAssertEqual(state.cardPosition, .bottom)
        XCTAssertFalse(state.usesOmnibarMargins)
        XCTAssertFalse(state.showsDismissButton)
        XCTAssertFalse(state.isToolbarSubmitHidden)
    }

    // MARK: - Omnibar Inactive

    func test_omnibarInactive_renderState() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        sut.updateOmnibarInputVisibility(false)
        let state = sut.computeRenderState()
        XCTAssertTrue(state.isInputVisible)
        XCTAssertTrue(state.isContentVisible)
        XCTAssertEqual(state.headerDisplayMode, .inactive)
        XCTAssertTrue(state.inactiveAppearance)
    }

    func test_omnibarInactive_topPosition_noInactiveAppearance() {
        sut.activateFromOmnibar(cardPosition: .top)
        sut.updateOmnibarInputVisibility(false)
        let state = sut.computeRenderState()
        XCTAssertFalse(state.inactiveAppearance)
    }

    // MARK: - Floating Submit

    func test_floatingSubmit_visibleForOmnibarActiveTopAIChat() {
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .top)
        let state = sut.computeRenderState()
        XCTAssertTrue(state.isFloatingSubmitVisible)
    }

    func test_floatingSubmit_hiddenForSearchMode() {
        sut.activateFromOmnibar(inputMode: .search, cardPosition: .top)
        let state = sut.computeRenderState()
        XCTAssertFalse(state.isFloatingSubmitVisible)
    }

    func test_floatingSubmit_hiddenForBottomPosition() {
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)
        let state = sut.computeRenderState()
        XCTAssertFalse(state.isFloatingSubmitVisible)
    }

    func test_floatingSubmit_hiddenForOmnibarInactive() {
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .top)
        sut.updateOmnibarInputVisibility(false)
        let state = sut.computeRenderState()
        XCTAssertFalse(state.isFloatingSubmitVisible)
    }

    func test_floatingSubmit_hiddenForAITab() {
        sut.showExpanded(inputMode: .aiChat)
        let state = sut.computeRenderState()
        XCTAssertFalse(state.isFloatingSubmitVisible)
    }

    // MARK: - Content Input Mode

    func test_viewConfig_isTopBarPosition_trueForOmnibarTop() {
        sut.activateFromOmnibar(cardPosition: .top)
        let config = sut.computeRenderState().viewConfig
        XCTAssertTrue(config.isTopBarPosition)
    }

    func test_viewConfig_isTopBarPosition_falseForOmnibarBottom() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        let config = sut.computeRenderState().viewConfig
        XCTAssertFalse(config.isTopBarPosition)
    }

    func test_viewConfig_isTopBarPosition_falseForAITab() {
        sut.showExpanded()
        let config = sut.computeRenderState().viewConfig
        XCTAssertFalse(config.isTopBarPosition)
    }

    func test_contentInputMode_matchesCoordinatorInputMode() {
        sut.activateFromOmnibar(inputMode: .aiChat)
        let state = sut.computeRenderState()
        XCTAssertEqual(state.contentInputMode, .aiChat)
    }
}
