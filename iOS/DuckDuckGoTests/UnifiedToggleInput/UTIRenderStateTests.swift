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
        sut = UnifiedToggleInputCoordinator(host: .omnibar, isToggleEnabled: true)
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
        XCTAssertFalse(state.isFloatingReturnKeyVisible)

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

    func test_aiTabExpanded_search_emptyText_hidesContent() {
        // Toggling to search on a chat tab without typing keeps the chat web view visible —
        // suggestions only take over once there's text to suggest against.
        sut.showExpanded(inputMode: .search)
        let state = sut.computeRenderState()
        XCTAssertFalse(state.isContentVisible)
    }

    func test_aiTabExpanded_search_withText_showsContent() {
        sut.showExpanded(inputMode: .search)
        sut.setText("hello")
        let state = sut.computeRenderState()
        XCTAssertTrue(state.isContentVisible)
    }

    func test_aiTabExpanded_search_afterDismissCleanupWithDraft_hidesContent() {
        // Dismiss-cleanup scrubs the visible input (`textState = .empty`) but keeps `currentText`
        // as a per-tab draft. Toggling to Search on a Duck.ai tab afterwards must still hide
        // content — the field is visually empty even though the draft persists.
        sut.activateFromOmnibar(inputMode: .search)
        sut.setText("draft")
        sut.clearText()
        sut.showExpanded(inputMode: .search)
        let state = sut.computeRenderState()
        XCTAssertFalse(state.isContentVisible)
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
    }

    func test_omnibarActive_bottomPosition_setsOmnibarProperties() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        let state = sut.computeRenderState()
        XCTAssertEqual(state.cardPosition, .bottom)
        XCTAssertFalse(state.usesOmnibarMargins)
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

    // MARK: - Floating Return Key

    func test_floatingReturnKey_visibleForOmnibarActiveTopAIChat() {
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .top)
        sut.setText("how")
        let state = sut.computeRenderState()
        XCTAssertTrue(state.isFloatingReturnKeyVisible)
    }

    func test_floatingReturnKey_hiddenForEmptyNewAIChat() {
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .top)
        let state = sut.computeRenderState()
        XCTAssertFalse(state.isFloatingReturnKeyVisible)
    }

    func test_floatingReturnKey_hiddenForSearchModeWithText() {
        sut.activateFromOmnibar(inputMode: .search, cardPosition: .top)
        sut.setText("how")
        let state = sut.computeRenderState()
        XCTAssertFalse(state.isFloatingReturnKeyVisible)
    }

    func test_floatingReturnKey_visibleForBottomPosition() {
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)
        sut.setText("how")
        let state = sut.computeRenderState()
        XCTAssertTrue(state.isFloatingReturnKeyVisible)
    }

    func test_floatingReturnKey_hiddenForOmnibarInactive() {
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)
        sut.setText("how")
        sut.updateOmnibarInputVisibility(false)
        let state = sut.computeRenderState()
        XCTAssertFalse(state.isFloatingReturnKeyVisible)
    }

    func test_floatingReturnKey_restoresReturnKeyAfterOmnibarReactivates() {
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)
        sut.setText("how")
        sut.updateOmnibarInputVisibility(false)
        sut.updateOmnibarInputVisibility(true)
        let state = sut.computeRenderState()

        XCTAssertTrue(state.isFloatingReturnKeyVisible)
    }

    func test_floatingReturnKey_hiddenForAITabNewChatWithText() {
        sut.showExpanded(inputMode: .aiChat)
        sut.setText("how")
        let state = sut.computeRenderState()
        XCTAssertFalse(state.isFloatingReturnKeyVisible)
    }

    func test_omnibarNewAIChat_submitsAIChatOnKeyboardReturn() {
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .top)
        XCTAssertTrue(sut.viewController.handler.submitsAIChatOnKeyboardReturn)
    }

    func test_aiTabNewChat_usesNormalKeyboardReturn() {
        sut.showExpanded(inputMode: .aiChat)
        XCTAssertFalse(sut.viewController.handler.submitsAIChatOnKeyboardReturn)
    }

    func test_omnibarSearch_doesNotUseFloatingReturnKeyOrKeyboardReturnSubmit() {
        sut.activateFromOmnibar(inputMode: .search, cardPosition: .top)
        sut.setText("how")
        let state = sut.computeRenderState()

        XCTAssertFalse(state.isFloatingReturnKeyVisible)
        XCTAssertFalse(sut.viewController.handler.submitsAIChatOnKeyboardReturn)
    }

    func test_deactivateToOmnibar_clearsNewPromptInputBehavior() {
        sut.activateFromOmnibar(inputMode: .aiChat, cardPosition: .bottom)
        sut.setText("how")
        XCTAssertTrue(sut.computeRenderState().isFloatingReturnKeyVisible)
        XCTAssertTrue(sut.viewController.handler.submitsAIChatOnKeyboardReturn)

        sut.deactivateToOmnibar()

        XCTAssertFalse(sut.computeRenderState().isFloatingReturnKeyVisible)
        XCTAssertFalse(sut.viewController.handler.submitsAIChatOnKeyboardReturn)
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

    // MARK: - Host-Driven Render Flags

    func test_omnibarHost_renderState_showsToggle() {
        sut.activateFromOmnibar()
        let state = sut.computeRenderState()
        XCTAssertTrue(state.cardLayout.showsToggle)
    }

    func test_contextualChatHost_renderState_hidesToggle_showsToolbar() {
        sut = UnifiedToggleInputCoordinator(host: .contextualChat, isToggleEnabled: false)
        sut.showExpanded()
        let state = sut.computeRenderState()
        XCTAssertFalse(state.cardLayout.showsToggle)
        XCTAssertTrue(state.cardLayout.showsToolbar)
    }

    func test_omnibarHost_aiTabExpanded_aiChat_toggleDisabled_stillShowsToolbar() {
        // Toggle-off on a Duck.ai tab must keep the AI-chat toolbar so the user retains
        // the model selector / attachments / send affordances.
        sut = UnifiedToggleInputCoordinator(host: .omnibar, isToggleEnabled: false)
        sut.showExpanded(inputMode: .aiChat)
        let state = sut.computeRenderState()
        XCTAssertFalse(state.cardLayout.showsToggle)
        XCTAssertTrue(state.cardLayout.showsToolbar)
    }

    func test_omnibarHost_aiTabExpanded_aiChat_disablingToggleAfterShow_keepsToolbar() {
        // Live disable path — coordinator must compute showsToolbar=true here so the live update
        // doesn't strip the AI toolbar (the view's local rule alone can't see isAITabState).
        sut.showExpanded(inputMode: .aiChat)
        sut.updateToggleEnabled(false)
        let state = sut.computeRenderState()
        XCTAssertFalse(state.cardLayout.showsToggle)
        XCTAssertTrue(state.cardLayout.showsToolbar)
    }
}
