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
import Core
import UIKit
import UserScript
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedToggleInputCoordinatorTests: XCTestCase {

    private var sut: UnifiedToggleInputCoordinator!
    private var mockDelegate: MockUnifiedToggleInputDelegate!
    private var mockPreferences: MockAIChatPreferences!
    private var mockToggleModeStorage: MockToggleModeStorage!
    private var mockSubmissionMetrics: MockSwitchBarSubmissionMetrics!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        mockPreferences = MockAIChatPreferences()
        mockToggleModeStorage = MockToggleModeStorage()
        mockSubmissionMetrics = MockSwitchBarSubmissionMetrics()
        sut = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            preferences: mockPreferences,
            toggleModeStorage: mockToggleModeStorage,
            switchBarSubmissionMetrics: mockSubmissionMetrics
        )
        mockDelegate = MockUnifiedToggleInputDelegate()
        sut.delegate = mockDelegate
    }

    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        mockDelegate = nil
        mockPreferences = nil
        mockToggleModeStorage = nil
        mockSubmissionMetrics = nil
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
            .sink { if case .showCollapsed = $0 { exp.fulfill() } }
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
            .sink { if case .showExpanded = $0 { exp.fulfill() } }
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

    // MARK: - Model Picker (showModelPicker)

    func test_modelChip_isHidden_duringActiveChat_byDefault() {
        _ = sut.prepareExternalPromptSubmission()

        XCTAssertTrue(sut.hasSubmittedPrompt)
        XCTAssertTrue(sut.viewController.isModelChipHidden)
    }

    func test_presentModelPickerForActiveChat_revealsModelChip_duringActiveChat() {
        _ = sut.prepareExternalPromptSubmission()
        XCTAssertTrue(sut.viewController.isModelChipHidden)

        sut.presentModelPickerForActiveChat()

        XCTAssertTrue(sut.hasSubmittedPrompt) // still an active chat — no new chat started
        XCTAssertFalse(sut.viewController.isModelChipHidden)
    }

    func test_selectingSupportedModel_afterPresentingModelPicker_keepsModelChipVisible() {
        _ = sut.prepareExternalPromptSubmission()
        sut.presentModelPickerForActiveChat()
        XCTAssertFalse(sut.viewController.isModelChipHidden)

        sut.modelStore.models = [
            AIChatModel(id: "gpt-5", name: "GPT-5", shortName: "G5", provider: .openAI, supportsImageUpload: false, entityHasAccess: true)
        ]
        sut.handleModelSelection("gpt-5")

        XCTAssertFalse(sut.viewController.isModelChipHidden)
    }

    func test_submittingPrompt_afterPresentingModelPickerAndSelectingModel_hidesModelChip() {
        _ = sut.prepareExternalPromptSubmission()
        sut.presentModelPickerForActiveChat()
        sut.modelStore.models = [
            AIChatModel(id: "gpt-5", name: "GPT-5", shortName: "G5", provider: .openAI, supportsImageUpload: false, entityHasAccess: true)
        ]
        sut.handleModelSelection("gpt-5")
        XCTAssertFalse(sut.viewController.isModelChipHidden)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "follow-up", mode: .aiChat)

        XCTAssertTrue(sut.viewController.isModelChipHidden)
    }

    // MARK: - Recovery-Card Submit Block

    func test_recoveryCardBlock_propagatesToViewController() {
        sut.isSubmitBlockedByRecoveryCard = true
        XCTAssertTrue(sut.viewController.isSubmitBlockedByRecoveryCard)

        sut.isSubmitBlockedByRecoveryCard = false
        XCTAssertFalse(sut.viewController.isSubmitBlockedByRecoveryCard)
    }

    func test_handleModelSelection_supportedModel_clearsRecoveryBlock() {
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true)]
        sut.isSubmitBlockedByRecoveryCard = true

        sut.handleModelSelection("gpt-5")

        XCTAssertFalse(sut.isSubmitBlockedByRecoveryCard)
    }

    func test_handleModelSelection_gatedModel_keepsRecoveryBlock() {
        sut.modelStore.models = [makeModel(id: "gated", access: false)]
        sut.isSubmitBlockedByRecoveryCard = true

        sut.handleModelSelection("gated")

        XCTAssertTrue(sut.isSubmitBlockedByRecoveryCard, "A gated selection routes to the upsell — the recovery block must remain")
    }

    func test_presentModelPickerForActiveChat_withSupportedModel_clearsRecoveryBlock() {
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true)]
        sut.isSubmitBlockedByRecoveryCard = true

        sut.presentModelPickerForActiveChat()

        XCTAssertFalse(sut.isSubmitBlockedByRecoveryCard, "Entering Switch Model with a supported model already selected reconciles and unblocks submit")
    }

    func test_presentModelPickerForActiveChat_withNoSupportedModel_keepsRecoveryBlock() {
        mockPreferences.selectedModelId = nil
        sut.modelStore.models = [makeModel(id: "gated", access: false)]
        sut.isSubmitBlockedByRecoveryCard = true

        sut.presentModelPickerForActiveChat()

        XCTAssertTrue(sut.isSubmitBlockedByRecoveryCard,
                      "With no accessible model there is nothing to adopt — the block (and recovery card) must remain")
    }

    func test_presentModelPickerForActiveChat_withEmptyModelList_keepsRecoveryBlock() {
        sut.modelStore.updateSelectedModel("gated", isNewChatContext: false)
        sut.modelStore.models = []
        sut.isSubmitBlockedByRecoveryCard = true

        sut.presentModelPickerForActiveChat()

        XCTAssertTrue(sut.isSubmitBlockedByRecoveryCard,
                      "Empty model list ⇒ no access-checked selectedModel ⇒ block must remain")
    }

    // MARK: - Recovery Picker Session Pixels

    func test_recoveryPickerSession_fullFunnel_smokeTest() {
        let previousDryRun = Pixel.isDryRun
        Pixel.isDryRun = true
        defer { Pixel.isDryRun = previousDryRun }

        _ = sut.prepareExternalPromptSubmission()
        let userScript = makeBridgeReadyUserScript()
        sut.bindToTab(userScript, hasExistingChat: true)
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true)]

        sut.presentModelPickerForActiveChat()
        sut.handleModelSelection("gpt-5")
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "follow-up", mode: .aiChat)

        XCTAssertTrue(sut.viewController.isModelChipHidden)
    }

    func test_recoveryPickerSession_submitChangeModelPixel_smokeTest_withoutRecoveryPin() {
        let previousDryRun = Pixel.isDryRun
        Pixel.isDryRun = true
        defer { Pixel.isDryRun = previousDryRun }

        _ = sut.prepareExternalPromptSubmission()
        let userScript = makeBridgeReadyUserScript()
        sut.bindToTab(userScript, hasExistingChat: true)
        sut.modelStore.models = [
            makeModel(id: "haiku", access: true),
            makeModel(id: "gpt-5", access: true)
        ]
        sut.updateSelectedModel("haiku")

        sut.handleModelSelection("gpt-5")
    }

    func test_recoveryPickerSession_promptSentPixel_notFiredWithoutRecoveryPin() {
        let previousDryRun = Pixel.isDryRun
        Pixel.isDryRun = true
        defer { Pixel.isDryRun = previousDryRun }

        sut.modelStore.models = [makeModel(id: "gpt-5", access: true)]
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "first prompt", mode: .aiChat)
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "follow-up", mode: .aiChat)
    }

    func test_hide_clearsRecoveryBlock() {
        sut.isSubmitBlockedByRecoveryCard = true
        sut.hide()
        XCTAssertFalse(sut.isSubmitBlockedByRecoveryCard)
    }

    func test_startNewChat_clearsRecoveryBlock() {
        sut.isSubmitBlockedByRecoveryCard = true
        sut.startNewChat()
        XCTAssertFalse(sut.isSubmitBlockedByRecoveryCard)
    }

    func test_showExpanded_withNilPrefilledText_doesNotSetPrefilledState() {
        sut.showExpanded(prefilledText: nil)
        XCTAssertEqual(sut.textState, .empty)
    }

    // MARK: - Onboarding Lock

    func test_showExpanded_whenOnboardingLocked_doesNotChangeDisplayState() {
        sut.setOnboardingControlsLocked(true)
        sut.showExpanded()
        XCTAssertNotEqual(sut.displayState, .aiTab(.expanded),
                          "showExpanded must be a no-op while the onboarding lock is active")
    }

    func test_showExpanded_whenOnboardingLocked_doesNotEmitIntent() {
        let exp = expectation(description: "showExpanded intent must not be emitted when locked")
        exp.isInverted = true
        sut.intentPublisher
            .sink { if case .showExpanded = $0 { exp.fulfill() } }
            .store(in: &cancellables)

        sut.setOnboardingControlsLocked(true)
        sut.showExpanded()

        waitForExpectations(timeout: 0.3)
    }

    func test_showExpanded_afterUnlocking_changesDisplayState() {
        sut.setOnboardingControlsLocked(true)
        sut.showExpanded()
        XCTAssertNotEqual(sut.displayState, .aiTab(.expanded))

        sut.setOnboardingControlsLocked(false)
        sut.showExpanded()
        XCTAssertEqual(sut.displayState, .aiTab(.expanded),
                       "Unlocking must restore normal showExpanded behaviour")
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

    func test_unbind_preservesAIChatInputBoxVisibility() {
        // Visibility is owned per-tab by `TabInputState`; resetting on unbind would clobber the
        // value that `applyState` just restored for the incoming tab.
        sut.aiChatInputBoxVisibility = .hidden
        sut.unbind()
        XCTAssertEqual(sut.aiChatInputBoxVisibility, .hidden)
    }

    func test_unbind_preservesVoiceSessionActive() {
        sut.isVoiceSessionActive = true
        sut.unbind()
        XCTAssertTrue(sut.isVoiceSessionActive)
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

    // MARK: - VC Delegate: Submit — Submission Metrics

    func test_submitAIChat_processesSubmissionMetricsForAIChat() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello AI", mode: .aiChat)

        XCTAssertEqual(mockSubmissionMetrics.processedSubmissions.count, 1)
        XCTAssertEqual(mockSubmissionMetrics.processedSubmissions.first?.text, "hello AI")
        XCTAssertEqual(mockSubmissionMetrics.processedSubmissions.first?.mode, .aiChat)
    }

    func test_submitSearch_nonURL_processesSubmissionMetricsForSearch() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "best privacy browser", mode: .search)

        XCTAssertEqual(mockSubmissionMetrics.processedSubmissions.count, 1)
        XCTAssertEqual(mockSubmissionMetrics.processedSubmissions.first?.text, "best privacy browser")
        XCTAssertEqual(mockSubmissionMetrics.processedSubmissions.first?.mode, .search)
    }

    func test_submitSearch_validURL_doesNotProcessSubmissionMetrics() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "https://duckduckgo.com", mode: .search)

        XCTAssertTrue(mockSubmissionMetrics.processedSubmissions.isEmpty)
    }

    // MARK: - VC Delegate: Submit — AI Chat Mode, With Bound Script

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
    }

    func test_activateFromOmnibar_bottomPosition_setsVCProperties() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        XCTAssertEqual(sut.viewController.cardPosition, .bottom)
        XCTAssertFalse(sut.viewController.usesOmnibarMargins)
    }

    func test_activateFromSearchTopPosition_withVoiceSearchDisabledAndAIVoiceEnabled_hidesInlineVoiceButton() {
        sut.updateVoiceSearchAvailability(false)
        sut.updateAIVoiceChatAvailability(true)

        sut.activateFromOmnibar(inputMode: .search, cardPosition: .top)

        XCTAssertEqual(sut.viewController.handler.buttonState, .noButtons)
    }

    func test_activateFromSearchBottomPosition_withVoiceSearchDisabledAndAIVoiceEnabled_hidesInlineVoiceButton() {
        sut.updateVoiceSearchAvailability(false)
        sut.updateAIVoiceChatAvailability(true)

        sut.activateFromOmnibar(inputMode: .search, cardPosition: .bottom)

        XCTAssertEqual(sut.viewController.handler.buttonState, .noButtons)
    }

    func test_activateFromSearchTopPosition_withVoiceSearchEnabled_showsInlineVoiceButton() {
        sut.updateVoiceSearchAvailability(true)

        sut.activateFromOmnibar(inputMode: .search, cardPosition: .top)

        XCTAssertEqual(sut.viewController.handler.buttonState, .voiceOnly)
    }

    func test_activateFromSearchBottomPosition_withVoiceSearchEnabled_showsInlineVoiceButton() {
        sut.updateVoiceSearchAvailability(true)

        sut.activateFromOmnibar(inputMode: .search, cardPosition: .bottom)

        XCTAssertEqual(sut.viewController.handler.buttonState, .voiceOnly)
    }

    func test_activateFromOmnibar_setsExpandedTrue() {
        sut.activateFromOmnibar()
        XCTAssertTrue(sut.viewController.isInputExpanded)
    }

    func test_computeRenderState_whenContentOverlayNotSuppressed_keepsContentVisibleForPrefilledText() {
        sut.activateFromOmnibar(prefilledText: "example.com")

        XCTAssertTrue(sut.computeRenderState().isContentVisible)
        XCTAssertEqual(sut.textState, .prefilledSelected)
    }

    func test_setContentOverlaySuppressed_whenOmnibarActive_hidesContentButKeepsInputVisible() {
        sut.activateFromOmnibar()

        sut.setContentOverlaySuppressed(true)

        let renderState = sut.computeRenderState()
        XCTAssertTrue(renderState.isInputVisible)
        XCTAssertFalse(renderState.isContentVisible)
        XCTAssertTrue(sut.isOmnibarSession)
    }

    func test_setContentOverlaySuppressed_whenOmnibarActiveWithPrefilledText_hidesContentButKeepsInputVisible() {
        sut.activateFromOmnibar(prefilledText: "example.com")

        sut.setContentOverlaySuppressed(true)

        let renderState = sut.computeRenderState()
        XCTAssertTrue(renderState.isInputVisible)
        XCTAssertFalse(renderState.isContentVisible)
        XCTAssertEqual(sut.textState, .prefilledSelected)
    }

    func test_setContentOverlaySuppressed_whenOmnibarActiveAndTextEntered_keepsContentVisible() {
        sut.activateFromOmnibar()
        sut.setContentOverlaySuppressed(true)

        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "duck")

        XCTAssertTrue(sut.computeRenderState().isContentVisible)
    }

    func test_activateFromOmnibar_bottomPosition_leavesBarInCollapsedStartPose() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        // Bottom pre-stages to collapsed; the show animation expands it.
        XCTAssertFalse(sut.viewController.isInputExpanded)
    }

    func test_activateFromOmnibar_emitsIntentWithBothHeights() {
        let exp = expectation(description: "showOmnibarEditing emitted with pending height")
        sut.intentPublisher
            .sink { intent in
                if case .showOmnibarEditing(let height, let pending) = intent {
                    XCTAssertGreaterThan(height, 0)
                    XCTAssertNotNil(pending)
                    exp.fulfill()
                }
            }
            .store(in: &cancellables)

        sut.activateFromOmnibar(cardPosition: .bottom)
        waitForExpectations(timeout: 1)
    }

    func test_deactivateToOmnibar_resetsVCProperties() {
        sut.activateFromOmnibar(cardPosition: .top)
        sut.deactivateToOmnibar()

        XCTAssertEqual(sut.viewController.cardPosition, .bottom)
        XCTAssertFalse(sut.viewController.usesOmnibarMargins)
        XCTAssertFalse(sut.viewController.isInputExpanded)
    }

    func test_deactivateToOmnibar_resetsState() {
        sut.activateFromOmnibar(prefilledText: "test")
        sut.deactivateToOmnibar()

        XCTAssertEqual(sut.displayState, .hidden)
        // Text is preserved through deactivate; the dismiss completion handler clears it after the animation.
        XCTAssertEqual(sut.textState, .prefilledSelected)
        XCTAssertFalse(sut.isOmnibarSession)
    }

    func test_deactivateToOmnibar_emitsIntent() {
        sut.activateFromOmnibar()

        let exp = expectation(description: "hideOmnibarEditing intent emitted")
        sut.intentPublisher
            .sink { if $0 == .hideOmnibarEditing(animated: true) { exp.fulfill() } }
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
        sut.activateFromOmnibar(cardPosition: .bottom)

        sut.updateOmnibarInputVisibility(false)

        XCTAssertEqual(sut.displayState, .omnibar(.inactive))
    }

    func test_updateOmnibarInputVisibility_topOmnibarAwaitFallbackTransitionsToInactive() {
        sut.activateFromOmnibar(cardPosition: .top)

        sut.updateOmnibarInputVisibility(false)

        XCTAssertEqual(sut.displayState, .omnibar(.active))

        let exp = expectation(description: "top omnibar keyboard await fallback transitions to inactive")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            XCTAssertEqual(self?.sut.displayState, .omnibar(.inactive))
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
    }

    func test_updateOmnibarInputVisibility_inactiveToActive() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        sut.updateOmnibarInputVisibility(false)

        sut.updateOmnibarInputVisibility(true)

        XCTAssertEqual(sut.displayState, .omnibar(.active))
    }

    func test_updateOmnibarInputVisibility_emitsInactiveIntent() {
        sut.activateFromOmnibar(cardPosition: .bottom)
        let exp = expectation(description: "showOmnibarInactive intent emitted")
        sut.intentPublisher
            .sink { if $0 == .showOmnibarInactive { exp.fulfill() } }
            .store(in: &cancellables)

        sut.updateOmnibarInputVisibility(false)

        waitForExpectations(timeout: 1)
    }

    func test_updateOmnibarInputVisibility_emitsActiveIntent() {
        sut.activateFromOmnibar(cardPosition: .bottom)
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
        sut.activateFromOmnibar(cardPosition: .bottom)
        sut.updateOmnibarInputVisibility(false)

        sut.deactivateToOmnibar()

        XCTAssertEqual(sut.displayState, .hidden)
    }

    func test_isOmnibarSession_trueForInactiveState() {
        sut.activateFromOmnibar(cardPosition: .bottom)
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
        sut.activateFromOmnibar(cardPosition: .bottom)
        sut.updateOmnibarInputVisibility(false)
        sut.dismissOmnibarKeyboard()
        XCTAssertEqual(sut.displayState, .omnibar(.inactive))
    }

    func test_submitSearch_fromOmnibarInactive_deactivates() {
        sut.activateFromOmnibar(inputMode: .search, cardPosition: .bottom)
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

    func test_updateInputMode_firstModeChangeFromBottomOmnibar_keepsActivePresentation() {
        sut.activateFromOmnibar(inputMode: .search, cardPosition: .bottom)

        sut.updateInputMode(.aiChat, animated: false)

        XCTAssertEqual(sut.displayState, .omnibar(.active))
        XCTAssertEqual(sut.viewController.inputMode, .aiChat)
        // Bottom bar sits in show-animation start pose here; expansion runs in the intent handler.

        let renderState = sut.computeRenderState()
        XCTAssertEqual(renderState.cardPosition, .bottom)
        XCTAssertTrue(renderState.isInputVisible)
        XCTAssertTrue(renderState.isContentVisible)
        XCTAssertTrue(renderState.isExpanded)
        XCTAssertFalse(renderState.inactiveAppearance)
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

    func test_updateToggleEnabled_false_forcesAIChatModeWhenAITab() {
        sut.showExpanded(inputMode: .search)
        sut.updateToggleEnabled(false)
        XCTAssertEqual(sut.inputMode, .aiChat)
    }

    func test_updateInputMode_toggleDisabled_forcesAIChatInAITabSession() {
        sut.showExpanded()
        sut.updateToggleEnabled(false)
        sut.updateInputMode(.search, animated: false)
        XCTAssertEqual(sut.inputMode, .aiChat)
    }

    func test_syncInputModeFromExternalSource_toggleDisabled_forcesAIChatInAITabSession() {
        sut.showExpanded()
        sut.updateToggleEnabled(false)
        sut.syncInputModeFromExternalSource(.search)
        XCTAssertEqual(sut.inputMode, .aiChat)
    }

    func test_updateToggleEnabled_false_clearsAttachmentErrorBannerWhenOmnibar() {
        let validationMessage = UserText.aiChatAttachmentFileTooManyPages(maxPagesPerFile: 8)
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.viewController.addAttachment(.invalidFile(UnifiedToggleInputInvalidFileAttachment(
            fileName: "too-many-pages.pdf",
            mimeType: "application/pdf",
            fileSizeBytes: 1_000,
            validationMessage: validationMessage
        )))
        sut.viewController.showAttachmentValidationError(validationMessage)
        XCTAssertEqual(sut.viewController.attachmentValidationMessage, validationMessage)

        sut.updateToggleEnabled(false)

        XCTAssertEqual(sut.inputMode, .search)
        XCTAssertNil(sut.viewController.attachmentValidationMessage)
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

    // MARK: - Fire Tab

    func test_updateIsFireTab_true_updatesHandler() {
        XCTAssertFalse(sut.viewController.handler.isFireTab)
        sut.updateIsFireTab(true)
        XCTAssertTrue(sut.viewController.handler.isFireTab)
    }

    func test_updateIsFireTab_falseAfterTrue_updatesHandler() {
        sut.updateIsFireTab(true)
        sut.updateIsFireTab(false)
        XCTAssertFalse(sut.viewController.handler.isFireTab)
    }

    func test_updateIsFireTab_noChangeDoesNotRebuildDaxLogoManager() {
        let initialManager = sut.contentViewController.daxLogoManager
        sut.updateIsFireTab(false)
        XCTAssertTrue(sut.contentViewController.daxLogoManager === initialManager)
    }

    func test_updateIsFireTab_trueRebuildsDaxLogoManager() {
        let initialManager = sut.contentViewController.daxLogoManager
        sut.updateIsFireTab(true)
        XCTAssertFalse(sut.contentViewController.daxLogoManager === initialManager)
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
        sut.handleExternalSubmission(.query)
        XCTAssertEqual(sut.displayState, .hidden)
    }

    func test_handleExternalQuerySubmission_hidesAITab() {
        sut.showExpanded()
        sut.handleExternalSubmission(.query)
        XCTAssertEqual(sut.displayState, .hidden)
    }

    func test_handleExternalQuerySubmission_noOpWhenHidden() {
        sut.handleExternalSubmission(.query)
        XCTAssertEqual(sut.displayState, .hidden)
    }

    func test_handleExternalPromptSubmission_deactivatesOmnibarEditing() {
        sut.activateFromOmnibar()
        sut.handleExternalSubmission(.prompt)
        XCTAssertEqual(sut.displayState, .hidden)
    }

    func test_handleExternalPromptSubmission_collapsesAITab() {
        sut.showExpanded()
        sut.handleExternalSubmission(.prompt)
        XCTAssertEqual(sut.displayState, .aiTab(.collapsed))
    }

    func test_handleExternalPromptSubmission_fromAITab_clearsPendingAttachments() {
        sut.showExpanded()
        sut.viewController.addAttachment(.image(AIChatImageAttachment(image: UIImage(), fileName: "test.png")))

        sut.handleExternalSubmission(.prompt)

        XCTAssertTrue(sut.viewController.currentAttachments.isEmpty)
    }

    func test_handleExternalPromptSubmission_noOpWhenHidden() {
        sut.handleExternalSubmission(.prompt)
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

    func test_aiChatStatus_ready_restoresAttachmentButtonAndMenuAfterGenerating() {
        configureImageAttachments()
        sut.updateImageButtonVisibility()
        XCTAssertTrue(sut.viewController.isImageButtonEnabled)
        XCTAssertNotNil(sut.viewController.attachmentMenu)

        sut.aiChatStatus = .streaming
        XCTAssertFalse(sut.viewController.isImageButtonEnabled)
        XCTAssertNil(sut.viewController.attachmentMenu)

        sut.aiChatStatus = .ready
        XCTAssertTrue(sut.viewController.isImageButtonEnabled)
        XCTAssertNotNil(sut.viewController.attachmentMenu)
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

    // MARK: - Customize Responses Button

    func test_customizeResponsesTap_forwardsPublisher() {
        let exp = expectation(description: "didPressCustomizeResponsesButton fires")
        sut.didPressCustomizeResponsesButton
            .sink { exp.fulfill() }
            .store(in: &cancellables)

        sut.viewController.handler.customizeResponsesButtonTapped()
        waitForExpectations(timeout: 1)
    }

    func test_customizeResponsesTap_collapsesInput() {
        sut.showExpanded()
        XCTAssertEqual(sut.displayState, .aiTab(.expanded))

        sut.viewController.handler.customizeResponsesButtonTapped()
        XCTAssertEqual(sut.displayState, .aiTab(.collapsed))
    }

    func test_customizeResponsesTap_preservesSelectedTool() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]
        sut.showExpanded()
        sut.handleToolsMenuSelection(.webSearch)
        XCTAssertEqual(sut.selectedTool, .webSearch)

        sut.handleToolsMenuSelection(.customizeResponses)

        XCTAssertEqual(sut.selectedTool, .webSearch)
        XCTAssertEqual(sut.viewController.selectedTool, .webSearch)
    }

    func test_toolsMenu_containsCustomizeResponsesAction_onAITab() {
        sut.showExpanded()

        let actionTitles = toolsMenuActions().map(\.title)

        XCTAssertTrue(actionTitles.contains(UserText.aiChatToolbarCustomizeResponsesMenuTitle))
    }

    func test_toolsMenu_customizeResponsesHasNoIcon_onAITab() {
        sut.showExpanded()

        let customize = toolsMenuActions().first { $0.title == UserText.aiChatToolbarCustomizeResponsesMenuTitle }

        XCTAssertNotNil(customize)
        XCTAssertNil(customize?.image)
    }

    func test_toolsMenu_separatesCustomizeResponsesFromToolsWithDivider_onAITab() {
        sut.showExpanded()

        let children = sut.viewController.toolsMenu?.children ?? []
        let topLevelActionTitles = children.compactMap { ($0 as? UIAction)?.title }
        let inlineMenus = children.compactMap { $0 as? UIMenu }.filter { $0.options.contains(.displayInline) }

        // Customize Responses stays a top-level action; the tools live in their own inline
        // (divider-separated) section.
        XCTAssertEqual(topLevelActionTitles, [UserText.aiChatToolbarCustomizeResponsesMenuTitle])
        XCTAssertEqual(inlineMenus.count, 1)
        let inlineTitles = inlineMenus.first?.children.compactMap { ($0 as? UIAction)?.title } ?? []
        XCTAssertTrue(inlineTitles.contains(UserText.aiChatToolbarWebSearchToolTitle))
        XCTAssertTrue(inlineTitles.contains(UserText.aiChatToolbarImageGenerationToolTitle))
    }

    func test_handleToolsMenuSelection_customizeResponses_forwardsToHandler() {
        let exp = expectation(description: "didPressCustomizeResponsesButton fires")
        sut.didPressCustomizeResponsesButton
            .sink { exp.fulfill() }
            .store(in: &cancellables)

        sut.handleToolsMenuSelection(.customizeResponses)

        waitForExpectations(timeout: 1)
    }

    func test_toolsMenu_doesNotContainCustomizeResponsesAction_inOmnibar() {
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.updateInputMode(.aiChat, animated: false)

        let actionTitles = toolsMenuActions().map(\.title)

        XCTAssertFalse(actionTitles.contains(UserText.aiChatToolbarCustomizeResponsesMenuTitle))
    }

    // MARK: - Web Search Tools

    func test_toolsButton_visibleOnAITabWhenModelSupportsTools() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]

        sut.showExpanded()

        XCTAssertFalse(sut.viewController.isToolsButtonHidden)
    }

    func test_toolsButton_hiddenWhenModelDoesNotSupportAnyTool() {
        mockPreferences.selectedModelId = "mistral"
        sut.modelStore.models = [makeModel(id: "mistral", access: true, supportedTools: [])]

        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.updateInputMode(.aiChat, animated: false)

        XCTAssertTrue(sut.viewController.isToolsButtonHidden)
    }

    func test_toolsButton_visibleInOmnibarAIChatWhenModelSupportsWebSearch() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]

        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.updateInputMode(.aiChat, animated: false)

        XCTAssertFalse(sut.viewController.isToolsButtonHidden)
    }

    func test_toolsButton_staysUnhiddenAcrossSwitchToSearchMode_soItFadesWithTheToolbar() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]

        sut.showExpanded()
        XCTAssertFalse(sut.viewController.isToolsButtonHidden)

        sut.updateInputMode(.search, animated: true)

        XCTAssertFalse(sut.viewController.isToolsButtonHidden)
    }

    func test_toolsMenu_disablesWebSearchActionWhenModelDoesNotSupportIt() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.imageGeneration])]

        sut.showExpanded()

        let webSearchAction = toolsMenuActions().first { $0.title == UserText.aiChatToolbarWebSearchToolTitle }

        XCTAssertEqual(webSearchAction?.attributes, .disabled)
    }

    func test_toolsMenu_enablesWebSearchActionWhenModelSupportsIt() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]

        sut.showExpanded()

        let webSearchAction = toolsMenuActions().first { $0.title == UserText.aiChatToolbarWebSearchToolTitle }

        XCTAssertEqual(webSearchAction?.attributes, [])
    }

    func test_selectTool_setsSelectedTool() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]
        sut.activateFromOmnibar(inputMode: .aiChat)

        sut.selectTool(.webSearch)

        XCTAssertEqual(sut.selectedTool, .webSearch)
        XCTAssertEqual(sut.viewController.selectedTool, .webSearch)
    }

    func test_toolsController_toggleSelection_togglesOffSelectedWebSearchTool() {
        let toolsController = UTIToolsController()
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]
        toolsController.select(.webSearch, for: sut.modelStore)

        toolsController.toggleSelection(for: .webSearch, modelStore: sut.modelStore)

        XCTAssertNil(toolsController.selectedTool)
    }

    func test_handleToolsMenuSelection_selectsWebSearchTool() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]
        sut.activateFromOmnibar(inputMode: .aiChat)

        sut.handleToolsMenuSelection(.webSearch)

        XCTAssertEqual(sut.selectedTool, .webSearch)
        XCTAssertEqual(sut.viewController.selectedTool, .webSearch)
    }

    func test_handleToolsMenuSelection_togglesOffSelectedWebSearchTool() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.handleToolsMenuSelection(.webSearch)

        sut.handleToolsMenuSelection(.webSearch)

        XCTAssertNil(sut.selectedTool)
        XCTAssertNil(sut.viewController.selectedTool)
    }

    func test_handleToolsMenuSelection_replacesPreviousToolSelection() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch, .imageGeneration])]
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.handleToolsMenuSelection(.webSearch)

        sut.handleToolsMenuSelection(.imageGeneration)

        XCTAssertEqual(sut.selectedTool, .imageGeneration)
        XCTAssertEqual(sut.viewController.selectedTool, .imageGeneration)
    }

    func test_updateSelectedModel_clearsSelectedToolWhenNewModelDoesNotSupportIt() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [
            makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch]),
            makeModel(id: "claude", access: true)
        ]
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.selectTool(.webSearch)

        sut.updateSelectedModel("claude")

        XCTAssertNil(sut.selectedTool)
        XCTAssertNil(sut.viewController.selectedTool)
    }

    func test_submitAIChat_noBoundScript_passesSelectedToolToDelegate() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.selectTool(.webSearch)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello AI", mode: .aiChat)

        XCTAssertEqual(mockDelegate.submittedTools, [.webSearch])
    }

    func test_showCollapsed_doesNotClearSelectedToolBeforeSubmission() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]
        sut.showExpanded()
        sut.selectTool(.webSearch)

        sut.showCollapsed()

        XCTAssertEqual(sut.selectedTool, .webSearch)
    }

    func test_submitAIChat_clearsSelectedToolAfterSubmission() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]
        sut.showExpanded()
        sut.selectTool(.webSearch)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello AI", mode: .aiChat)

        XCTAssertNil(sut.selectedTool)
        XCTAssertNil(sut.viewController.selectedTool)
    }

    // MARK: - Image Generation Tool

    func test_toolsMenu_containsImageGenerationAction() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.imageGeneration])]

        sut.showExpanded()

        let actionTitles = toolsMenuActions().map(\.title)

        XCTAssertTrue(actionTitles.contains(UserText.aiChatToolbarImageGenerationToolTitle))
    }

    func test_toolsMenu_disablesImageGenerationActionWhenModelDoesNotSupportIt() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]

        sut.showExpanded()

        let imageGenAction = toolsMenuActions().first { $0.title == UserText.aiChatToolbarImageGenerationToolTitle }

        XCTAssertEqual(imageGenAction?.attributes, .disabled)
    }

    func test_toolsMenu_enablesImageGenerationActionWhenModelSupportsIt() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.imageGeneration])]

        sut.showExpanded()

        let imageGenAction = toolsMenuActions().first { $0.title == UserText.aiChatToolbarImageGenerationToolTitle }

        XCTAssertEqual(imageGenAction?.attributes, [])
    }

    func test_selectTool_imageGeneration_setsSelectedTool() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.imageGeneration])]
        sut.activateFromOmnibar(inputMode: .aiChat)

        sut.selectTool(.imageGeneration)

        XCTAssertEqual(sut.selectedTool, .imageGeneration)
        XCTAssertEqual(sut.viewController.selectedTool, .imageGeneration)
    }

    func test_selectTool_imageGeneration_isIgnoredWhenModelDoesNotSupportIt() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [])]
        sut.activateFromOmnibar(inputMode: .aiChat)

        sut.selectTool(.imageGeneration)

        XCTAssertNil(sut.selectedTool)
    }

    /// Mirrors `handleNewImageGenerationChatStarted` on the host: the FE message must leave
    /// the UTI expanded with the image-generation tool selected so the user lands in an
    /// editing pose ready to type their prompt. `selectTool` sits between `startNewChat`
    /// (which resets tools) and `showExpanded`.
    func test_startNewChat_selectTool_imageGeneration_thenShowExpanded_endsExpandedWithToolSelected() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.imageGeneration])]

        sut.startNewChat()
        sut.selectTool(.imageGeneration)
        sut.showExpanded(inputMode: .aiChat)

        XCTAssertEqual(sut.displayState, .aiTab(.expanded))
        XCTAssertEqual(sut.selectedTool, .imageGeneration)
        XCTAssertEqual(sut.viewController.selectedTool, .imageGeneration)
    }

    func test_toolsController_toggleSelection_togglesOffSelectedImageGenerationTool() {
        let toolsController = UTIToolsController()
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.imageGeneration])]
        toolsController.select(.imageGeneration, for: sut.modelStore)

        toolsController.toggleSelection(for: .imageGeneration, modelStore: sut.modelStore)

        XCTAssertNil(toolsController.selectedTool)
    }

    func test_toolsController_selectingImageGeneration_replacesPreviousWebSearchSelection() {
        let toolsController = UTIToolsController()
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch, .imageGeneration])]
        toolsController.select(.webSearch, for: sut.modelStore)
        XCTAssertEqual(toolsController.selectedTool, .webSearch)

        toolsController.select(.imageGeneration, for: sut.modelStore)

        XCTAssertEqual(toolsController.selectedTool, .imageGeneration)
    }

    func test_updateSelectedModel_clearsImageGenerationSelectionWhenNewModelDoesNotSupportIt() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [
            makeModel(id: "gpt-5", access: true, supportedTools: [.imageGeneration]),
            makeModel(id: "claude", access: true, supportedTools: [])
        ]
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.selectTool(.imageGeneration)

        sut.updateSelectedModel("claude")

        XCTAssertNil(sut.selectedTool)
        XCTAssertNil(sut.viewController.selectedTool)
    }

    func test_submitAIChat_imageGenerationSelected_forwardsToolChoice() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.imageGeneration])]
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.selectTool(.imageGeneration)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "draw a cat", mode: .aiChat)

        XCTAssertEqual(mockDelegate.submittedTools, [.imageGeneration])
    }

    // MARK: - Image Generation: Model & Reasoning Visibility

    func test_selectImageGeneration_hidesModelChip() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.imageGeneration])]
        sut.activateFromOmnibar(inputMode: .aiChat)

        sut.selectTool(.imageGeneration)

        XCTAssertTrue(sut.viewController.isModelChipHidden)
    }

    func test_selectImageGeneration_hidesReasoningButton() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(
            id: "gpt-5", access: true, supportedTools: [.imageGeneration],
            supportedReasoningEffort: [.low, .medium, .high]
        )]
        sut.activateFromOmnibar(inputMode: .aiChat)
        XCTAssertFalse(sut.viewController.isReasoningButtonHidden)

        sut.selectTool(.imageGeneration)

        XCTAssertTrue(sut.viewController.isReasoningButtonHidden)
    }

    func test_clearImageGeneration_restoresModelChip() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.imageGeneration])]
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.selectTool(.imageGeneration)
        XCTAssertTrue(sut.viewController.isModelChipHidden)

        sut.clearSelectedTool()

        XCTAssertFalse(sut.viewController.isModelChipHidden)
    }

    func test_clearImageGeneration_restoresReasoningButton() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(
            id: "gpt-5", access: true, supportedTools: [.imageGeneration],
            supportedReasoningEffort: [.low, .medium, .high]
        )]
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.selectTool(.imageGeneration)
        XCTAssertTrue(sut.viewController.isReasoningButtonHidden)

        sut.clearSelectedTool()

        XCTAssertFalse(sut.viewController.isReasoningButtonHidden)
    }

    func test_selectWebSearch_doesNotHideModelChip() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.webSearch])]
        sut.activateFromOmnibar(inputMode: .aiChat)

        sut.selectTool(.webSearch)

        XCTAssertFalse(sut.viewController.isModelChipHidden)
    }

    // MARK: - Model Selection: persistedModelId

    func test_persistedModelId_returnsPreferencesValue() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true)]
        XCTAssertEqual(sut.persistedModelId, "gpt-5")
    }

    func test_persistedModelId_fallsBackToFirstAccessibleModel() {
        mockPreferences.selectedModelId = nil
        sut.modelStore.models = [
            makeModel(id: "premium", access: false),
            makeModel(id: "free", access: true)
        ]
        XCTAssertEqual(sut.persistedModelId, "free")
    }

    func test_persistedModelId_fallsBackToNil() {
        mockPreferences.selectedModelId = nil
        sut.modelStore.models = []
        XCTAssertNil(sut.persistedModelId)
    }

    // MARK: - Model Selection: updateSelectedModel

    func test_updateSelectedModel_persistsToPreferences() {
        sut.updateSelectedModel("gpt-5")
        XCTAssertEqual(mockPreferences.selectedModelId, "gpt-5")
    }

    // MARK: - Model Selection: new-chat vs ongoing-chat picks

    func test_updateSelectedModel_onNewChat_writesPreferredModelToPreferences() {
        sut.modelStore.models = [makeModel(id: "haiku", access: true)]
        XCTAssertFalse(sut.hasSubmittedPrompt)

        sut.updateSelectedModel("haiku")

        XCTAssertEqual(mockPreferences.selectedModelId, "haiku")
    }

    func test_updateSelectedModel_afterPromptSubmitted_doesNotChangePreferredModel() {
        sut.modelStore.models = [
            makeModel(id: "haiku", access: true),
            makeModel(id: "mistral", access: true)
        ]
        sut.updateSelectedModel("haiku")
        XCTAssertEqual(mockPreferences.selectedModelId, "haiku")
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertTrue(sut.hasSubmittedPrompt)

        sut.updateSelectedModel("mistral")

        XCTAssertEqual(mockPreferences.selectedModelId, "haiku",
                       "ongoing-chat picks must not retarget the cross-platform new-chat default")
        XCTAssertEqual(sut.modelStore.currentModelId, "mistral",
                       "ongoing-chat pick still updates the live current-tab model")
    }

    func test_updateSelectedModel_onExistingChatBoundTab_doesNotChangePreferredModel() {
        sut.modelStore.models = [
            makeModel(id: "haiku", access: true),
            makeModel(id: "mistral", access: true)
        ]
        sut.updateSelectedModel("haiku")
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript, hasExistingChat: true)
        XCTAssertTrue(sut.hasSubmittedPrompt)

        sut.updateSelectedModel("mistral")

        XCTAssertEqual(mockPreferences.selectedModelId, "haiku")
    }

    func test_persistedModelId_fallsBackToPreferredModel_onFreshTabActivation() {
        sut.modelStore.models = [
            makeModel(id: "gpt-5", access: true),
            makeModel(id: "haiku", access: true)
        ]
        sut.updateSelectedModel("haiku")
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)

        sut.modelStore.applyPersistedSelection(modelID: nil, reasoningMode: nil)

        XCTAssertEqual(sut.persistedModelId, "haiku",
                       "opening a new tab should return to the user's last new-chat pick")
    }

    func test_handleModelSelection_whenModelHasAccess_persistsToPreferences() {
        sut.modelStore.models = [makeModel(id: "plus-model", access: true, accessTier: ["plus"])]

        sut.handleModelSelection("plus-model")

        XCTAssertEqual(mockPreferences.selectedModelId, "plus-model")
    }

    func test_handleModelSelection_whenAddressBarFreeUserSelectsPlusGatedModel_routesPurchaseFlowWithoutChangingSelection() {
        mockPreferences.selectedModelId = "free-model"
        sut.modelStore.models = [
            makeModel(id: "free-model", access: true, accessTier: ["free"]),
            makeModel(id: "plus-model", access: false, accessTier: ["plus"])
        ]
        let notificationExpectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "featurePage", value: "duckai")
                && self.hasQueryItem(in: components, name: "origin", value: "funnel_addressbar_ios__modelpicker")
        }

        sut.handleModelSelection("plus-model")

        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(mockPreferences.selectedModelId, "free-model")
    }

    func test_handleModelSelection_whenAddressBarPlusUserSelectsProGatedModel_routesUpgradeFlowWithoutChangingSelection() {
        mockPreferences.selectedModelId = "plus-model"
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .plus, hasActiveSubscription: true)
        sut.modelStore.models = [
            makeModel(id: "plus-model", access: true, accessTier: ["plus"]),
            makeModel(id: "pro-model", access: false, accessTier: ["pro"])
        ]
        let notificationExpectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionPlanChangeFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "featurePage", value: "duckai")
                && self.hasQueryItem(in: components, name: "origin", value: "funnel_addressbar_ios__modelpicker")
        }

        sut.handleModelSelection("pro-model")

        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(mockPreferences.selectedModelId, "plus-model")
    }

    func test_handleModelSelection_whenGatedModelBecomesAccessibleAfterSubscriptionRefresh_selectsPendingModel() {
        mockPreferences.selectedModelId = "plus-model"
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .plus, hasActiveSubscription: true)
        sut.modelStore.models = [
            makeModel(id: "plus-model", access: true, accessTier: ["plus"]),
            makeModel(id: "pro-model", access: false, accessTier: ["pro"])
        ]
        let notificationExpectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionPlanChangeFlow = deepLink else {
                return false
            }
            return true
        }

        sut.handleModelSelection("pro-model")
        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(mockPreferences.selectedModelId, "plus-model")

        sut.modelStore.subscriptionState = SubscriptionState(userTier: .pro, hasActiveSubscription: true)
        sut.modelStore.models = [
            makeModel(id: "plus-model", access: true, accessTier: ["plus"]),
            makeModel(id: "pro-model", access: true, accessTier: ["pro"])
        ]
        sut.modelStore.onModelsUpdated?()

        XCTAssertEqual(mockPreferences.selectedModelId, "pro-model")
    }

    func test_handleModelSelection_whenAddressBarFreeUserSelectsProGatedModel_routesPurchaseFlowWithoutChangingSelection() {
        mockPreferences.selectedModelId = "free-model"
        sut.modelStore.models = [
            makeModel(id: "free-model", access: true, accessTier: ["free"]),
            makeModel(id: "pro-model", access: false, accessTier: ["pro"])
        ]
        let notificationExpectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "featurePage", value: "duckai")
                && self.hasQueryItem(in: components, name: "origin", value: "funnel_addressbar_ios__modelpicker")
        }

        sut.handleModelSelection("pro-model")

        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(mockPreferences.selectedModelId, "free-model")
    }

    func test_handleModelSelection_whenGatedModelHasNoPublicTier_doesNotChangeSelectionOrRouteToSubscriptionFlow() {
        mockPreferences.selectedModelId = "free-model"
        sut.modelStore.models = [
            makeModel(id: "free-model", access: true, accessTier: ["free"]),
            makeModel(id: "internal-model", access: false, accessTier: ["internal"])
        ]
        let notificationExpectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil)
        notificationExpectation.isInverted = true

        sut.handleModelSelection("internal-model")

        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(mockPreferences.selectedModelId, "free-model")
    }

    func test_handleModelSelection_whenDuckAITabFreeUserSelectsPlusGatedModel_routesPurchaseFlowWithDuckAIOrigin() {
        mockPreferences.selectedModelId = "free-model"
        sut.modelStore.models = [
            makeModel(id: "free-model", access: true, accessTier: ["free"]),
            makeModel(id: "plus-model", access: false, accessTier: ["plus"])
        ]
        sut.showCollapsed()
        let notificationExpectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "featurePage", value: "duckai")
                && self.hasQueryItem(in: components, name: "origin", value: "funnel_duckai_ios__modelpicker")
        }

        sut.handleModelSelection("plus-model")

        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(mockPreferences.selectedModelId, "free-model")
    }

    func test_handleModelSelection_whenDuckAITabPlusUserSelectsProGatedModel_routesUpgradeFlowWithDuckAIOrigin() {
        mockPreferences.selectedModelId = "plus-model"
        sut.modelStore.subscriptionState = SubscriptionState(userTier: .plus, hasActiveSubscription: true)
        sut.modelStore.models = [
            makeModel(id: "plus-model", access: true, accessTier: ["plus"]),
            makeModel(id: "pro-model", access: false, accessTier: ["pro"])
        ]
        sut.showCollapsed()
        let notificationExpectation = expectation(forNotification: .settingsDeepLinkNotification, object: nil) { notification in
            guard let deepLink = notification.object as? SettingsViewModel.SettingsDeepLinkSection,
                  case .subscriptionPlanChangeFlow(let components) = deepLink else {
                return false
            }
            return self.hasQueryItem(in: components, name: "featurePage", value: "duckai")
                && self.hasQueryItem(in: components, name: "origin", value: "funnel_duckai_ios__modelpicker")
        }

        sut.handleModelSelection("pro-model")

        wait(for: [notificationExpectation], timeout: 1.0)
        XCTAssertEqual(mockPreferences.selectedModelId, "plus-model")
    }

    // MARK: - Model Selection: supportsImageUpload

    func test_selectedModelSupportsImageUpload_returnsFalse_whenModelsEmpty() {
        sut.modelStore.models = []
        XCTAssertFalse(sut.selectedModelSupportsImageUpload)
    }

    func test_selectedModelSupportsImageUpload_returnsFalse_whenSelectedModelDoesNot() {
        mockPreferences.selectedModelId = "no-images"
        sut.modelStore.models = [makeModel(id: "no-images", access: true, supportsImageUpload: false)]
        XCTAssertFalse(sut.selectedModelSupportsImageUpload)
    }

    func test_selectedModelSupportsImageUpload_returnsTrue_whenSelectedModelDoes() {
        mockPreferences.selectedModelId = "has-images"
        sut.modelStore.models = [makeModel(id: "has-images", access: true, supportsImageUpload: true)]
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
        sut.modelStore.models = [
            makeModel(id: "premium", access: false),
            makeModel(id: "free", access: true)
        ]
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertEqual(mockDelegate.submittedModelId, "free")
    }

    func test_prepareExternalPromptSubmission_passesModelIdForFirstPrompt() {
        mockPreferences.selectedModelId = "gpt-5"

        let submission = sut.prepareExternalPromptSubmission()

        XCTAssertEqual(submission.modelId, "gpt-5")
    }

    func test_prepareExternalPromptSubmission_omitsModelIdAfterFirstPrompt() {
        mockPreferences.selectedModelId = "gpt-5"
        _ = sut.prepareExternalPromptSubmission()

        let submission = sut.prepareExternalPromptSubmission()

        XCTAssertNil(submission.modelId)
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

    func test_modelChip_hiddenAfterPreparingExternalPromptSubmission() {
        sut.prepareExternalPromptSubmission()
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

    func test_modelChip_hiddenWhileImageGenerationSelected_andRestoredAfterDeselect_inNewChat() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.imageGeneration])]
        sut.activateFromOmnibar(inputMode: .aiChat)
        XCTAssertFalse(sut.viewController.isModelChipHidden)

        sut.selectTool(.imageGeneration)
        XCTAssertTrue(sut.viewController.isModelChipHidden)

        sut.clearSelectedTool()
        XCTAssertFalse(sut.viewController.isModelChipHidden)
    }

    func test_modelChip_remainsHiddenAfterDeselectingImageGeneration_inExistingChat() {
        // Regression: deselecting the image-gen tool used to clobber the chip's hidden state to false,
        // making the chip reappear inside an existing chat (where `hasSubmittedPrompt` should keep it hidden).
        mockPreferences.selectedModelId = "gpt-5"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true, supportedTools: [.imageGeneration])]
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript, hasExistingChat: true)
        XCTAssertTrue(sut.hasSubmittedPrompt)
        XCTAssertTrue(sut.viewController.isModelChipHidden)

        sut.selectTool(.imageGeneration)
        XCTAssertTrue(sut.viewController.isModelChipHidden)

        sut.clearSelectedTool()
        XCTAssertTrue(sut.hasSubmittedPrompt)
        XCTAssertTrue(sut.viewController.isModelChipHidden)
    }

    // MARK: - Stale Model Selection

    func test_persistedModelId_clearedWhenModelRemoved() {
        mockPreferences.selectedModelId = "removed-model"
        mockPreferences.selectedModelShortName = "Removed"
        sut.modelStore.models = [makeModel(id: "gpt-5", access: true), makeModel(id: "claude", access: true)]

        XCTAssertEqual(sut.persistedModelId, "gpt-5")
    }

    func test_persistedModelId_clearedWhenAccessLost() {
        mockPreferences.selectedModelId = "premium"
        sut.modelStore.models = [makeModel(id: "premium", access: false), makeModel(id: "free", access: true)]

        XCTAssertEqual(sut.persistedModelId, "free")
    }

    func test_persistedModelId_noAccessibleModels_returnsNil() {
        mockPreferences.selectedModelId = "locked"
        sut.modelStore.models = [makeModel(id: "locked", access: false)]

        XCTAssertNil(sut.persistedModelId)
    }

    // MARK: - Chip Label Persistence

    func test_updateSelectedModel_persistsShortName() {
        sut.modelStore.models = [AIChatModel(id: "gpt-5", name: "GPT-5", shortName: "G5", provider: .openAI, supportsImageUpload: false, entityHasAccess: true)]
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
        let models = UTIModelStore.resolveModels(from: [remote], userTier: .free)

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
        let models = UTIModelStore.resolveModels(from: [remote], userTier: .free)

        XCTAssertFalse(models[0].entityHasAccess)
    }

    func test_resolveModels_mapsSupportedTools() {
        let remote = AIChatRemoteModel(
            id: "gpt-5",
            name: "GPT-5",
            provider: "openai",
            entityHasAccess: true,
            supportsImageUpload: false,
            supportedTools: ["WebSearch"],
            accessTier: []
        )
        let models = UTIModelStore.resolveModels(from: [remote], userTier: .free)

        XCTAssertEqual(models[0].supportedTools, [.webSearch])
    }

    func test_chipLabel_shownFromCacheBeforeFetch() {
        mockPreferences.selectedModelShortName = "Cached Model"
        let coordinator = UnifiedToggleInputCoordinator(host: .omnibar, isToggleEnabled: true, preferences: mockPreferences)

        XCTAssertEqual(coordinator.viewController.modelName, "Cached Model")
        XCTAssertNil(coordinator.viewController.modelPickerMenu)
    }

    // MARK: - Model ID Suppression on Follow-up Prompts

    func test_submitAIChat_firstPrompt_sendsModelId() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "first", mode: .aiChat)
        XCTAssertEqual(mockDelegate.submittedModelId, "gpt-5")
    }

    func test_submitAIChat_secondPrompt_sendsNilModelId() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "first", mode: .aiChat)
        mockDelegate.submittedModelId = nil
        sut.showExpanded()
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "follow-up", mode: .aiChat)
        XCTAssertNil(mockDelegate.submittedModelId)
    }

    func test_submitAIChat_afterNewChat_sendsModelIdAgain() {
        mockPreferences.selectedModelId = "gpt-5"
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "first", mode: .aiChat)
        sut.startNewChat()
        sut.showExpanded()
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "new chat prompt", mode: .aiChat)
        XCTAssertEqual(mockDelegate.submittedModelId, "gpt-5")
    }

    func test_submitAIChat_emptyPersistedModelId_sendsNilModelId() {
        mockPreferences.selectedModelId = nil
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertNil(mockDelegate.submittedModelId)
    }

    // MARK: - Attachments Change Publisher

    func test_addImageAttachment_publishesAttachmentsChange() {
        configureImageAttachments()
        let exp = expectation(description: "attachmentsChange fires")
        sut.attachmentsChangePublisher
            .sink { exp.fulfill() }
            .store(in: &cancellables)

        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 10, height: 10)))
        }
        sut.addImageAttachment(image: image, fileName: "test.png")
        waitForExpectations(timeout: 1)
    }

    func test_clearAttachments_publishesAttachmentsChange() {
        configureImageAttachments()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: 10, height: 10)))
        }
        sut.addImageAttachment(image: image, fileName: "test.png")

        let exp = expectation(description: "attachmentsChange fires on clear")
        var fired = false
        sut.attachmentsChangePublisher
            .sink { if !fired { fired = true; exp.fulfill() } }
            .store(in: &cancellables)

        sut.clearAttachments()
        waitForExpectations(timeout: 1)
    }

    // MARK: - Handler hasSubmittedPrompt Sync

    func test_handlerHasSubmittedPrompt_syncedAfterPromptSubmit() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        XCTAssertTrue(sut.viewController.handler.hasSubmittedPrompt)
    }

    func test_handlerHasSubmittedPrompt_syncedAfterStartNewChat() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        sut.startNewChat()
        XCTAssertFalse(sut.viewController.handler.hasSubmittedPrompt)
    }

    func test_handlerHasSubmittedPrompt_syncedAfterBindWithExistingChat() {
        let userScript = makeTestUserScript()
        sut.bindToTab(userScript, hasExistingChat: true)
        XCTAssertTrue(sut.viewController.handler.hasSubmittedPrompt)
    }

    func test_handlerHasSubmittedPrompt_syncedAfterUnbind() {
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)
        sut.unbind()
        XCTAssertFalse(sut.viewController.handler.hasSubmittedPrompt)
    }

    // MARK: - startNewChat Text Clearing

    func test_startNewChat_clearsText() {
        sut.showExpanded()
        sut.viewController.text = "draft message"
        sut.startNewChat()
        XCTAssertEqual(sut.viewController.text, "")
    }

    func test_startNewChat_resetsTextState() {
        sut.showExpanded()
        sut.viewController.text = "draft message"
        sut.startNewChat()
        XCTAssertEqual(sut.textState, .empty)
    }

    func test_startNewChat_resetsVoiceSessionActive() {
        sut.showExpanded()
        sut.isVoiceSessionActive = true
        sut.startNewChat()
        XCTAssertFalse(sut.isVoiceSessionActive)
    }

    // MARK: - Toggle State Persistence

    func test_submitSearch_commitsInputModeToStorage() {
        sut.activateFromOmnibar(inputMode: .search)
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "query", mode: .search)
        XCTAssertEqual(mockToggleModeStorage.restore(), .search)
    }

    func test_submitAIChat_commitsInputModeToStorage() {
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "prompt", mode: .aiChat)
        XCTAssertEqual(mockToggleModeStorage.restore(), .aiChat)
    }

    func test_submitSearch_notifiesDelegateOfCommit() {
        sut.activateFromOmnibar(inputMode: .search)
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "query", mode: .search)
        XCTAssertEqual(mockDelegate.committedMode, .search)
    }

    func test_submitAIChat_notifiesDelegateOfCommit() {
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "prompt", mode: .aiChat)
        XCTAssertEqual(mockDelegate.committedMode, .aiChat)
    }

    func test_activateFromOmnibar_setsCommittedInputMode() {
        sut.activateFromOmnibar(inputMode: .aiChat)
        XCTAssertEqual(sut.committedInputMode, .aiChat)
    }

    func test_toggleWithoutSubmit_doesNotCommit() {
        sut.activateFromOmnibar(inputMode: .search)
        sut.updateInputMode(.aiChat, animated: false)
        XCTAssertNil(mockToggleModeStorage.restore(), "Toggling without submitting should not persist")
        XCTAssertEqual(sut.committedInputMode, .search, "Committed mode should not change on toggle")
    }

    func test_deactivateToOmnibar_revertsToCommittedMode() {
        sut.activateFromOmnibar(inputMode: .search)
        sut.updateInputMode(.aiChat, animated: false)
        sut.deactivateToOmnibar()
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_externalSubmission_commitsCurrentMode() {
        sut.activateFromOmnibar(inputMode: .aiChat)
        mockDelegate.committedMode = nil
        sut.handleExternalSubmission(.prompt)
        XCTAssertEqual(mockToggleModeStorage.restore(), .aiChat)
        XCTAssertEqual(mockDelegate.committedMode, .aiChat)
    }

    func test_inlineVoiceSearchTap_requestsVoiceSearch() {
        sut.updateVoiceSearchAvailability(true)

        sut.viewController.handler.microphoneButtonTapped()

        XCTAssertEqual(mockDelegate.didRequestVoiceSearchCount, 1)
        XCTAssertEqual(mockDelegate.didRequestAIVoiceChatCount, 0)
    }

    func test_collapsedAIVoiceChatButtonTap_requestsAIVoiceChat() {
        sut.updateAIVoiceChatAvailability(true)
        sut.showCollapsed()

        sut.viewController.handler.microphoneButtonTapped()

        XCTAssertEqual(mockDelegate.didRequestAIVoiceChatCount, 1)
        XCTAssertEqual(mockDelegate.didRequestVoiceSearchCount, 0)
    }

    func test_initialCollapsedAIVoiceChatButton_usesPlainWaveformStyle() {
        sut.updateAIVoiceChatAvailability(true)
        sut.showCollapsed()

        let voiceButton = findButton(accessibilityIdentifier: "Browser.OmniBar.Button.VoiceSearch", in: sut.viewController.view)

        XCTAssertEqual(voiceButton?.backgroundColor, .clear)
        XCTAssertEqual(voiceButton?.layer.cornerRadius, 0)
    }

    func test_expandedAIChatInlineVoiceSearchTap_requestsVoiceSearch() {
        sut.updateVoiceSearchAvailability(true)
        sut.updateAIVoiceChatAvailability(true)
        sut.showExpanded(inputMode: .aiChat)

        sut.viewController.handler.microphoneButtonTapped()

        XCTAssertEqual(mockDelegate.didRequestVoiceSearchCount, 1)
        XCTAssertEqual(mockDelegate.didRequestAIVoiceChatCount, 0)
    }

    func test_expandedAIChatInlineVoiceSearchTap_whenVoiceSearchDisabled_ignoresStaleTap() {
        sut.updateVoiceSearchAvailability(false)
        sut.updateAIVoiceChatAvailability(true)
        sut.showExpanded(inputMode: .aiChat)

        sut.viewController.handler.microphoneButtonTapped()

        XCTAssertEqual(mockDelegate.didRequestVoiceSearchCount, 0)
        XCTAssertEqual(mockDelegate.didRequestAIVoiceChatCount, 0)
    }

    func test_aiVoiceChatTap_requestsAIVoiceChat() {
        sut.viewController.handler.aiVoiceChatButtonTapped()
        XCTAssertEqual(mockDelegate.didRequestAIVoiceChatCount, 1)
        XCTAssertEqual(mockDelegate.didRequestVoiceSearchCount, 0)
    }

    // MARK: - Toolbar Voice Chat State Sync

    func test_showCollapsed_whenAIVoiceChatEnabled_setsToolbarVoiceChatActive() {
        sut.updateAIVoiceChatAvailability(true)
        sut.showCollapsed()
        XCTAssertTrue(sut.viewController.isToolbarAIVoiceChatActive)
    }

    func test_showExpanded_inSearchMode_clearsToolbarVoiceChatActive() {
        sut.updateAIVoiceChatAvailability(true)
        sut.showExpanded(inputMode: .search)
        XCTAssertFalse(sut.viewController.isToolbarAIVoiceChatActive)
    }

    func test_deactivateToOmnibar_refreshesToolbarVoiceChatFlag() {
        sut.updateAIVoiceChatAvailability(true)
        sut.activateFromOmnibar(inputMode: .aiChat)
        XCTAssertTrue(sut.viewController.isToolbarAIVoiceChatActive)

        sut.updateInputMode(.search, animated: false)
        XCTAssertFalse(sut.viewController.isToolbarAIVoiceChatActive)

        sut.deactivateToOmnibar()
        XCTAssertTrue(sut.viewController.isToolbarAIVoiceChatActive)
    }

    // MARK: - AI Chat Shortcut

    func test_updateAIChatShortcutAvailability_propagatesToHandler() {
        sut.updateAIChatShortcutAvailability(true)
        XCTAssertTrue(sut.viewController.handler.isAIChatShortcutAvailable)

        sut.updateAIChatShortcutAvailability(false)
        XCTAssertFalse(sut.viewController.handler.isAIChatShortcutAvailable)
    }

    func test_unifiedToggleInputVCDidTapAIChatShortcut_invokesDelegate() {
        XCTAssertEqual(mockDelegate.didRequestAIChatCount, 0)

        sut.unifiedToggleInputVCDidTapAIChatShortcut(sut.viewController)

        XCTAssertEqual(mockDelegate.didRequestAIChatCount, 1)
        XCTAssertEqual(mockDelegate.didRequestAIChatPrefilledText, "")
    }

    func test_unifiedToggleInputVCDidTapAIChatShortcut_forwardsCurrentText() {
        sut.viewController.handler.updateCurrentText("hello")

        sut.unifiedToggleInputVCDidTapAIChatShortcut(sut.viewController)

        XCTAssertEqual(mockDelegate.didRequestAIChatPrefilledText, "hello")
    }

    // MARK: - Helpers

    private func configureImageAttachments() {
        mockPreferences.selectedModelId = "image-model"
        sut.modelStore.models = [makeModel(id: "image-model", access: true, supportsImageUpload: true)]
        sut.modelStore.attachmentLimits = makeLimits()
    }

    private func makeBridgeReadyUserScript() -> AIChatUserScript {
        let userScript = makeTestUserScript()
        let webView = WKWebView()
        let broker = UserScriptMessageBroker(context: "test", requiresRunInPageContentWorld: true)
        userScript.with(broker: broker)
        userScript.webView = webView
        return userScript
    }

    private func makeModel(id: String,
                           access: Bool,
                           supportsImageUpload: Bool = false,
                           supportedTools: [AIChatRAGTool] = [],
                           accessTier: [String] = [],
                           supportedReasoningEffort: [AIChatReasoningEffort] = []) -> AIChatModel {
        AIChatModel(id: id, name: id, provider: .unknown, supportsImageUpload: supportsImageUpload,
                    supportedTools: supportedTools, entityHasAccess: access,
                    accessTier: accessTier, supportedReasoningEffort: supportedReasoningEffort)
    }

    private func hasQueryItem(in components: URLComponents?, name: String, value: String) -> Bool {
        components?.queryItems?.contains { $0.name == name && $0.value == value } == true
    }

    private func makeLimits() -> AIChatAttachmentTierLimits {
        AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(maxPerConversation: 3, maxFileSizeMB: 5, maxTotalFileSizeBytes: 5_242_880, maxPagesPerFile: 8),
            images: AIChatAttachmentImageLimits(maxPerTurn: 3, maxPerConversation: 5, maxInputCharsWithAttachments: 4500)
        )
    }

    private func toolsMenuActions() -> [UIAction] {
        // Tools are grouped into an inline submenu (for the divider), so flatten recursively.
        func flatten(_ elements: [UIMenuElement]) -> [UIAction] {
            elements.flatMap { element -> [UIAction] in
                if let action = element as? UIAction {
                    return [action]
                } else if let submenu = element as? UIMenu {
                    return flatten(submenu.children)
                }
                return []
            }
        }
        return flatten(sut.viewController.toolsMenu?.children ?? [])
    }

    private func findButton(accessibilityIdentifier: String, in view: UIView) -> UIButton? {
        for subview in view.subviews {
            if let button = subview as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
                return button
            }
            if let button = findButton(accessibilityIdentifier: accessibilityIdentifier, in: subview) {
                return button
            }
        }
        return nil
    }

    // MARK: - App-menu forwarding (Duck.ai tab UTI bottom-right)

    func test_appMenuTap_forwardsThroughChainToDelegate() {
        XCTAssertEqual(mockDelegate.didRequestAppMenuCount, 0)
        sut.unifiedToggleInputVCDidTapAppMenu(sut.viewController)
        XCTAssertEqual(mockDelegate.didRequestAppMenuCount, 1)
    }

    func test_appMenuTap_suppressedWhileOnboardingLocked() {
        sut.setOnboardingControlsLocked(true)
        sut.unifiedToggleInputVCDidTapAppMenu(sut.viewController)
        XCTAssertEqual(mockDelegate.didRequestAppMenuCount, 0)
    }
}

