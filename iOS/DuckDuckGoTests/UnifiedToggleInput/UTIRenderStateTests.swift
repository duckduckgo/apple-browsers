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

        XCTAssertFalse(state.inactiveAppearance)
    }

    // MARK: - AI Tab Collapsed

    func test_aiTabCollapsed_renderState() {
        sut.showCollapsed()
        let state = sut.computeRenderState()
        XCTAssertTrue(state.isInputVisible)
        XCTAssertFalse(state.isContentVisible)
        XCTAssertFalse(state.isExpanded)

    }

    // MARK: - AI Tab Expanded

    func test_aiTabExpanded_aiChat_hidesContent() {
        sut.showExpanded(inputMode: .aiChat)
        let state = sut.computeRenderState()
        XCTAssertTrue(state.isInputVisible)
        XCTAssertFalse(state.isContentVisible)
        XCTAssertTrue(state.isExpanded)

    }

    func test_aiTabExpanded_search_showsContent() {
        sut.showExpanded(inputMode: .search)
        let state = sut.computeRenderState()
        XCTAssertTrue(state.isContentVisible)

    }

    func test_aiTabExpanded_search_keyboardHidden_showsInactive() {
        sut.showExpanded(inputMode: .search)
        sut.updateOmnibarInputVisibility(false)
        let state = sut.computeRenderState()
        XCTAssertTrue(state.inactiveAppearance)

    }

    func test_aiTabExpanded_search_keyboardShown_showsActive() {
        sut.showExpanded(inputMode: .search)
        sut.updateOmnibarInputVisibility(false)
        sut.updateOmnibarInputVisibility(true)
        let state = sut.computeRenderState()
        XCTAssertFalse(state.inactiveAppearance)

    }

    func test_aiTabExpanded_search_afterPriorKeyboardDismiss_startsActive() {
        sut.showExpanded(inputMode: .search)
        sut.updateOmnibarInputVisibility(false)
        sut.showCollapsed()
        sut.showExpanded(inputMode: .search)
        let state = sut.computeRenderState()
        XCTAssertFalse(state.inactiveAppearance)

    }

    // MARK: - Omnibar Active

    func test_omnibarActive_renderState() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        let state = sut.computeRenderState()
        XCTAssertTrue(state.isInputVisible)
        XCTAssertTrue(state.isContentVisible)
        XCTAssertTrue(state.isExpanded)

        XCTAssertFalse(state.inactiveAppearance)
    }

    func test_omnibarActive_topPosition_setsOmnibarProperties() {
        sut.activateFromOmnibar(cardPosition: .top)
        let state = sut.computeRenderState()
        XCTAssertEqual(state.cardPosition, .top)
        XCTAssertTrue(state.usesOmnibarMargins)
        XCTAssertTrue(state.isToolbarSubmitHidden)
    }

    func test_omnibarActive_bottomPosition_setsOmnibarProperties() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        let state = sut.computeRenderState()
        XCTAssertEqual(state.cardPosition, .bottom)
        XCTAssertFalse(state.usesOmnibarMargins)
        XCTAssertFalse(state.isToolbarSubmitHidden)
    }

    // MARK: - Omnibar Inactive

    func test_omnibarInactive_renderState() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        sut.updateOmnibarInputVisibility(false)
        let state = sut.computeRenderState()
        XCTAssertTrue(state.isInputVisible)
        XCTAssertTrue(state.isContentVisible)

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
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)
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

    // MARK: - Inline / Floating Dismiss

    func test_inlineDismiss_activeAtTopWhenExpanded() {
        sut.activateFromOmnibar(cardPosition: .top)
        XCTAssertTrue(sut.computeRenderState().isInlineDismissActive)
    }

    func test_inlineDismiss_hiddenAtBottomPosition() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        XCTAssertFalse(sut.computeRenderState().isInlineDismissActive)
    }

    func test_inlineDismiss_hiddenWhenToggleDisabled() {
        sut = UnifiedToggleInputCoordinator(isToggleEnabled: false)
        sut.activateFromOmnibar(cardPosition: .top)
        XCTAssertFalse(sut.computeRenderState().isInlineDismissActive)
    }

    func test_floatingDismiss_visibleAtTopWhenToggleDisabled() {
        // Regression: with the toggle setting off, the card has no top row for the inline X;
        // the floating X must still appear so users can dismiss the omnibar session.
        sut = UnifiedToggleInputCoordinator(isToggleEnabled: false)
        sut.activateFromOmnibar(cardPosition: .top)
        XCTAssertTrue(sut.computeRenderState().isFloatingDismissVisible)
    }

    func test_inlineDismiss_hiddenWhenCollapsed() {
        sut.showCollapsed()
        XCTAssertFalse(sut.computeRenderState().isInlineDismissActive)
    }

    func test_floatingDismiss_visibleAtBottomWithContent() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        XCTAssertTrue(sut.computeRenderState().isFloatingDismissVisible)
    }

    func test_floatingDismiss_hiddenAtTopWhenInlineDismissActive() {
        sut.activateFromOmnibar(cardPosition: .top)
        XCTAssertFalse(sut.computeRenderState().isFloatingDismissVisible)
    }

    func test_floatingDismiss_hiddenWhenContentHidden() {
        XCTAssertFalse(sut.computeRenderState().isFloatingDismissVisible)
    }
}
