//
//  UnifiedToggleInputCoordinatorTests.swift
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

import AIChat
import Combine
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedToggleInputCoordinatorTests: XCTestCase {

    private var sut: UnifiedToggleInputCoordinator!
    private var mockDelegate: MockUnifiedToggleInputDelegate!
    private var mockPreferences: MockAIChatPreferences!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        mockPreferences = MockAIChatPreferences()
        sut = UnifiedToggleInputCoordinator(isToggleEnabled: true, preferences: mockPreferences)
        mockDelegate = MockUnifiedToggleInputDelegate()
        sut.delegate = mockDelegate
    }

    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        mockDelegate = nil
        mockPreferences = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func test_initialState() {
        XCTAssertEqual(sut.displayState, .hidden)
        XCTAssertEqual(sut.textState, .empty)
        XCTAssertEqual(sut.inputMode, .aiChat)
        XCTAssertFalse(sut.hasActiveChat)
    }

    // MARK: - Display State: showCollapsed

    func test_showCollapsed_setsDisplayState() {
        sut.showCollapsed()
        XCTAssertEqual(sut.displayState, .aiTab(.collapsed))
    }

    func test_showCollapsed_setsInputModeToAIChat() {
        sut.showExpanded(inputMode: .search)
        sut.showCollapsed()
        XCTAssertEqual(sut.inputMode, .aiChat)
    }

    func test_showCollapsed_deactivatesInput() {
        sut.showExpanded()
        sut.showCollapsed()
        XCTAssertFalse(sut.viewController.isInputExpanded)
    }

    func test_showCollapsed_emitsIntent() {
        let exp = expectation(description: "showCollapsed intent emitted")
        sut.intentPublisher
            .sink { if $0 == .showCollapsed { exp.fulfill() } }
            .store(in: &cancellables)

        sut.showCollapsed()
        waitForExpectations(timeout: 1)
    }

    // MARK: - Display State: showExpanded

    func test_showExpanded_setsDisplayState() {
        sut.showExpanded()
        XCTAssertEqual(sut.displayState, .aiTab(.expanded))
    }

    func test_showExpanded_emitsIntent() {
        let exp = expectation(description: "showExpanded intent emitted")
        sut.intentPublisher
            .sink { if $0 == .showExpanded { exp.fulfill() } }
            .store(in: &cancellables)

        sut.showExpanded()
        waitForExpectations(timeout: 1)
    }

    func test_showExpanded_setsInputMode() {
        sut.showExpanded(inputMode: .search)
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_showExpanded_setsExpandedOnVC() {
        sut.showExpanded()
        XCTAssertTrue(sut.viewController.isInputExpanded)
    }

    func test_showExpanded_setsInputModeOnVC() {
        sut.showExpanded(inputMode: .search)
        XCTAssertEqual(sut.viewController.inputMode, .search)
    }

    func test_showExpanded_withPrefilledText_setsTextStateToPrefilledSelected() {
        sut.showExpanded(prefilledText: "hello")
        XCTAssertEqual(sut.textState, .prefilledSelected)
    }

    func test_showExpanded_withEmptyPrefilledText_doesNotSetPrefilledState() {
        sut.showExpanded(prefilledText: "")
        XCTAssertEqual(sut.textState, .empty)
    }

    func test_showExpanded_withNilPrefilledText_doesNotSetPrefilledState() {
        sut.showExpanded(prefilledText: nil)
        XCTAssertEqual(sut.textState, .empty)
    }

    // MARK: - Display State: hide

    func test_hide_setsDisplayState() {
        sut.showExpanded()
        sut.hide()
        XCTAssertEqual(sut.displayState, .hidden)
    }

    func test_hide_collapsesVC() {
        sut.showExpanded()
        sut.hide()
        XCTAssertFalse(sut.viewController.isInputExpanded)
    }

    func test_hide_emitsIntent() {
        let exp = expectation(description: "hide intent emitted")
        sut.intentPublisher
            .sink { if $0 == .hide { exp.fulfill() } }
            .store(in: &cancellables)

        sut.hide()
        waitForExpectations(timeout: 1)
    }

    // MARK: - Tab Binding

    func test_bindToTab_setsHasActiveChat() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript)
        XCTAssertTrue(sut.hasActiveChat)
    }

    func test_unbind_clearsHasActiveChat() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript)
        sut.unbind()
        XCTAssertFalse(sut.hasActiveChat)
    }

    func test_bindToTab_sameScript_remainsActive() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript)
        sut.bindToTab(userScript)
        XCTAssertTrue(sut.hasActiveChat)
    }

    func test_unbind_resetsAIChatStatus() {
        sut.aiChatStatus = .streaming
        sut.unbind()
        XCTAssertEqual(sut.aiChatStatus, .unknown)
    }

    func test_unbind_resetsAIChatInputBoxVisibility() {
        sut.aiChatInputBoxVisibility = .visible
        sut.unbind()
        XCTAssertEqual(sut.aiChatInputBoxVisibility, .unknown)
    }

    // MARK: - VC Delegate: Collapsed Tap

    func test_collapsedTap_setsExpandedState() {
        sut.unifiedToggleInputVCDidTapWhileCollapsed(sut.viewController)
        XCTAssertEqual(sut.displayState, .aiTab(.expanded))
    }

    func test_collapsedTap_usesAIChatMode() {
        sut.unifiedToggleInputVCDidTapWhileCollapsed(sut.viewController)
        XCTAssertEqual(sut.inputMode, .aiChat)
    }

    // MARK: - VC Delegate: Text Change

    func test_didChangeText_nonEmpty_setsUserTyped() {
        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "hello")
        XCTAssertEqual(sut.textState, .userTyped)
    }

    func test_didChangeText_empty_setsEmpty() {
        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "hello")
        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "")
        XCTAssertEqual(sut.textState, .empty)
    }

    func test_didChangeText_publishesText() {
        let exp = expectation(description: "textChangePublisher emits text")
        sut.textChangePublisher
            .sink { XCTAssertEqual($0, "hello"); exp.fulfill() }
            .store(in: &cancellables)

        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "hello")
        waitForExpectations(timeout: 1)
    }

    func test_didChangeMode_updatesInputMode() {
        sut.unifiedToggleInputVC(sut.viewController, didChangeMode: .search)
        XCTAssertEqual(sut.inputMode, .search)
    }

    // MARK: - VC Delegate: Submit — Search Mode

    func test_submitSearch_callsDelegateQueryMethod() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "ducks", mode: .search)
        XCTAssertEqual(mockDelegate.submittedQuery, "ducks")
    }

    func test_submitSearch_publishesToDidSubmitQuery() {
        let exp = expectation(description: "didSubmitQuery fires")
        sut.didSubmitQuery
            .sink { XCTAssertEqual($0, "ducks"); exp.fulfill() }
            .store(in: &cancellables)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "ducks", mode: .search)
        waitForExpectations(timeout: 1)
    }

    func test_submitSearch_doesNotCallDelegatePromptMethod() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "ducks", mode: .search)
        XCTAssertNil(mockDelegate.submittedPrompt)
    }

    // MARK: - VC Delegate: Submit — AI Chat Mode, No Bound Script

    func test_submitAIChat_noBoundScript_callsDelegatePromptMethod() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello AI", mode: .aiChat)
        XCTAssertEqual(mockDelegate.submittedPrompt, "hello AI")
    }

    func test_submitAIChat_noBoundScript_collapses() {
        sut.showExpanded()
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertEqual(sut.displayState, .aiTab(.collapsed))
    }

    func test_submitAIChat_noBoundScript_clearsTextState() {
        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "hello")
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertEqual(sut.textState, .empty)
    }

    // MARK: - VC Delegate: Submit — AI Chat Mode, With Bound Script

    func test_submitAIChat_withBoundScript_publishesToDidSubmitPrompt() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript)

        let exp = expectation(description: "didSubmitPrompt fires")
        sut.didSubmitPrompt
            .sink { XCTAssertEqual($0, "hello AI"); exp.fulfill() }
            .store(in: &cancellables)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello AI", mode: .aiChat)
        waitForExpectations(timeout: 1)
    }

    func test_submitAIChat_withBoundScript_doesNotCallDelegatePromptMethod() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertNil(mockDelegate.submittedPrompt)
    }

    func test_submitAIChat_withBoundScript_collapses() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript)
        sut.showExpanded()

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertEqual(sut.displayState, .aiTab(.collapsed))
    }

    // MARK: - VC Delegate: Voice

    func test_voiceTap_callsDelegateVoiceMethod() {
        sut.unifiedToggleInputVCDidTapVoice(sut.viewController)
        XCTAssertTrue(mockDelegate.didRequestVoiceSearch)
    }

    // MARK: - VC Delegate: Dismiss

    func test_dismissTap_deactivatesOmnibarEditing() {
        sut.activateFromOmnibar()
        XCTAssertTrue(sut.isOmnibarSession)

        sut.unifiedToggleInputVCDidTapDismiss(sut.viewController)
        XCTAssertEqual(sut.displayState, .hidden)
        XCTAssertFalse(sut.isOmnibarSession)
    }

    // MARK: - Omnibar Editing Lifecycle

    func test_activateFromOmnibar_setsDisplayState() {
        sut.activateFromOmnibar()
        XCTAssertEqual(sut.displayState, .omnibar(.active))
        XCTAssertTrue(sut.isOmnibarSession)
    }

    func test_activateFromOmnibar_emitsIntent() {
        let exp = expectation(description: "showOmnibarEditing intent emitted")
        sut.intentPublisher
            .sink { intent in
                if case .showOmnibarEditing = intent { exp.fulfill() }
            }
            .store(in: &cancellables)

        sut.activateFromOmnibar()
        waitForExpectations(timeout: 1)
    }

    func test_activateFromOmnibar_defaultsToSearchMode() {
        sut.activateFromOmnibar()
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_activateFromOmnibar_respectsRequestedMode() {
        sut.activateFromOmnibar(inputMode: .aiChat)
        XCTAssertEqual(sut.inputMode, .aiChat)
    }

    func test_activateFromOmnibar_withPrefilledText_setsPrefilledState() {
        sut.activateFromOmnibar(prefilledText: "test query")
        XCTAssertEqual(sut.textState, .prefilledSelected)
    }

    func test_activateFromOmnibar_toggleDisabled_forcesSearchMode() {
        sut.updateToggleEnabled(false)
        sut.activateFromOmnibar(inputMode: .aiChat)
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_activateFromOmnibar_topPosition_setsVCProperties() {
        sut.activateFromOmnibar(cardPosition: .top)
        XCTAssertEqual(sut.viewController.cardPosition, .top)
        XCTAssertTrue(sut.viewController.usesOmnibarMargins)
        XCTAssertTrue(sut.viewController.showsDismissButton)
        XCTAssertTrue(sut.viewController.isToolbarSubmitHidden)
    }

    func test_activateFromOmnibar_bottomPosition_setsVCProperties() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        XCTAssertEqual(sut.viewController.cardPosition, .bottom)
        XCTAssertFalse(sut.viewController.usesOmnibarMargins)
        XCTAssertFalse(sut.viewController.showsDismissButton)
        XCTAssertFalse(sut.viewController.isToolbarSubmitHidden)
    }

    func test_activateFromOmnibar_setsExpandedTrue() {
        sut.activateFromOmnibar()
        XCTAssertTrue(sut.viewController.isInputExpanded)
    }

    func test_deactivateToOmnibar_resetsVCProperties() {
        sut.activateFromOmnibar(cardPosition: .top)
        sut.deactivateToOmnibar()

        XCTAssertEqual(sut.viewController.cardPosition, .bottom)
        XCTAssertFalse(sut.viewController.usesOmnibarMargins)
        XCTAssertFalse(sut.viewController.showsDismissButton)
        XCTAssertFalse(sut.viewController.isToolbarSubmitHidden)
        XCTAssertFalse(sut.viewController.isInputExpanded)
    }

    func test_deactivateToOmnibar_resetsState() {
        sut.activateFromOmnibar(prefilledText: "test")
        sut.deactivateToOmnibar()

        XCTAssertEqual(sut.displayState, .hidden)
        XCTAssertEqual(sut.textState, .empty)
        XCTAssertFalse(sut.isOmnibarSession)
    }

    func test_deactivateToOmnibar_emitsIntent() {
        sut.activateFromOmnibar()

        let exp = expectation(description: "hideOmnibarEditing intent emitted")
        sut.intentPublisher
            .sink { if $0 == .hideOmnibarEditing { exp.fulfill() } }
            .store(in: &cancellables)

        sut.deactivateToOmnibar()
        waitForExpectations(timeout: 1)
    }

    func test_deactivateToOmnibar_guardsWhenNotActive() {
        let exp = expectation(description: "no intent emitted")
        exp.isInverted = true
        sut.intentPublisher
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        sut.deactivateToOmnibar()
        waitForExpectations(timeout: 0.1)
    }

    // MARK: - Omnibar Editing Input Visibility

    func test_updateOmnibarInputVisibility_activeToInactive() {
        sut.activateFromOmnibar()

        sut.updateOmnibarInputVisibility(false)

        XCTAssertEqual(sut.displayState, .omnibar(.inactive))
    }

    func test_updateOmnibarInputVisibility_inactiveToActive() {
        sut.activateFromOmnibar()
        sut.updateOmnibarInputVisibility(false)

        sut.updateOmnibarInputVisibility(true)

        XCTAssertEqual(sut.displayState, .omnibar(.active))
    }

    func test_updateOmnibarInputVisibility_emitsInactiveIntent() {
        sut.activateFromOmnibar()
        let exp = expectation(description: "showOmnibarInactive intent emitted")
        sut.intentPublisher
            .sink { if $0 == .showOmnibarInactive { exp.fulfill() } }
            .store(in: &cancellables)

        sut.updateOmnibarInputVisibility(false)

        waitForExpectations(timeout: 1)
    }

    func test_updateOmnibarInputVisibility_emitsActiveIntent() {
        sut.activateFromOmnibar()
        sut.updateOmnibarInputVisibility(false)
        let exp = expectation(description: "showOmnibarActive intent emitted")
        sut.intentPublisher
            .sink { if $0 == .showOmnibarActive { exp.fulfill() } }
            .store(in: &cancellables)

        sut.updateOmnibarInputVisibility(true)

        waitForExpectations(timeout: 1)
    }

    func test_updateOmnibarInputVisibility_ignoresWhenNotOmnibar() {
        sut.showExpanded()
        let exp = expectation(description: "no intent emitted")
        exp.isInverted = true
        sut.intentPublisher
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        sut.updateOmnibarInputVisibility(false)

        waitForExpectations(timeout: 0.1)
    }

    func test_deactivateToOmnibar_fromInactive_hidesOmnibarEditing() {
        sut.activateFromOmnibar()
        sut.updateOmnibarInputVisibility(false)

        sut.deactivateToOmnibar()

        XCTAssertEqual(sut.displayState, .hidden)
    }

    func test_isOmnibarSession_trueForInactiveState() {
        sut.activateFromOmnibar()
        sut.updateOmnibarInputVisibility(false)

        XCTAssertEqual(sut.displayState, .omnibar(.inactive))
        XCTAssertTrue(sut.isOmnibarSession)
    }

    func test_dismissOmnibarKeyboard_guardsWhenNotOmnibarActive() {
        sut.showExpanded()
        sut.dismissOmnibarKeyboard()
        XCTAssertEqual(sut.displayState, .aiTab(.expanded))
    }

    func test_dismissOmnibarKeyboard_guardsWhenOmnibarInactive() {
        sut.activateFromOmnibar()
        sut.updateOmnibarInputVisibility(false)
        sut.dismissOmnibarKeyboard()
        XCTAssertEqual(sut.displayState, .omnibar(.inactive))
    }

    func test_submitSearch_fromOmnibarInactive_deactivates() {
        sut.activateFromOmnibar(inputMode: .search)
        sut.updateOmnibarInputVisibility(false)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "query", mode: .search)

        XCTAssertEqual(sut.displayState, .hidden)
    }

    // MARK: - Content View Controller Ownership

    func test_contentViewController_createdOnInit() {
        XCTAssertNotNil(sut.contentViewController)
    }

    // MARK: - Input Mode Management

    func test_updateInputMode_setsMode() {
        sut.updateInputMode(.search, animated: false)
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_updateInputMode_onlyUpdatesInputMode_doesNotApplyFullConfig() {
        sut.showExpanded(inputMode: .aiChat)
        let expandedBefore = sut.viewController.isInputExpanded
        let modeBefore = sut.viewController.inputMode

        sut.updateInputMode(.search, animated: false)

        XCTAssertEqual(sut.viewController.inputMode, .search, "inputMode should update")
        XCTAssertNotEqual(modeBefore, .search, "precondition: mode was different before")
        XCTAssertEqual(sut.viewController.isInputExpanded, expandedBefore, "expansion state should not change")
    }

    func test_syncInputModeFromExternalSource_onlyUpdatesInputMode_doesNotApplyFullConfig() {
        sut.showExpanded(inputMode: .aiChat)
        let expandedBefore = sut.viewController.isInputExpanded

        sut.syncInputModeFromExternalSource(.search)

        XCTAssertEqual(sut.viewController.inputMode, .search, "inputMode should update")
        XCTAssertEqual(sut.viewController.isInputExpanded, expandedBefore, "expansion state should not change")
    }

    func test_updateInputMode_emitsMode() {
        let exp = expectation(description: "modeChangePublisher emits")
        sut.modeChangePublisher
            .sink { XCTAssertEqual($0, .search); exp.fulfill() }
            .store(in: &cancellables)

        sut.updateInputMode(.search, animated: false)
        waitForExpectations(timeout: 1)
    }

    func test_updateInputMode_toggleDisabled_forcesSearchInOmnibarSession() {
        sut.activateFromOmnibar()
        sut.updateToggleEnabled(false)
        sut.updateInputMode(.aiChat, animated: false)
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_syncInputModeFromExternalSource_setsMode() {
        sut.syncInputModeFromExternalSource(.search)
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_syncInputModeFromExternalSource_toggleDisabled_forcesSearchInOmnibarSession() {
        sut.activateFromOmnibar()
        sut.updateToggleEnabled(false)
        sut.syncInputModeFromExternalSource(.aiChat)
        XCTAssertEqual(sut.inputMode, .search)
    }

    // MARK: - Toggle Enabled

    func test_updateToggleEnabled_setsFlag() {
        sut.updateToggleEnabled(false)
        XCTAssertFalse(sut.isToggleEnabled)
    }

    func test_updateToggleEnabled_false_forcesSearchModeWhenOmnibar() {
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.updateToggleEnabled(false)
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_updateToggleEnabled_noChangeIsNoOp() {
        let exp = expectation(description: "no mode change emitted")
        exp.isInverted = true
        sut.modeChangePublisher
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        sut.updateToggleEnabled(true)
        waitForExpectations(timeout: 0.1)
    }

    // MARK: - Submit From Omnibar Editing

    func test_submitSearch_fromOmnibarEditing_deactivates() {
        sut.activateFromOmnibar(inputMode: .search)
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "query", mode: .search)
        XCTAssertEqual(sut.displayState, .hidden)
        XCTAssertFalse(sut.isOmnibarSession)
    }

    func test_submitAIChat_fromOmnibarEditing_deactivates() {
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "prompt", mode: .aiChat)
        XCTAssertEqual(sut.displayState, .hidden)
        XCTAssertFalse(sut.isOmnibarSession)
    }

    // MARK: - External Submission Handlers

    func test_handleExternalQuerySubmission_deactivatesOmnibarEditing() {
        sut.activateFromOmnibar()
        sut.handleExternalQuerySubmission()
        XCTAssertEqual(sut.displayState, .hidden)
    }

    func test_handleExternalQuerySubmission_hidesAITab() {
        sut.showExpanded()
        sut.handleExternalQuerySubmission()
        XCTAssertEqual(sut.displayState, .hidden)
    }

    func test_handleExternalQuerySubmission_noOpWhenHidden() {
        sut.handleExternalQuerySubmission()
        XCTAssertEqual(sut.displayState, .hidden)
    }

    func test_handleExternalPromptSubmission_deactivatesOmnibarEditing() {
        sut.activateFromOmnibar()
        sut.handleExternalPromptSubmission()
        XCTAssertEqual(sut.displayState, .hidden)
    }

    func test_handleExternalPromptSubmission_collapsesAITab() {
        sut.showExpanded()
        sut.handleExternalPromptSubmission()
        XCTAssertEqual(sut.displayState, .aiTab(.collapsed))
    }

    func test_handleExternalPromptSubmission_noOpWhenHidden() {
        sut.handleExternalPromptSubmission()
        XCTAssertEqual(sut.displayState, .hidden)
    }

    // MARK: - Clear Text

    func test_clearText_resetsTextState() {
        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "hello")
        sut.clearText()
        XCTAssertEqual(sut.textState, .empty)
    }

    // MARK: - showCollapsed Resets Input Mode

    func test_showCollapsed_resetsInputModeToAIChat() {
        sut.showExpanded(inputMode: .search)
        XCTAssertEqual(sut.inputMode, .search)

        sut.showCollapsed()
        XCTAssertEqual(sut.inputMode, .aiChat)
    }

    // MARK: - VC Delegate: SearchGoTo

    func test_searchGoToTap_expandsInSearchMode() {
        sut.showCollapsed()
        sut.unifiedToggleInputVCDidTapSearchGoTo(sut.viewController)

        XCTAssertEqual(sut.displayState, .aiTab(.expanded))
        XCTAssertEqual(sut.inputMode, .search)
    }

    // MARK: - VC Delegate: Dismiss from AI Tab

    func test_dismissTap_fromAITab_collapsesInsteadOfDeactivating() {
        sut.showExpanded()
        sut.unifiedToggleInputVCDidTapDismiss(sut.viewController)

        XCTAssertEqual(sut.displayState, .aiTab(.collapsed))
        XCTAssertEqual(sut.inputMode, .aiChat)
    }

    // MARK: - AI Tab Search Inactive State

    func test_updateOmnibarInputVisibility_aiTabSearch_becomesInactiveOnHide() {
        sut.showExpanded(inputMode: .search)

        sut.updateOmnibarInputVisibility(false)

        XCTAssertEqual(sut.displayState, .aiTab(.expanded))
    }

    func test_updateOmnibarInputVisibility_aiTabSearch_becomesActiveOnShow() {
        sut.showExpanded(inputMode: .search)
        sut.updateOmnibarInputVisibility(false)

        sut.updateOmnibarInputVisibility(true)

        XCTAssertEqual(sut.displayState, .aiTab(.expanded))
    }

    func test_updateOmnibarInputVisibility_aiTabAIChat_isIgnored() {
        sut.showExpanded(inputMode: .aiChat)

        let exp = expectation(description: "no intent emitted")
        exp.isInverted = true
        sut.intentPublisher
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        sut.updateOmnibarInputVisibility(false)
        waitForExpectations(timeout: 0.1)
    }
    // MARK: - Stop Generating State

    func test_aiChatStatus_loading_setsIsGenerating() {
        sut.aiChatStatus = .loading
        let handler = sut.viewController.handler
        XCTAssertTrue(handler.isGenerating)
    }

    func test_aiChatStatus_streaming_setsIsGenerating() {
        sut.aiChatStatus = .streaming
        let handler = sut.viewController.handler
        XCTAssertTrue(handler.isGenerating)
    }

    func test_aiChatStatus_startStreamNewPrompt_setsIsGenerating() {
        sut.aiChatStatus = .startStreamNewPrompt
        let handler = sut.viewController.handler
        XCTAssertTrue(handler.isGenerating)
    }

    func test_aiChatStatus_ready_clearsIsGenerating() {
        sut.aiChatStatus = .streaming
        sut.aiChatStatus = .ready
        let handler = sut.viewController.handler
        XCTAssertFalse(handler.isGenerating)
    }

    func test_unbind_whileGenerating_clearsIsGenerating() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript)
        sut.aiChatStatus = .streaming
        sut.unbind()
        XCTAssertEqual(sut.aiChatStatus, .unknown)
    }

    func test_stopGeneratingTap_forwardsToDidPressStopGeneratingButton() {
        let exp = expectation(description: "didPressStopGeneratingButton fires")
        sut.didPressStopGeneratingButton
            .sink { exp.fulfill() }
            .store(in: &cancellables)

        sut.viewController.handler.stopGeneratingButtonTapped()
        waitForExpectations(timeout: 1)
    }

    // MARK: - Model Selection: persistedModelId

    func test_persistedModelId_returnsPreferencesValue() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.models = [makeModel(id: "gpt-5", access: true)]
        XCTAssertEqual(sut.persistedModelId, "gpt-5")
    }

    func test_persistedModelId_fallsBackToFirstAccessibleModel() {
        mockPreferences.selectedModelId = nil
        sut.models = [
            makeModel(id: "premium", access: false),
            makeModel(id: "free", access: true)
        ]
        XCTAssertEqual(sut.persistedModelId, "free")
    }

    func test_persistedModelId_fallsBackToNil() {
        mockPreferences.selectedModelId = nil
        sut.models = []
        XCTAssertNil(sut.persistedModelId)
    }

    // MARK: - Model Selection: updateSelectedModel

    func test_updateSelectedModel_persistsToPreferences() {
        sut.updateSelectedModel("gpt-5")
        XCTAssertEqual(mockPreferences.selectedModelId, "gpt-5")
    }

    // MARK: - Model Selection: supportsImageUpload

    func test_selectedModelSupportsImageUpload_returnsTrue_whenModelsEmpty() {
        sut.models = []
        XCTAssertTrue(sut.selectedModelSupportsImageUpload)
    }

    func test_selectedModelSupportsImageUpload_returnsFalse_whenSelectedModelDoesNot() {
        mockPreferences.selectedModelId = "no-images"
        sut.models = [makeModel(id: "no-images", access: true, supportsImageUpload: false)]
        XCTAssertFalse(sut.selectedModelSupportsImageUpload)
    }

    func test_selectedModelSupportsImageUpload_returnsTrue_whenSelectedModelDoes() {
        mockPreferences.selectedModelId = "has-images"
        sut.models = [makeModel(id: "has-images", access: true, supportsImageUpload: true)]
        XCTAssertTrue(sut.selectedModelSupportsImageUpload)
    }

    // MARK: - Submit passes modelId

    func test_submitAIChat_noBoundScript_passesModelIdToDelegate() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertEqual(mockDelegate.submittedModelId, "gpt-5")
    }

    func test_submitAIChat_noBoundScript_fallsBackToFirstAccessibleModel() {
        mockPreferences.selectedModelId = nil
        sut.models = [
            makeModel(id: "premium", access: false),
            makeModel(id: "free", access: true)
        ]
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertEqual(mockDelegate.submittedModelId, "free")
    }

    // MARK: - Model Chip Visibility

    func test_modelChip_visibleByDefault() {
        XCTAssertFalse(sut.hasSubmittedPrompt)
        XCTAssertFalse(sut.viewController.isModelChipHidden)
    }

    func test_modelChip_hiddenAfterPromptSubmit() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertTrue(sut.hasSubmittedPrompt)
        XCTAssertTrue(sut.viewController.isModelChipHidden)
    }

    func test_modelChip_visibleAfterNewChat() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        sut.startNewChat()
        XCTAssertFalse(sut.hasSubmittedPrompt)
        XCTAssertFalse(sut.viewController.isModelChipHidden)
    }

    func test_modelChip_hiddenWhenBindingWithExistingChat() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript, hasExistingChat: true)
        XCTAssertTrue(sut.hasSubmittedPrompt)
        XCTAssertTrue(sut.viewController.isModelChipHidden)
    }

    func test_modelChip_visibleWhenBindingWithNewChat() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript, hasExistingChat: false)
        XCTAssertFalse(sut.hasSubmittedPrompt)
        XCTAssertFalse(sut.viewController.isModelChipHidden)
    }

    func test_modelChip_visibleAfterUnbind() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertTrue(sut.viewController.isModelChipHidden)
        sut.unbind()
        XCTAssertFalse(sut.viewController.isModelChipHidden)
    }

    func test_modelChip_visibleAfterNewChatFollowingRestore() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript, hasExistingChat: true)
        XCTAssertTrue(sut.viewController.isModelChipHidden)
        sut.startNewChat()
        XCTAssertFalse(sut.viewController.isModelChipHidden)
    }

    func test_modelChip_notAffectedBySearchSubmit() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "query", mode: .search)
        XCTAssertFalse(sut.hasSubmittedPrompt)
        XCTAssertFalse(sut.viewController.isModelChipHidden)
    }

    // MARK: - Stale Model Selection

    func test_persistedModelId_clearedWhenModelRemoved() {
        mockPreferences.selectedModelId = "removed-model"
        mockPreferences.selectedModelShortName = "Removed"
        sut.models = [makeModel(id: "gpt-5", access: true), makeModel(id: "claude", access: true)]

        XCTAssertEqual(sut.persistedModelId, "gpt-5")
    }

    func test_persistedModelId_clearedWhenAccessLost() {
        mockPreferences.selectedModelId = "premium"
        sut.models = [makeModel(id: "premium", access: false), makeModel(id: "free", access: true)]

        XCTAssertEqual(sut.persistedModelId, "free")
    }

    func test_persistedModelId_noAccessibleModels_returnsNil() {
        mockPreferences.selectedModelId = "locked"
        sut.models = [makeModel(id: "locked", access: false)]

        XCTAssertNil(sut.persistedModelId)
    }

    // MARK: - Chip Label Persistence

    func test_updateSelectedModel_persistsShortName() {
        sut.models = [AIChatModel(id: "gpt-5", name: "GPT-5", shortName: "G5", provider: .openAI, supportsImageUpload: false, entityHasAccess: true)]
        sut.updateSelectedModel("gpt-5")

        XCTAssertEqual(mockPreferences.selectedModelShortName, "G5")
    }

    func test_resolveModels_emptyAccessTier_fallsBackToEntityHasAccess() {
        let remote = AIChatRemoteModel(
            id: "gpt-4o-mini",
            name: "GPT-4o mini",
            provider: "openai",
            entityHasAccess: true,
            supportsImageUpload: false,
            supportedTools: [],
            accessTier: []
        )
        let models = UnifiedToggleInputCoordinator.resolveModels(from: [remote], userTier: .free)

        XCTAssertTrue(models[0].entityHasAccess)
    }

    func test_resolveModels_nonEmptyAccessTier_usesLocalResolution() {
        let remote = AIChatRemoteModel(
            id: "gpt-5",
            name: "GPT-5",
            provider: "openai",
            entityHasAccess: true,
            supportsImageUpload: false,
            supportedTools: [],
            accessTier: ["plus", "pro"]
        )
        let models = UnifiedToggleInputCoordinator.resolveModels(from: [remote], userTier: .free)

        XCTAssertFalse(models[0].entityHasAccess)
    }

    func test_chipLabel_shownFromCacheBeforeFetch() {
        mockPreferences.selectedModelShortName = "Cached Model"
        let coordinator = UnifiedToggleInputCoordinator(isToggleEnabled: true, preferences: mockPreferences)

        XCTAssertEqual(coordinator.viewController.modelName, "Cached Model")
        XCTAssertNil(coordinator.viewController.modelPickerMenu)
    }

    // MARK: - Helpers

    private func makeModel(id: String, access: Bool, supportsImageUpload: Bool = false) -> AIChatModel {
        AIChatModel(id: id, name: id, provider: .unknown, supportsImageUpload: supportsImageUpload, entityHasAccess: access)
    }
}

// MARK: - Mock Delegate

@MainActor
private final class MockUnifiedToggleInputDelegate: UnifiedToggleInputDelegate {
    var submittedPrompt: String?
    var submittedModelId: String?
    var submittedQuery: String?
    var didRequestVoiceSearch = false

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String, modelId: String?) {
        submittedPrompt = prompt
        submittedModelId = modelId
    }
    func unifiedToggleInputDidSubmitQuery(_ query: String) { submittedQuery = query }
    func unifiedToggleInputDidRequestVoiceSearch() { didRequestVoiceSearch = true }
}

private final class MockAIChatPreferences: AIChatPreferencesPersisting {
    var selectedModelId: String?
    var selectedModelShortName: String?
}