// MARK: - Toolbar Layout

@MainActor
final class UnifiedToggleInputToolbarViewTests: XCTestCase {

    func test_compactWidthWithLongModelName_keepsSubmitButtonVisible() {
        let sut = UnifiedToggleInputToolbarView()
        sut.translatesAutoresizingMaskIntoConstraints = false
        sut.modelName = "Claude Haiku 4.5 with a long label"

        let container = UIView(frame: CGRect(x: 0, y: 0, width: 280, height: 56))
        container.addSubview(sut)
        NSLayoutConstraint.activate([
            sut.topAnchor.constraint(equalTo: container.topAnchor),
            sut.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sut.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sut.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        container.layoutIfNeeded()

        guard let submitButton = findButton(accessibilityLabel: UserText.aiChatToolbarSubmitButtonAccessibilityLabel, in: sut) else {
            XCTFail("Expected to find submit button")
            return
        }

        let submitFrame = submitButton.convert(submitButton.bounds, to: sut)
        XCTAssertGreaterThanOrEqual(submitFrame.minX, sut.bounds.minX)
        XCTAssertLessThanOrEqual(submitFrame.maxX, sut.bounds.maxX)
    }

    func test_stopGeneratingButtonMatchesSubmitLayoutAndUsesMinimumHitTarget() {
        let sut = UnifiedToggleInputToolbarView()
        sut.translatesAutoresizingMaskIntoConstraints = false

        let container = UIView(frame: CGRect(x: 0, y: 0, width: 280, height: 56))
        container.addSubview(sut)
        NSLayoutConstraint.activate([
            sut.topAnchor.constraint(equalTo: container.topAnchor),
            sut.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sut.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sut.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        container.layoutIfNeeded()

        guard let submitButton = findButton(accessibilityLabel: UserText.aiChatToolbarSubmitButtonAccessibilityLabel, in: sut) else {
            XCTFail("Expected to find submit button")
            return
        }

        let submitFrame = submitButton.convert(submitButton.bounds, to: sut)
        sut.isGenerating = true
        container.layoutIfNeeded()

        guard let stopButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.StopGenerating", in: sut) else {
            XCTFail("Expected to find stop generating button")
            return
        }

        let stopFrame = stopButton.convert(stopButton.bounds, to: sut)
        XCTAssertEqual(stopFrame.width, submitFrame.width, accuracy: 0.5)
        XCTAssertEqual(stopFrame.height, submitFrame.height, accuracy: 0.5)
        XCTAssertEqual(stopButton.image(for: .normal)?.size, CGSize(width: 24, height: 24))
        XCTAssertTrue(stopButton.hitTest(CGPoint(x: -1, y: stopButton.bounds.midY), with: nil) === stopButton)
    }

    func test_isGenerating_disablesToolbarConfigurationButtons() {
        let sut = UnifiedToggleInputToolbarView()
        sut.isImageButtonEnabled = true
        sut.selectedTool = .webSearch

        let attachmentButton = findButton(accessibilityLabel: UserText.aiChatToolbarAttachButtonAccessibilityLabel, in: sut)
        let toolsButton = findButton(accessibilityLabel: UserText.aiChatToolbarToolsButtonAccessibilityLabel, in: sut)
        let reasoningButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.Reasoning", in: sut)
        let modelChipButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.ModelChip", in: sut)
        let selectedToolClearButton = findButton(accessibilityLabel: UserText.aiChatToolbarClearSelectedToolAccessibilityLabel, in: sut)

        sut.isGenerating = true

        XCTAssertFalse(attachmentButton?.isEnabled ?? true)
        XCTAssertFalse(toolsButton?.isEnabled ?? true)
        XCTAssertFalse(reasoningButton?.isEnabled ?? true)
        XCTAssertFalse(modelChipButton?.isEnabled ?? true)
        XCTAssertFalse(selectedToolClearButton?.isEnabled ?? true)

        sut.isGenerating = false

        XCTAssertTrue(attachmentButton?.isEnabled ?? false)
        XCTAssertTrue(toolsButton?.isEnabled ?? false)
        XCTAssertTrue(reasoningButton?.isEnabled ?? false)
        XCTAssertTrue(modelChipButton?.isEnabled ?? false)
        XCTAssertTrue(selectedToolClearButton?.isEnabled ?? false)
    }

    func test_isGenerating_doesNotReenableUnavailableAttachmentButton() {
        let sut = UnifiedToggleInputToolbarView()
        sut.isImageButtonEnabled = false

        let attachmentButton = findButton(accessibilityLabel: UserText.aiChatToolbarAttachButtonAccessibilityLabel, in: sut)
        let toolsButton = findButton(accessibilityLabel: UserText.aiChatToolbarToolsButtonAccessibilityLabel, in: sut)

        sut.isGenerating = true
        sut.isGenerating = false

        XCTAssertFalse(attachmentButton?.isEnabled ?? true)
        XCTAssertTrue(toolsButton?.isEnabled ?? false)
    }

    func test_reasoningButton_hasAccessibilityIdentifier() {
        let sut = UnifiedToggleInputToolbarView()

        let reasoningButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.Reasoning", in: sut)

        XCTAssertEqual(reasoningButton?.accessibilityLabel, UserText.aiChatToolbarReasoningButtonAccessibilityLabel)
        if #available(iOS 16.0, *) {
            XCTAssertEqual(reasoningButton?.preferredMenuElementOrder, .fixed)
        }
    }

    func test_modelChipButton_usesFixedMenuElementOrder() {
        let sut = UnifiedToggleInputToolbarView()

        let modelChipButton = findButton(accessibilityIdentifier: "AIChat.Toolbar.Button.ModelChip", in: sut)

        XCTAssertNotNil(modelChipButton)
        if #available(iOS 16.0, *) {
            XCTAssertEqual(modelChipButton?.preferredMenuElementOrder, .fixed)
        }
    }

    private func findButton(accessibilityLabel: String, in view: UIView) -> UIButton? {
        for subview in view.subviews {
            if let button = subview as? UIButton, button.accessibilityLabel == accessibilityLabel {
                return button
            }
            if let button = findButton(accessibilityLabel: accessibilityLabel, in: subview) {
                return button
            }
        }
        return nil
    }

    private func findButton(accessibilityIdentifier: String, in view: UIView) -> UIButton? {
        for subview in view.subviews {
            if let button = subview as? UIButton, button.accessibilityIdentifier == accessibilityIdentifier {
                return button
            }
            if let button = findButton(accessibilityIdentifier: accessibilityIdentifier, in: subview) {
                return button
            }
        }
        return nil
    }

    // MARK: - aiChatTabHideToggle truth table

    func test_aiChatTabHideToggle_off_onAITab_togglesShowsAccordingToUserSetting() {
        let coord = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            hidesToggleOnDuckAITab: false,
            preferences: MockAIChatPreferences()
        )
        coord.showExpanded(inputMode: .aiChat)
        XCTAssertTrue(coord.isAITabState)
        XCTAssertTrue(coord.computeRenderState().cardLayout.showsToggle)
    }

