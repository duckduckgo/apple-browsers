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
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        sut = UnifiedToggleInputCoordinator(isToggleEnabled: true)
        mockDelegate = MockUnifiedToggleInputDelegate()
        sut.delegate = mockDelegate
    }

    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        mockDelegate = nil
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

    func test_dismissTap_deactivatesInlineEditing() {
        sut.activateInlineEditing()
        XCTAssertTrue(sut.isInlineEditingSession)

        sut.unifiedToggleInputVCDidTapDismiss(sut.viewController)
        XCTAssertEqual(sut.displayState, .hidden)
        XCTAssertFalse(sut.isInlineEditingSession)
    }

    // MARK: - Inline Editing Lifecycle

    func test_activateInlineEditing_setsDisplayState() {
        sut.activateInlineEditing()
        XCTAssertEqual(sut.displayState, .inline(.active))
        XCTAssertTrue(sut.isInlineEditingSession)
    }

    func test_activateInlineEditing_emitsIntent() {
        let exp = expectation(description: "showInlineEditing intent emitted")
        sut.intentPublisher
            .sink { intent in
                if case .showInlineEditing = intent { exp.fulfill() }
            }
            .store(in: &cancellables)

        sut.activateInlineEditing()
        waitForExpectations(timeout: 1)
    }

    func test_activateInlineEditing_defaultsToSearchMode() {
        sut.activateInlineEditing()
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_activateInlineEditing_respectsRequestedMode() {
        sut.activateInlineEditing(inputMode: .aiChat)
        XCTAssertEqual(sut.inputMode, .aiChat)
    }

    func test_activateInlineEditing_withPrefilledText_setsPrefilledState() {
        sut.activateInlineEditing(prefilledText: "test query")
        XCTAssertEqual(sut.textState, .prefilledSelected)
    }

    func test_activateInlineEditing_toggleDisabled_forcesSearchMode() {
        sut.updateToggleEnabled(false)
        sut.activateInlineEditing(inputMode: .aiChat)
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_deactivateInlineEditing_resetsState() {
        sut.activateInlineEditing(prefilledText: "test")
        sut.deactivateInlineEditing()

        XCTAssertEqual(sut.displayState, .hidden)
        XCTAssertEqual(sut.textState, .empty)
        XCTAssertFalse(sut.isInlineEditingSession)
    }

    func test_deactivateInlineEditing_emitsIntent() {
        sut.activateInlineEditing()

        let exp = expectation(description: "hideInlineEditing intent emitted")
        sut.intentPublisher
            .sink { if $0 == .hideInlineEditing { exp.fulfill() } }
            .store(in: &cancellables)

        sut.deactivateInlineEditing()
        waitForExpectations(timeout: 1)
    }

    func test_deactivateInlineEditing_guardsWhenNotActive() {
        let exp = expectation(description: "no intent emitted")
        exp.isInverted = true
        sut.intentPublisher
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        sut.deactivateInlineEditing()
        waitForExpectations(timeout: 0.1)
    }

    // MARK: - Inline Editing Input Visibility

    func test_updateInlineEditingInputVisibility_activeToInactive() {
        sut.activateInlineEditing()

        sut.updateInlineEditingInputVisibility(false)

        XCTAssertEqual(sut.displayState, .inline(.inactive))
    }

    func test_updateInlineEditingInputVisibility_inactiveToActive() {
        sut.activateInlineEditing()
        sut.updateInlineEditingInputVisibility(false)

        sut.updateInlineEditingInputVisibility(true)

        XCTAssertEqual(sut.displayState, .inline(.active))
    }

    func test_updateInlineEditingInputVisibility_emitsInactiveIntent() {
        sut.activateInlineEditing()
        let exp = expectation(description: "showInlineInactive intent emitted")
        sut.intentPublisher
            .sink { if $0 == .showInlineInactive { exp.fulfill() } }
            .store(in: &cancellables)

        sut.updateInlineEditingInputVisibility(false)

        waitForExpectations(timeout: 1)
    }

    func test_updateInlineEditingInputVisibility_emitsActiveIntent() {
        sut.activateInlineEditing()
        sut.updateInlineEditingInputVisibility(false)
        let exp = expectation(description: "showInlineActive intent emitted")
        sut.intentPublisher
            .sink { if $0 == .showInlineActive { exp.fulfill() } }
            .store(in: &cancellables)

        sut.updateInlineEditingInputVisibility(true)

        waitForExpectations(timeout: 1)
    }

    func test_updateInlineEditingInputVisibility_ignoresWhenNotInline() {
        sut.showExpanded()
        let exp = expectation(description: "no intent emitted")
        exp.isInverted = true
        sut.intentPublisher
            .sink { _ in exp.fulfill() }
            .store(in: &cancellables)

        sut.updateInlineEditingInputVisibility(false)

        waitForExpectations(timeout: 0.1)
    }

    func test_deactivateInlineEditing_fromInactive_hidesInlineEditing() {
        sut.activateInlineEditing()
        sut.updateInlineEditingInputVisibility(false)

        sut.deactivateInlineEditing()

        XCTAssertEqual(sut.displayState, .hidden)
    }

    func test_isInlineEditingSession_trueForInactiveState() {
        sut.activateInlineEditing()
        sut.updateInlineEditingInputVisibility(false)

        XCTAssertEqual(sut.displayState, .inline(.inactive))
        XCTAssertTrue(sut.isInlineEditingSession)
    }

    func test_dismissInlineKeyboard_guardsWhenNotInlineActive() {
        sut.showExpanded()
        sut.dismissInlineKeyboard()
        XCTAssertEqual(sut.displayState, .aiTab(.expanded))
    }

    func test_dismissInlineKeyboard_guardsWhenInlineInactive() {
        sut.activateInlineEditing()
        sut.updateInlineEditingInputVisibility(false)
        sut.dismissInlineKeyboard()
        XCTAssertEqual(sut.displayState, .inline(.inactive))
    }

    func test_submitSearch_fromInlineInactive_deactivates() {
        sut.activateInlineEditing(inputMode: .search)
        sut.updateInlineEditingInputVisibility(false)

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

    func test_updateInputMode_emitsMode() {
        let exp = expectation(description: "modeChangePublisher emits")
        sut.modeChangePublisher
            .sink { XCTAssertEqual($0, .search); exp.fulfill() }
            .store(in: &cancellables)

        sut.updateInputMode(.search, animated: false)
        waitForExpectations(timeout: 1)
    }

    func test_updateInputMode_toggleDisabled_forcesSearch() {
        sut.updateToggleEnabled(false)
        sut.updateInputMode(.aiChat, animated: false)
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_syncInputModeFromExternalSource_setsMode() {
        sut.syncInputModeFromExternalSource(.search)
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_syncInputModeFromExternalSource_toggleDisabled_forcesSearch() {
        sut.updateToggleEnabled(false)
        sut.syncInputModeFromExternalSource(.aiChat)
        XCTAssertEqual(sut.inputMode, .search)
    }

    // MARK: - Toggle Enabled

    func test_updateToggleEnabled_setsFlag() {
        sut.updateToggleEnabled(false)
        XCTAssertFalse(sut.isToggleEnabled)
    }

    func test_updateToggleEnabled_false_forcesSearchModeWhenInline() {
        sut.activateInlineEditing(inputMode: .aiChat)
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

    // MARK: - Submit From Inline Editing

    func test_submitSearch_fromInlineEditing_deactivates() {
        sut.activateInlineEditing(inputMode: .search)
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "query", mode: .search)
        XCTAssertEqual(sut.displayState, .hidden)
        XCTAssertFalse(sut.isInlineEditingSession)
    }

    func test_submitAIChat_fromInlineEditing_deactivates() {
        sut.activateInlineEditing(inputMode: .aiChat)
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "prompt", mode: .aiChat)
        XCTAssertEqual(sut.displayState, .hidden)
        XCTAssertFalse(sut.isInlineEditingSession)
    }

    // MARK: - External Submission Handlers

    func test_handleExternalQuerySubmission_deactivatesInlineEditing() {
        sut.activateInlineEditing()
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

    func test_handleExternalPromptSubmission_deactivatesInlineEditing() {
        sut.activateInlineEditing()
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
}

// MARK: - Mock Delegate

@MainActor
private final class MockUnifiedToggleInputDelegate: UnifiedToggleInputDelegate {
    var submittedPrompt: String?
    var submittedQuery: String?
    var didRequestVoiceSearch = false

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String) { submittedPrompt = prompt }
    func unifiedToggleInputDidSubmitQuery(_ query: String) { submittedQuery = query }
    func unifiedToggleInputDidRequestVoiceSearch() { didRequestVoiceSearch = true }
}