    func test_aiChatTabHideToggle_on_onAITab_hidesToggleRegardlessOfUserSetting() {
        let coord = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            hidesToggleOnDuckAITab: true,
            preferences: MockAIChatPreferences()
        )
        coord.showExpanded(inputMode: .aiChat)
        XCTAssertTrue(coord.isAITabState)
        XCTAssertFalse(coord.computeRenderState().cardLayout.showsToggle)
    }

    func test_aiChatTabHideToggle_on_offAITab_doesNotAffectToggleVisibility() {
        let coord = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            hidesToggleOnDuckAITab: true,
            preferences: MockAIChatPreferences()
        )
        coord.activateFromOmnibar(inputMode: .aiChat)
        XCTAssertFalse(coord.isAITabState)
        XCTAssertTrue(coord.computeRenderState().cardLayout.showsToggle)
    }

    // MARK: - isToggleVisible (drives swipe-between-modes gating alongside the toggle row)

    func test_isToggleVisible_returnsFalse_whenUserSettingOff() {
        let coord = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: false,
            hidesToggleOnDuckAITab: false,
            preferences: MockAIChatPreferences()
        )
        coord.showExpanded(inputMode: .aiChat)
        XCTAssertFalse(coord.isToggleVisible, "Swipe must follow the user setting when off")
    }

    func test_isToggleVisible_returnsTrue_onAITab_whenKillSwitchOff() {
        let coord = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            hidesToggleOnDuckAITab: false,
            preferences: MockAIChatPreferences()
        )
        coord.showExpanded(inputMode: .aiChat)
        XCTAssertTrue(coord.isAITabState)
        XCTAssertTrue(coord.isToggleVisible, "AI tab with kill-switch off must keep swipe enabled when user setting is on")
    }

    func test_isToggleVisible_returnsFalse_onAITab_whenKillSwitchOn() {
        let coord = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            hidesToggleOnDuckAITab: true,
            preferences: MockAIChatPreferences()
        )
        coord.showExpanded(inputMode: .aiChat)
        XCTAssertTrue(coord.isAITabState)
        XCTAssertFalse(coord.isToggleVisible, "Kill-switch on an AI tab must also disable the swipe gesture, not just the toggle row")
    }

    func test_isToggleVisible_returnsTrue_offAITab_whenKillSwitchOn() {
        let coord = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            hidesToggleOnDuckAITab: true,
            preferences: MockAIChatPreferences()
        )
        coord.activateFromOmnibar(inputMode: .aiChat)
        XCTAssertFalse(coord.isAITabState)
        XCTAssertTrue(coord.isToggleVisible, "Kill-switch only applies on Duck.ai tabs — non-AI tabs follow the user setting")
    }

    // MARK: - Content swipe suppression while the toggle pill is being dragged

    func test_draggingToggle_disablesContentSwipe_soTheTwoGesturesDoNotGlitchEachOther() {
        let coord = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            hidesToggleOnDuckAITab: false,
            preferences: MockAIChatPreferences()
        )
        coord.showExpanded(inputMode: .aiChat)
        XCTAssertTrue(coord.contentViewController.isSwipeEnabled, "Precondition: content swipe is enabled when the toggle is visible")

        coord.unifiedToggleInputVC(coord.viewController, isDraggingToggle: true)

        XCTAssertFalse(coord.contentViewController.isSwipeEnabled, "Content swipe must be suppressed while the toggle pill is being dragged")
    }

    func test_endingToggleDrag_restoresContentSwipeToToggleVisibility() {
        let coord = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            hidesToggleOnDuckAITab: false,
            preferences: MockAIChatPreferences()
        )
        coord.showExpanded(inputMode: .aiChat)

        coord.unifiedToggleInputVC(coord.viewController, isDraggingToggle: true)
        coord.unifiedToggleInputVC(coord.viewController, isDraggingToggle: false)

        XCTAssertEqual(coord.contentViewController.isSwipeEnabled, coord.isToggleVisible, "Once the drag ends, content swipe must return to following toggle visibility")
        XCTAssertTrue(coord.contentViewController.isSwipeEnabled)
    }

    func test_endingToggleDrag_keepsContentSwipeDisabled_whenToggleIsNotVisible() {
        let coord = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: false,
            hidesToggleOnDuckAITab: false,
            preferences: MockAIChatPreferences()
        )
        coord.showExpanded(inputMode: .aiChat)
        XCTAssertFalse(coord.isToggleVisible)

        coord.unifiedToggleInputVC(coord.viewController, isDraggingToggle: true)
        coord.unifiedToggleInputVC(coord.viewController, isDraggingToggle: false)

        XCTAssertFalse(coord.contentViewController.isSwipeEnabled, "Restoring after a drag must not enable swipe when the toggle is hidden")
    }

    /// Mirrors `test_syncInputModeFromExternalSource_toggleDisabled_forcesAIChatInAITabSession`
    /// for the kill-switch path: the toggle row is hidden by the remote flag (not by the user
    /// setting), so the user has no way to flip back — `effectiveInputMode` must clamp.
    func test_syncInputModeFromExternalSource_killSwitchOn_forcesAIChatOnAITab() {
        let coord = UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            hidesToggleOnDuckAITab: true,
            preferences: MockAIChatPreferences()
        )
        coord.showExpanded(inputMode: .aiChat)
        XCTAssertTrue(coord.isAITabState)
        coord.syncInputModeFromExternalSource(.search)
        XCTAssertEqual(coord.inputMode, .aiChat, "Programmatic .search on a kill-switched Duck.ai tab must clamp to .aiChat")
    }
}

// MARK: - Mock Delegate

@MainActor
private final class MockUnifiedToggleInputDelegate: UnifiedToggleInputDelegate {
    var submittedPrompt: String?
    var submittedModelId: String?
    var submittedTools: [AIChatRAGTool]?
    var submittedReasoningEffort: AIChatReasoningEffort?
    var submittedImages: [AIChatNativePrompt.NativePromptImage]?
    var submittedFiles: [AIChatNativePrompt.NativePromptFile]?
    var submittedQuery: String?
    var committedMode: TextEntryMode?
    var didRequestVoiceSearchCount = 0
    var didRequestAIVoiceChatCount = 0
    var didRequestAIChatCount = 0
    var didRequestAppMenuCount = 0

    func unifiedToggleInputDidSubmitPrompt(_ prompt: String, modelId: String?, tools: [AIChatRAGTool]?, reasoningEffort: AIChatReasoningEffort?, images: [AIChatNativePrompt.NativePromptImage]?, files: [AIChatNativePrompt.NativePromptFile]?) {
        submittedPrompt = prompt
        submittedModelId = modelId
        submittedTools = tools
        submittedReasoningEffort = reasoningEffort
        submittedImages = images
        submittedFiles = files
    }
    func unifiedToggleInputDidSubmitQuery(_ query: String) { submittedQuery = query }
    func unifiedToggleInputDidRequestVoiceSearch() { didRequestVoiceSearchCount += 1 }
    func unifiedToggleInputDidRequestAIVoiceChat() { didRequestAIVoiceChatCount += 1 }
    var didRequestAIChatPrefilledText: String?
    func unifiedToggleInputDidRequestAIChat(prefilledText: String) {
        didRequestAIChatCount += 1
        didRequestAIChatPrefilledText = prefilledText
    }
    func unifiedToggleInputDidChangeHeight() {}
    func unifiedToggleInputDidCommitMode(_ mode: TextEntryMode) {
        committedMode = mode
    }
    func unifiedToggleInputDidRequestFire() {}
    func unifiedToggleInputDidRequestAppMenu() { didRequestAppMenuCount += 1 }
}

private final class MockAIChatPreferences: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

private final class MockToggleModeStorage: ToggleModeStoring {
    private var storedMode: TextEntryMode?
    func save(_ mode: TextEntryMode) { storedMode = mode }
    func restore() -> TextEntryMode? { storedMode }
}

@MainActor
private final class FakeInputStateStore: UnifiedInputStateStoring {
    var states: [TabUID: TabInputState] = [:]
    var lastUsedDefaults = LastUsedInputDefaults(
        toggleMode: .search,
        selectedModelID: nil,
        selectedReasoningMode: nil,
        selectedTool: nil
    )

    var lastUsed: LastUsedInputDefaults { lastUsedDefaults }

    func state(for uid: TabUID) -> TabInputState {
        states[uid] ?? TabInputState(toggleMode: lastUsedDefaults.toggleMode)
    }

    func update(_ state: TabInputState, for uid: TabUID) {
        states[uid] = state
    }

    func recordUserChoice(_ state: TabInputState, for uid: TabUID, isNewChatContext: Bool) {
        states[uid] = state
        lastUsedDefaults = LastUsedInputDefaults(
            toggleMode: lastUsedDefaults.toggleMode,
            selectedModelID: isNewChatContext ? state.selectedModelID : lastUsedDefaults.selectedModelID,
            selectedReasoningMode: state.selectedReasoningMode,
            selectedTool: state.selectedTool
        )
    }

    func commitToggleMode(_ mode: TextEntryMode) {
        lastUsedDefaults = LastUsedInputDefaults(
            toggleMode: mode,
            selectedModelID: lastUsedDefaults.selectedModelID,
            selectedReasoningMode: lastUsedDefaults.selectedReasoningMode,
            selectedTool: lastUsedDefaults.selectedTool
        )
    }

    func remove(for uid: TabUID) {
        states.removeValue(forKey: uid)
    }
}

// MARK: - Per-tab state regression tests

@MainActor
final class UnifiedToggleInputCoordinatorPerTabStateTests: XCTestCase {

    private func makeSUT(
        stateStore: UnifiedInputStateStoring,
        duckAIWideEventInstrumentation: DuckAIWideEventInstrumentation? = nil
    ) -> UnifiedToggleInputCoordinator {
        UnifiedToggleInputCoordinator(
            host: .omnibar,
            isToggleEnabled: true,
            preferences: MockAIChatPreferencesForPerTab(),
            toggleModeStorage: MockToggleModeStorageForPerTab(),
            stateStore: stateStore,
            duckAIWideEventInstrumentation: duckAIWideEventInstrumentation
        )
    }

    func test_activateForTab_appliesStoredText() {
        let store = FakeInputStateStore()
        store.states["tab-A"] = TabInputState(text: "remembered")
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        XCTAssertEqual(sut.currentText, "remembered")
    }

    func test_activateForTab_flushesPreviousTab() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.setText("typed")
        sut.activateForTab("tab-B")
        XCTAssertEqual(store.states["tab-A"]?.text, "typed")
    }

    func test_activateForTab_roundTripsVoiceSessionActive() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.isVoiceSessionActive = true
        sut.activateForTab("tab-B")
        XCTAssertFalse(sut.isVoiceSessionActive)
        sut.activateForTab("tab-A")
        XCTAssertTrue(sut.isVoiceSessionActive)
    }

    func test_activateForTab_roundTripsModelPickerForcedVisible() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        _ = sut.prepareExternalPromptSubmission()
        sut.presentModelPickerForActiveChat()
        XCTAssertFalse(sut.viewController.isModelChipHidden)

        sut.activateForTab("tab-B")
        XCTAssertTrue(sut.viewController.isModelChipHidden)

        sut.activateForTab("tab-A")
        XCTAssertFalse(sut.viewController.isModelChipHidden)
    }

    func test_bindToTab_afterActivateForTab_preservesModelPickerPin() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        let scriptA = makeTestUserScript()
        let scriptB = makeTestUserScript()

        sut.activateForTab("tab-A")
        _ = sut.prepareExternalPromptSubmission()
        sut.presentModelPickerForActiveChat()
        sut.bindToTab(scriptA, hasExistingChat: true)
        XCTAssertFalse(sut.viewController.isModelChipHidden)

        sut.activateForTab("tab-B")
        sut.bindToTab(scriptB, hasExistingChat: true)

        sut.activateForTab("tab-A")
        sut.bindToTab(scriptA, hasExistingChat: true)

        XCTAssertFalse(sut.viewController.isModelChipHidden,
                      "bindToTab must not reset the pin applyState restored — mirrors AI-tab → AI-tab switch")
    }

    func test_endToEnd_twoTabSwitches_preserveIndependentState() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)

        sut.activateForTab("tab-A")
        sut.setText("from A")
        sut.updateInputMode(.aiChat, animated: false)

        sut.activateForTab("tab-B")
        sut.setText("from B")
        sut.updateInputMode(.search, animated: false)

        sut.activateForTab("tab-A")
        XCTAssertEqual(sut.currentText, "from A")
        XCTAssertEqual(sut.inputMode, .aiChat)

        sut.activateForTab("tab-B")
        XCTAssertEqual(sut.currentText, "from B")
        XCTAssertEqual(sut.inputMode, .search)
    }

    func test_textChange_propagatesToStore() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.setText("typing")
        XCTAssertEqual(store.states["tab-A"]?.text, "typing")
    }

    // Regression: clearText is a dismiss-time visible-input cleanup. With per-tab
    // persistence it must NOT wipe the stored draft — the user may re-activate the
    // same tab and expect their typed text back. Without this guard, tapping outside
    // the omnibar (or opening a new tab) eventually fires the deferred clearText and
    // overwrites the per-tab entry with empty text.
    func test_clearText_doesNotWipeStoreEntry() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "draft to keep")
        XCTAssertEqual(store.states["tab-A"]?.text, "draft to keep")

        sut.clearText()
        XCTAssertEqual(store.states["tab-A"]?.text, "draft to keep",
                       "Dismiss-time clearText must preserve the per-tab stored draft.")
    }

    func test_hide_doesNotWipeStoreEntryForCurrentTab() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [makeModel(id: "file-model", access: true, supportedFileTypes: ["application/pdf"])]
        sut.modelStore.attachmentLimits = makeLimits()
        sut.activateForTab("tab-A")
        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "draft to keep")
        sut.addFileAttachment(makeFileAttachment())
        XCTAssertEqual(store.states["tab-A"]?.text, "draft to keep")
        XCTAssertEqual(store.states["tab-A"]?.attachments.count, 1)

        sut.hide()

        XCTAssertEqual(store.states["tab-A"]?.text, "draft to keep",
                       "hide() must preserve the previous tab's stored draft.")
        XCTAssertEqual(store.states["tab-A"]?.attachments.count, 1)
        XCTAssertEqual(sut.viewController.text, "")
        XCTAssertEqual(sut.viewController.currentAttachments.count, 0)
    }

    // Regression: a Duck.ai tab → non-AI tab transition routes through
    // `resetUnifiedToggleInputForTabTransition` → `coordinator.hide()`, which clears
    // currentTabUID before the next `activateForTab` runs. Without firing the wide-event
    // cancellation here, the matching call in `activateForTab` sees `previous == nil`
    // and the active Duck.ai prompt flow orphans until the next app launch.
    func test_hide_firesTabSwitchedAwayDuringGenerationForCurrentTab() {
        let store = FakeInputStateStore()
        let instrumentation = MockDuckAIWideEventInstrumentation()
        let sut = makeSUT(stateStore: store, duckAIWideEventInstrumentation: instrumentation)
        sut.activateForTab("tab-A")

        sut.hide()

        XCTAssertEqual(instrumentation.tabSwitchedAwayCalls, ["tab-A"])
    }

    func test_hide_doesNotFireTabSwitchedAway_whenNoCurrentTab() {
        let store = FakeInputStateStore()
        let instrumentation = MockDuckAIWideEventInstrumentation()
        let sut = makeSUT(stateStore: store, duckAIWideEventInstrumentation: instrumentation)

        sut.hide()

        XCTAssertTrue(instrumentation.tabSwitchedAwayCalls.isEmpty)
    }

    func test_duckAISubmissionAfterHideUsesLastActivatedTabScope() {
        let store = FakeInputStateStore()
        let instrumentation = MockDuckAIWideEventInstrumentation()
        let sut = makeSUT(stateStore: store, duckAIWideEventInstrumentation: instrumentation)
        sut.activateForTab("tab-A")
        sut.hide()

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)

        XCTAssertEqual(instrumentation.submissionStartedScopes, [.tab("tab-A")])
    }

    func test_submitAfterHide_clearsPersistedModelPickerPin() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        _ = sut.prepareExternalPromptSubmission()
        sut.presentModelPickerForActiveChat()
        XCTAssertTrue(store.states["tab-A"]?.isModelPickerForcedVisible == true)

        sut.hide()
        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .aiChat)

        XCTAssertEqual(store.states["tab-A"]?.isModelPickerForcedVisible, false)
    }

    // Regression: applyState must always sync the live model store from per-tab
    // state, even when state values are nil. Otherwise the previous tab's reasoning
    // mode (or model id) leaks through preferences, and the next snapshot writes
    // that leaked value into the current tab's stored state — corrupting it.
    func test_applyState_clearsLiveReasoningWhenStateHasNoReasoning() {
        let store = FakeInputStateStore()
        store.states["tab-A"] = TabInputState(toggleMode: .aiChat, selectedReasoningMode: .reasoning)
        store.states["tab-B"] = TabInputState(toggleMode: .aiChat, selectedReasoningMode: nil)
        let sut = makeSUT(stateStore: store)

        sut.activateForTab("tab-A")
        XCTAssertEqual(sut.snapshotCurrentState().selectedReasoningMode, .reasoning)

        sut.activateForTab("tab-B")
        XCTAssertNil(sut.snapshotCurrentState().selectedReasoningMode,
                     "Live reasoning must clear to match tab-B's nil state, otherwise it leaks into tab-B's snapshot.")
    }

    func test_applyState_clearsLiveModelIDWhenStateHasNoModel() {
        let store = FakeInputStateStore()
        store.states["tab-A"] = TabInputState(toggleMode: .aiChat, selectedModelID: "claude-opus")
        store.states["tab-B"] = TabInputState(toggleMode: .aiChat, selectedModelID: nil)
        let sut = makeSUT(stateStore: store)

        sut.activateForTab("tab-A")
        sut.activateForTab("tab-B")
        // The live preferences must reflect tab-B's nil model id, not tab-A's.
        XCTAssertNil(sut.modelStore.currentModelId,
                     "Live preferences.selectedModelId must clear when state has nil model id.")
    }

    // Regression: clearText only clears the visible input; the coordinator's tracked
    // draft (currentText) must remain so the very next activateForTab flush captures
    // the user's text, not the cleared visible state.
    func test_clearText_thenActivateAnotherTab_flushesPreviousTabDraft() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "tab A draft")
        sut.clearText()

        sut.activateForTab("tab-B")

        XCTAssertEqual(store.states["tab-A"]?.text, "tab A draft",
                       "Flushing the outgoing tab after a dismiss-clear must store the user's draft, not the cleared live state.")
    }

    // Regression: a brand-new tab must not inherit another tab's attachments. The
    // previous tab's attachments are still in the live view at the moment of
    // activateForTab; applyState must clear them before any user can see them.
    func test_activateForTab_newTabDoesNotInheritPreviousTabAttachments() {
        let store = FakeInputStateStore()
        let attachment = UnifiedToggleInputAttachment.image(AIChatImageAttachment(image: UIImage(), fileName: "x.jpg"))
        store.states["tab-1"] = TabInputState(attachments: [attachment])
        let sut = makeSUT(stateStore: store)

        sut.activateForTab("tab-1")
        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)

        // tab-2 has no entry in the store — it should get a fresh empty seed.
        sut.activateForTab("tab-2")
        XCTAssertEqual(sut.viewController.currentAttachments.count, 0,
                       "tab-2 must start with no attachments; the previous tab's strip contents must be cleared.")
    }

    func test_activateForTab_restoresFileAttachmentDraft() {
        let store = FakeInputStateStore()
        let attachment = UnifiedToggleInputAttachment.file(makeFileAttachment())
        store.states["tab-1"] = TabInputState(attachments: [attachment])
        let sut = makeSUT(stateStore: store)

        sut.activateForTab("tab-1")

        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
        XCTAssertTrue(sut.viewController.currentAttachments.first?.isFile ?? false)
    }

    // Regression: submitting a search/prompt empties the live input. The store entry
    // for the active tab must reflect that emptiness eagerly — the visible clear may
    // be deferred to a dismiss animation, but the store entry shouldn't hold the
    // submitted text in the meantime, since a tab switch during the animation would
    // miss the deferred clear.
    func test_submitSearch_clearsStoreEntryEagerly() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.setText("hello")
        XCTAssertEqual(store.states["tab-A"]?.text, "hello")

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "hello", mode: .search)
        XCTAssertEqual(store.states["tab-A"]?.text ?? "", "")
    }

    func test_submitPrompt_clearsStoreTextAndAttachmentsEagerly() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [makeModelWithTools(id: "image-model", supportsImageUpload: true)]
        sut.modelStore.attachmentLimits = makeLimits()
        sut.activateForTab("tab-A")
        sut.setText("ask claude something")
        sut.addImageAttachment(image: UIImage(), fileName: "x.jpg")
        XCTAssertEqual(store.states["tab-A"]?.text, "ask claude something")
        XCTAssertEqual(store.states["tab-A"]?.attachments.count, 1)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "ask claude something", mode: .aiChat)
        XCTAssertEqual(store.states["tab-A"]?.text ?? "", "")
        XCTAssertEqual(store.states["tab-A"]?.attachments.count, 0)
    }

    func test_addFileAttachment_persistsToStore() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [makeModel(id: "file-model", access: true, supportedFileTypes: ["application/pdf"])]
        sut.modelStore.attachmentLimits = makeLimits()
        sut.activateForTab("tab-A")

        sut.addFileAttachment(makeFileAttachment())

        XCTAssertEqual(store.states["tab-A"]?.attachments.count, 1)
        XCTAssertTrue(store.states["tab-A"]?.attachments.first?.isFile ?? false)
    }

    func test_activateForTab_restoresInvalidFileAttachmentDraft() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [makeModel(id: "file-model", access: true, supportedFileTypes: ["application/pdf"])]
        sut.modelStore.attachmentLimits = makeLimits()
        sut.activateForTab("tab-A")
        sut.updateInputMode(.aiChat, animated: false)

        sut.addFileAttachment(makeFileAttachment(pageCount: 9))
        XCTAssertTrue(store.states["tab-A"]?.attachments.first?.isInvalid ?? false)

        sut.activateForTab("tab-B")
        sut.activateForTab("tab-A")

        XCTAssertEqual(sut.viewController.currentAttachments.count, 1)
        XCTAssertTrue(sut.viewController.currentAttachments.first?.isInvalid ?? false)
        XCTAssertEqual(sut.viewController.attachmentValidationMessage, UserText.aiChatAttachmentFileTooManyPages(maxPagesPerFile: 8))
    }

    func test_submitPrompt_whenValidationFails_preservesStoreTextAndAttachments() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [makeModel(id: "file-model", access: true, supportedFileTypes: ["application/pdf"])]
        sut.modelStore.attachmentLimits = makeLimits()
        sut.activateForTab("tab-A")
        sut.addFileAttachment(makeFileAttachment())
        let text = String(repeating: "a", count: 4_501)
        sut.setText(text)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: text, mode: .aiChat)

        XCTAssertEqual(store.states["tab-A"]?.text, text)
        XCTAssertEqual(store.states["tab-A"]?.attachments.count, 1)
        XCTAssertTrue(store.states["tab-A"]?.attachments.first?.isFile ?? false)
    }

    // Regression: user keystrokes flow through unifiedToggleInputVC(_:didChangeText:),
    // not setText(_:), so the persistence must be wired on the delegate callback too.
    func test_didChangeText_propagatesToStore() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "user-typed")
        XCTAssertEqual(store.states["tab-A"]?.text, "user-typed")
    }

    // Regression: tab switch must NOT mutate lastUsed. New tabs should keep inheriting
    // the most recent deliberate choice, not the active tab's mirror.
    func test_activateForTab_doesNotMutateLastUsed() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)

        sut.activateForTab("tab-A")
        sut.updateInputMode(.aiChat, animated: false)
        let lastUsedAfterChoice = store.lastUsed

        sut.activateForTab("tab-B")
        sut.activateForTab("tab-A")

        XCTAssertEqual(store.lastUsed, lastUsedAfterChoice)
    }

    // MARK: - Persistence split: drafts vs user-deliberate choices

    func test_setText_doesNotMutateLastUsed() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        let baseline = store.lastUsed

        sut.setText("just typing")

        XCTAssertEqual(store.lastUsed, baseline)
    }

    func test_didChangeText_doesNotMutateLastUsed() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        let baseline = store.lastUsed

        sut.unifiedToggleInputVC(sut.viewController, didChangeText: "keystrokes")

        XCTAssertEqual(store.lastUsed, baseline)
    }

    func test_addImageAttachment_doesNotMutateLastUsed() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        let baseline = store.lastUsed

        sut.addImageAttachment(image: UIImage(), fileName: "x.jpg")

        XCTAssertEqual(store.lastUsed, baseline)
    }

    func test_addFileAttachment_doesNotMutateLastUsed() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [makeModel(id: "file-model", access: true, supportedFileTypes: ["application/pdf"])]
        sut.modelStore.attachmentLimits = makeLimits()
        sut.activateForTab("tab-A")
        let baseline = store.lastUsed

        sut.addFileAttachment(makeFileAttachment())

        XCTAssertEqual(store.lastUsed, baseline)
    }

    func test_clearAttachments_doesNotMutateLastUsed() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.addImageAttachment(image: UIImage(), fileName: "x.jpg")
        let baseline = store.lastUsed

        sut.clearAttachments()

        XCTAssertEqual(store.lastUsed, baseline)
    }

    // Toggle mode is intentionally treated like a draft: in-flight changes update the
    // per-tab state but must NOT promote to the global `lastUsed` snapshot. Promotion
    // happens via `commitToggleMode` on submit (covered in `UnifiedInputStateStoreTests`).
    func test_updateInputMode_doesNotMutateLastUsedToggleMode() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        let baseline = store.lastUsed.toggleMode

        sut.updateInputMode(.aiChat, animated: false)

        XCTAssertEqual(store.lastUsed.toggleMode, baseline)
    }

    func test_selectTool_mutatesLastUsed() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [makeModelWithTools(id: "gpt-5")]
        sut.activateForTab("tab-A")

        sut.selectTool(.webSearch)

        XCTAssertEqual(store.lastUsed.selectedTool, .webSearch)
    }

    // MARK: - External submission clears the store (P1)

    func test_handleExternalSubmission_query_clearsStoreText() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.setText("submitted via suggestion")
        XCTAssertEqual(store.states["tab-A"]?.text, "submitted via suggestion")

        sut.handleExternalSubmission(.query)

        XCTAssertEqual(store.states["tab-A"]?.text ?? "", "")
    }

    func test_handleExternalSubmission_prompt_clearsStoreTextAndAttachments() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.setText("voice prompt body")
        sut.addImageAttachment(image: UIImage(), fileName: "x.jpg")

        sut.handleExternalSubmission(.prompt)

        XCTAssertEqual(store.states["tab-A"]?.text ?? "", "")
        XCTAssertEqual(store.states["tab-A"]?.attachments.count, 0)
    }

    func test_handleExternalSubmission_resetsCoordinatorCurrentText() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.activateForTab("tab-A")
        sut.setText("about to submit")

        sut.handleExternalSubmission(.query)

        XCTAssertEqual(sut.currentText, "")
    }

    // MARK: - Tool menu selection persists (P2)

    func test_handleToolsMenuSelection_webSearch_persistsSelection() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [makeModelWithTools(id: "gpt-5")]
        sut.activateForTab("tab-A")

        sut.handleToolsMenuSelection(.webSearch)

        XCTAssertEqual(store.states["tab-A"]?.selectedTool, .webSearch)
        XCTAssertEqual(store.lastUsed.selectedTool, .webSearch)
    }

    // MARK: - Tool selection cleared on submit (P1)

    func test_submitAIChat_withSelectedTool_clearsToolFromStore() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [makeModelWithTools(id: "gpt-5")]
        sut.activateForTab("tab-A")
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.selectTool(.webSearch)
        XCTAssertEqual(store.states["tab-A"]?.selectedTool, .webSearch)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "query", mode: .aiChat)

        XCTAssertNil(store.states["tab-A"]?.selectedTool,
                     "After AI submit the store must not retain the selected tool — otherwise reactivation restores it.")
    }

    func test_submitAIChat_withSelectedToolAndAttachments_clearsToolFromStore() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [makeModelWithTools(id: "gpt-5", supportsImageUpload: true)]
        sut.activateForTab("tab-A")
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.addImageAttachment(image: UIImage(), fileName: "x.jpg")
        sut.selectTool(.webSearch)

        sut.unifiedToggleInputVC(sut.viewController, didSubmitText: "query", mode: .aiChat)

        XCTAssertNil(store.states["tab-A"]?.selectedTool)
    }

    func test_handleExternalSubmission_prompt_withSelectedTool_clearsToolFromStore() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [makeModelWithTools(id: "gpt-5")]
        sut.activateForTab("tab-A")
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.selectTool(.webSearch)

        sut.handleExternalSubmission(.prompt)

        XCTAssertNil(store.states["tab-A"]?.selectedTool)
    }

    func test_handleExternalSubmission_prompt_clearsLastUsedSelectedTool() {
        // Regression: the lastUsed snapshot was not cleared on submission, so a fresh tab seeded
        // its state from `trackedLastUsed.selectedTool` and inherited the just-consumed tool
        // selection — surfacing as a sticky chip on the newly-opened chat tab.
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [makeModelWithTools(id: "gpt-5", supportedTools: [.imageGeneration])]
        sut.activateForTab("tab-A")
        sut.activateFromOmnibar(inputMode: .aiChat)
        sut.selectTool(.imageGeneration)
        XCTAssertEqual(store.lastUsed.selectedTool, .imageGeneration)

        sut.handleExternalSubmission(.prompt)

        XCTAssertNil(store.lastUsed.selectedTool)
    }

    // MARK: - Reasoning button visibility on tab switch

    func test_activateForTab_reasoningModel_showsReasoningButton() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [
            makeReasoningModel(id: "smart", supportedReasoningEffort: [.none, .low, .medium]),
            makeReasoningModel(id: "fast", supportedReasoningEffort: [.minimal])
        ]
        store.states["tab-A"] = TabInputState(toggleMode: .aiChat, selectedModelID: "smart")

        sut.activateForTab("tab-A")

        XCTAssertFalse(sut.viewController.isReasoningButtonHidden,
                       "Reasoning-capable model must show the picker after tab activation.")
    }

    func test_activateForTab_nonReasoningModel_hidesReasoningButton() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [
            makeReasoningModel(id: "smart", supportedReasoningEffort: [.none, .low, .medium]),
            makeReasoningModel(id: "fast", supportedReasoningEffort: [.minimal])
        ]
        store.states["tab-A"] = TabInputState(toggleMode: .aiChat, selectedModelID: "fast")

        sut.activateForTab("tab-A")

        XCTAssertTrue(sut.viewController.isReasoningButtonHidden,
                      "Non-reasoning model must hide the picker after tab activation.")
    }

    func test_activateForTab_switchingFromReasoningToNonReasoning_hidesButton() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [
            makeReasoningModel(id: "smart", supportedReasoningEffort: [.none, .low, .medium]),
            makeReasoningModel(id: "fast", supportedReasoningEffort: [.minimal])
        ]
        store.states["tab-A"] = TabInputState(toggleMode: .aiChat, selectedModelID: "smart")
        store.states["tab-B"] = TabInputState(toggleMode: .aiChat, selectedModelID: "fast")

        sut.activateForTab("tab-A")
        XCTAssertFalse(sut.viewController.isReasoningButtonHidden)

        sut.activateForTab("tab-B")

        XCTAssertTrue(sut.viewController.isReasoningButtonHidden,
                      "Switching to a non-reasoning model must re-evaluate visibility and hide the picker.")
    }

    func test_activateForTab_switchingFromNonReasoningToReasoning_showsButton() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [
            makeReasoningModel(id: "smart", supportedReasoningEffort: [.none, .low, .medium]),
            makeReasoningModel(id: "fast", supportedReasoningEffort: [.minimal])
        ]
        store.states["tab-A"] = TabInputState(toggleMode: .aiChat, selectedModelID: "fast")
        store.states["tab-B"] = TabInputState(toggleMode: .aiChat, selectedModelID: "smart")

        sut.activateForTab("tab-A")
        XCTAssertTrue(sut.viewController.isReasoningButtonHidden)

        sut.activateForTab("tab-B")

        XCTAssertFalse(sut.viewController.isReasoningButtonHidden)
    }

    func test_showCollapsed_afterTabSwitch_refreshesReasoningButtonVisibility() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [
            makeReasoningModel(id: "smart", supportedReasoningEffort: [.none, .low, .medium]),
            makeReasoningModel(id: "fast", supportedReasoningEffort: [.minimal])
        ]
        store.states["tab-A"] = TabInputState(toggleMode: .aiChat, selectedModelID: "smart")
        store.states["tab-B"] = TabInputState(toggleMode: .aiChat, selectedModelID: "fast")

        sut.activateForTab("tab-A")
        sut.showExpanded()
        XCTAssertFalse(sut.viewController.isReasoningButtonHidden)

        sut.activateForTab("tab-B")
        sut.showCollapsed()

        XCTAssertTrue(sut.viewController.isReasoningButtonHidden,
                      "showCollapsed must refresh reasoning visibility from the live model.")
    }

    func test_activateFromOmnibar_refreshesReasoningButtonVisibility() {
        let store = FakeInputStateStore()
        let sut = makeSUT(stateStore: store)
        sut.modelStore.models = [
            makeReasoningModel(id: "smart", supportedReasoningEffort: [.none, .low, .medium]),
            makeReasoningModel(id: "fast", supportedReasoningEffort: [.minimal])
        ]
        store.states["tab-A"] = TabInputState(toggleMode: .aiChat, selectedModelID: "fast")

        sut.activateForTab("tab-A")
        sut.activateFromOmnibar(inputMode: .aiChat)

        XCTAssertTrue(sut.viewController.isReasoningButtonHidden,
                      "activateFromOmnibar must reflect the current tab's model reasoning capability.")
    }

    // MARK: - Helpers

    private func makeModel(id: String, access: Bool, supportedFileTypes: [String] = []) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            provider: .unknown,
            supportsImageUpload: false,
            supportedFileTypes: supportedFileTypes,
            entityHasAccess: access
        )
    }

    private func makeModelWithTools(
        id: String,
        supportsImageUpload: Bool = false,
        supportedTools: [AIChatRAGTool] = [.webSearch]
    ) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            provider: .unknown,
            supportsImageUpload: supportsImageUpload,
            supportedTools: supportedTools,
            entityHasAccess: true
        )
    }

    private func makeFileAttachment(fileName: String = "test.pdf", pageCount: Int? = 1) -> AIChatFileAttachment {
        let data = Data(repeating: 0, count: 1_000)
        return AIChatFileAttachment(
            data: data,
            fileName: fileName,
            mimeType: "application/pdf",
            fileSizeBytes: data.count,
            pageCount: pageCount
        )
    }

    private func makeLimits() -> AIChatAttachmentTierLimits {
        AIChatAttachmentTierLimits(
            files: AIChatAttachmentFileLimits(maxPerConversation: 3, maxFileSizeMB: 5, maxTotalFileSizeBytes: 5_242_880, maxPagesPerFile: 8),
            images: AIChatAttachmentImageLimits(maxPerTurn: 3, maxPerConversation: 5, maxInputCharsWithAttachments: 4500)
        )
    }

    private func makeReasoningModel(id: String, supportedReasoningEffort: [AIChatReasoningEffort]) -> AIChatModel {
        AIChatModel(
            id: id,
            name: id,
            shortName: id,
            provider: .openAI,
            supportsImageUpload: false,
            entityHasAccess: true,
            supportedReasoningEffort: supportedReasoningEffort
        )
    }

}

private final class MockAIChatPreferencesForPerTab: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

private final class MockToggleModeStorageForPerTab: ToggleModeStoring {
    private var storedMode: TextEntryMode?
    func save(_ mode: TextEntryMode) { storedMode = mode }
    func restore() -> TextEntryMode? { storedMode }
}

final class MockSwitchBarSubmissionMetrics: SwitchBarSubmissionMetricsProviding {
    private(set) var processedSubmissions: [(text: String, mode: TextEntryMode)] = []

    func process(_ text: String, for submissionMode: TextEntryMode) {
        processedSubmissions.append((text, submissionMode))
    }
}

@MainActor
private final class MockDuckAIWideEventInstrumentation: DuckAIWideEventInstrumentation {
    private(set) var submissionStartedScopes: [DuckAIWideEventFlowScope] = []
    private(set) var tabSwitchedAwayCalls: [TabUID] = []

    func submissionStarted(scope: DuckAIWideEventFlowScope,
                           modelId: String?,
                           userTier: AIChatUserTier,
                           reasoningEffort: AIChatReasoningEffort?,
                           entryPoint: DuckAIPromptWideEventData.EntryPoint,
                           inputMode: DuckAIPromptWideEventData.InputMode,
                           fireMode: Bool,
                           isFirstPrompt: Bool,
                           frontendDeliveryPath: DuckAIPromptWideEventData.FrontendDeliveryPath,
                           hasPageContext: Bool,
                           toolsSelected: Bool,
                           attachmentsSelected: Bool) {
        submissionStartedScopes.append(scope)
    }
    func promptDeliveryUpdated(scope: DuckAIWideEventFlowScope, wasQueued: Bool?, didSendBridgeMessage: Bool?) {}
    func frontendSubmissionAcknowledged(scope: DuckAIWideEventFlowScope) {}
    func chatStatusChanged(_ status: AIChatStatusValue, scope: DuckAIWideEventFlowScope) {}
    func stopGeneratingTapped(scope: DuckAIWideEventFlowScope) {}
    func tabClosedDuringGeneration(tabID: TabUID) {}
    func tabSwitchedAwayDuringGeneration(tabID: TabUID) { tabSwitchedAwayCalls.append(tabID) }
    func fireButtonClearedTabDuringGeneration(tabID: TabUID) {}
    func sheetDismissedDuringGeneration(scope: DuckAIWideEventFlowScope) {}
    func pageLoadFailed(scope: DuckAIWideEventFlowScope, error: Error) {}
}
