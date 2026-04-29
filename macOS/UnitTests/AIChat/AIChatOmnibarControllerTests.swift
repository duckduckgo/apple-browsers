//
//  AIChatOmnibarControllerTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Combine
import AIChat
import FeatureFlags
import PrivacyConfig
import SubscriptionTestingUtilities
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class AIChatOmnibarControllerTests: XCTestCase {

    private var controller: AIChatOmnibarController!
    private var mockDelegate: MockAIChatOmnibarControllerDelegate!
    private var mockTabOpener: MockAIChatTabOpener!
    private var featureFlagger: MockFeatureFlagger!
    private var searchPreferencesPersistor: AIChatMockSearchPreferencesPersistor!
    private var mockPreferences: MockAIChatPreferencesPersisting!
    private var mockModelsService: MockAIChatModelsProviding!
    private var mockSubscriptionManager: SubscriptionManagerMock!
    private var tabCollectionViewModel: TabCollectionViewModel!

    override func setUp() {
        super.setUp()
        mockDelegate = MockAIChatOmnibarControllerDelegate()
        mockTabOpener = MockAIChatTabOpener()
        featureFlagger = MockFeatureFlagger()
        searchPreferencesPersistor = AIChatMockSearchPreferencesPersistor()
        mockPreferences = MockAIChatPreferencesPersisting()
        mockModelsService = MockAIChatModelsProviding()
        mockSubscriptionManager = SubscriptionManagerMock()
        tabCollectionViewModel = TabCollectionViewModel(isPopup: false)

        controller = AIChatOmnibarController(
            aiChatTabOpener: mockTabOpener,
            tabCollectionViewModel: tabCollectionViewModel,
            featureFlagger: featureFlagger,
            searchPreferencesPersistor: searchPreferencesPersistor,
            preferences: mockPreferences,
            modelsService: mockModelsService,
            subscriptionManager: mockSubscriptionManager
        )
        controller.delegate = mockDelegate
    }

    override func tearDown() {
        controller = nil
        mockDelegate = nil
        mockTabOpener = nil
        featureFlagger = nil
        searchPreferencesPersistor = nil
        mockPreferences = nil
        mockModelsService = nil
        mockSubscriptionManager = nil
        tabCollectionViewModel = nil
        super.tearDown()
    }

    // MARK: - URL Navigation Tests

    func testWhenValidURLIsSubmitted_ThenDelegateReceivesNavigationRequest() {
        // Given
        controller.updateText("apple.com")

        // When
        controller.submit()

        // Then
        XCTAssertTrue(mockDelegate.didRequestNavigationToURLCalled, "Delegate should receive navigation request for valid URL")
        XCTAssertNotNil(mockDelegate.lastNavigationURL, "Navigation URL should not be nil")
        XCTAssertEqual(mockDelegate.lastNavigationURL?.host, "apple.com", "URL host should match input")
        XCTAssertFalse(mockDelegate.didSubmitCalled, "didSubmit should not be called for URL navigation")
        XCTAssertFalse(mockTabOpener.openAIChatTabCalled, "AI chat tab should not be opened for URL navigation")
    }

    func testWhenURLWithSchemeIsSubmitted_ThenDelegateReceivesNavigationRequest() {
        // Given
        controller.updateText("https://duckduckgo.com")

        // When
        controller.submit()

        // Then
        XCTAssertTrue(mockDelegate.didRequestNavigationToURLCalled)
        XCTAssertEqual(mockDelegate.lastNavigationURL?.host, "duckduckgo.com")
        XCTAssertFalse(mockDelegate.didSubmitCalled)
    }

    func testWhenURLWithPathIsSubmitted_ThenDelegateReceivesNavigationRequest() {
        // Given
        controller.updateText("github.com/duckduckgo")

        // When
        controller.submit()

        // Then
        XCTAssertTrue(mockDelegate.didRequestNavigationToURLCalled)
        XCTAssertNotNil(mockDelegate.lastNavigationURL)
        XCTAssertEqual(mockDelegate.lastNavigationURL?.host, "github.com")
    }

    // MARK: - AI Chat Query Tests

    func testWhenSearchQueryIsSubmitted_ThenAIChatFlowIsFollowed() async {
        // Given
        controller.updateText("what is privacy")

        // When
        controller.submit()

        // Wait for the async Task to complete
        await Task.yield()

        // Then
        XCTAssertTrue(mockDelegate.didSubmitCalled, "Delegate didSubmit should be called for search query")
        XCTAssertFalse(mockDelegate.didRequestNavigationToURLCalled, "Navigation should not be requested for search query")
        XCTAssertTrue(mockTabOpener.openAIChatTabCalled, "AI chat tab should be opened for search query")
    }

    func testWhenMultiWordQueryIsSubmitted_ThenAIChatFlowIsFollowed() async {
        // Given
        controller.updateText("how does DuckDuckGo protect my privacy")

        // When
        controller.submit()

        // Wait for the async Task to complete
        await Task.yield()

        // Then
        XCTAssertTrue(mockDelegate.didSubmitCalled)
        XCTAssertFalse(mockDelegate.didRequestNavigationToURLCalled)
        XCTAssertTrue(mockTabOpener.openAIChatTabCalled)
    }

    func testWhenQueryWithSpecialCharactersIsSubmitted_ThenAIChatFlowIsFollowed() async {
        // Given
        controller.updateText("what is 2 + 2?")

        // When
        controller.submit()

        // Wait for the async Task to complete
        await Task.yield()

        // Then
        XCTAssertTrue(mockDelegate.didSubmitCalled)
        XCTAssertFalse(mockDelegate.didRequestNavigationToURLCalled)
        XCTAssertTrue(mockTabOpener.openAIChatTabCalled)
    }

    // MARK: - Edge Cases

    func testWhenEmptyTextIsSubmitted_ThenNothingHappens() {
        // Given
        controller.updateText("")

        // When
        controller.submit()

        // Then
        XCTAssertFalse(mockDelegate.didSubmitCalled, "didSubmit should not be called for empty input")
        XCTAssertFalse(mockDelegate.didRequestNavigationToURLCalled, "Navigation should not be requested for empty input")
        XCTAssertFalse(mockTabOpener.openAIChatTabCalled, "AI chat tab should not be opened for empty input")
    }

    func testWhenWhitespaceOnlyIsSubmitted_ThenNothingHappens() {
        // Given
        controller.updateText("   ")

        // When
        controller.submit()

        // Then
        XCTAssertFalse(mockDelegate.didSubmitCalled)
        XCTAssertFalse(mockDelegate.didRequestNavigationToURLCalled)
        XCTAssertFalse(mockTabOpener.openAIChatTabCalled)
    }

    func testWhenTextWithLeadingWhitespaceIsSubmitted_ThenItIsTrimmed() {
        // Given
        controller.updateText("  apple.com  ")

        // When
        controller.submit()

        // Then - URL should be recognized despite whitespace
        XCTAssertTrue(mockDelegate.didRequestNavigationToURLCalled)
        XCTAssertNotNil(mockDelegate.lastNavigationURL)
    }

    func testWhenSubmitted_ThenCurrentTextIsCleared() {
        // Given
        controller.updateText("test query")

        // When
        controller.submit()

        // Then
        XCTAssertEqual(controller.currentText, "", "Current text should be cleared after submit")
    }

    // MARK: - Text Update Tests

    func testWhenTextIsUpdated_ThenCurrentTextReflectsChange() {
        // Given & When
        controller.updateText("test input")

        // Then
        XCTAssertEqual(controller.currentText, "test input")
    }

    func testWhenTextIsUpdated_ThenSharedTextStateIsUpdated() {
        // Given & When
        controller.updateText("shared text")

        // Then
        let sharedTextState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        XCTAssertEqual(sharedTextState?.text, "shared text")
        XCTAssertEqual(sharedTextState?.hasUserInteractedWithText, true)
    }

    // MARK: - Suggestions Feature Tests

    func testWhenFeatureFlagAndAutocompleteBothEnabled_ThenSuggestionsEnabled() {
        // Given
        featureFlagger.featuresStub[FeatureFlag.aiChatSuggestions.rawValue] = true
        searchPreferencesPersistor.showAutocompleteSuggestions = true

        // Then
        XCTAssertTrue(controller.isSuggestionsEnabled)
    }

    func testWhenFeatureFlagDisabled_ThenSuggestionsDisabled() {
        // Given
        featureFlagger.featuresStub[FeatureFlag.aiChatSuggestions.rawValue] = false
        searchPreferencesPersistor.showAutocompleteSuggestions = true

        // Then
        XCTAssertFalse(controller.isSuggestionsEnabled)
    }

    func testWhenAutocompleteDisabled_ThenSuggestionsDisabled() {
        // Given
        featureFlagger.featuresStub[FeatureFlag.aiChatSuggestions.rawValue] = true
        searchPreferencesPersistor.showAutocompleteSuggestions = false

        // Then
        XCTAssertFalse(controller.isSuggestionsEnabled)
    }

    func testWhenBothFeatureFlagAndAutocompleteDisabled_ThenSuggestionsDisabled() {
        // Given
        featureFlagger.featuresStub[FeatureFlag.aiChatSuggestions.rawValue] = false
        searchPreferencesPersistor.showAutocompleteSuggestions = false

        // Then
        XCTAssertFalse(controller.isSuggestionsEnabled)
    }

    // MARK: - Model Selection Tests

    func testWhenNoModelSelected_ThenCurrentModelIdIsNil() {
        XCTAssertNil(controller.currentModelId)
    }

    func testWhenModelIsSelected_ThenCurrentModelIdReturnsPersistedValue() {
        // Given
        mockPreferences.selectedModelId = "claude-sonnet-4-5"

        // Then
        XCTAssertEqual(controller.currentModelId, "claude-sonnet-4-5")
    }

    func testWhenUpdateSelectedModel_ThenValueIsPersistedToPreferences() {
        // When
        controller.updateSelectedModel("gpt-4o-mini")

        // Then
        XCTAssertEqual(mockPreferences.selectedModelId, "gpt-4o-mini")
    }

    func testWhenNoModelSelectedAndNoModels_ThenPersistedModelIdIsEmpty() {
        XCTAssertEqual(controller.persistedModelId, "")
    }

    func testWhenModelSelectedButModelsNotLoaded_ThenPersistedModelIdFallsBackToEmpty() {
        // Given — model selected but models haven't loaded yet
        mockPreferences.selectedModelId = "claude-sonnet-4-5"

        // Then — can't validate the selection without models, falls back to empty
        XCTAssertEqual(controller.persistedModelId, "")
    }

    func testWhenModelSelectedAndExistsInLoadedModels_ThenPersistedModelIdReturnsSelection() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "claude-sonnet-4-5", entityHasAccess: true)
        ]
        mockPreferences.selectedModelId = "claude-sonnet-4-5"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertEqual(controller.persistedModelId, "claude-sonnet-4-5")
    }

    func testWhenModelsEmpty_ThenSelectedModelSupportsImageUploadReturnsTrue() {
        // Conservative default: show image button when models haven't loaded
        XCTAssertTrue(controller.selectedModelSupportsImageUpload)
    }

    // MARK: - Model Selection With Loaded Models

    func testWhenNoModelSelectedAndModelsAvailable_ThenPersistedModelIdFallsBackToFirstAccessible() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "premium-model", entityHasAccess: false),
            makeRemoteModel(id: "free-model", entityHasAccess: true),
        ]

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertEqual(controller.persistedModelId, "free-model")
    }

    func testWhenSelectedModelSupportsImages_ThenReturnsTrue() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "vision-model", supportsImageUpload: true, entityHasAccess: true)
        ]
        mockPreferences.selectedModelId = "vision-model"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertTrue(controller.selectedModelSupportsImageUpload)
    }

    func testWhenSelectedModelDoesNotSupportImages_ThenReturnsFalse() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "text-only-model", supportsImageUpload: false, entityHasAccess: true)
        ]
        mockPreferences.selectedModelId = "text-only-model"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertFalse(controller.selectedModelSupportsImageUpload)
    }

    func testWhenSelectedModelNotInList_ThenFallsBackToFirstAccessible() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "some-model", supportsImageUpload: true, entityHasAccess: true)
        ]
        mockPreferences.selectedModelId = "nonexistent-model"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then — stale selection cleared, falls back to "some-model"
        XCTAssertNil(mockPreferences.selectedModelId)
        XCTAssertEqual(controller.persistedModelId, "some-model")
        XCTAssertTrue(controller.selectedModelSupportsImageUpload)
    }

    // MARK: - Model Fetch Tests

    func testWhenOmnibarActivated_ThenModelsFetched() async {
        // Given
        mockModelsService.modelsToReturn = [
            AIChatRemoteModel(id: "gpt-4o-mini", name: "GPT-4o mini", modelShortName: "4o-mini",
                              provider: "openai", entityHasAccess: true, supportsImageUpload: false,
                              supportedTools: [], accessTier: ["free"])
        ]

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertEqual(controller.models.count, 1)
        XCTAssertEqual(controller.models.first?.id, "gpt-4o-mini")
    }

    func testWhenModelFetchFails_ThenModelsRemainEmpty() async {
        // Given
        mockModelsService.errorToThrow = NSError(domain: "test", code: -1)

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertTrue(controller.models.isEmpty)
    }

    // MARK: - Per-tab State Preservation Tests

    func testWhenToolModeChanges_ThenPersistedToActiveTabSharedState() {
        // When
        controller.toggleImageGenerationMode()

        // Then
        let sharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        XCTAssertEqual(sharedState?.aiChatToolMode, .imageGeneration)
    }

    func testWhenToolModeTogglesOff_ThenSharedStateCleared() {
        // Given
        controller.toggleImageGenerationMode()
        let sharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        XCTAssertEqual(sharedState?.aiChatToolMode, .imageGeneration)

        // When
        controller.toggleImageGenerationMode()

        // Then
        XCTAssertNil(sharedState?.aiChatToolMode)
    }

    func testWhenTabSwitchesToTabWithSavedToolMode_ThenControllerRestoresIt() {
        // Given — tab 1 has image-gen active for the tab, tab 2 is fresh
        let tab1SharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        tab1SharedState?.setAIChatToolMode(.imageGeneration)
        tabCollectionViewModel.appendNewTab()
        XCTAssertNil(controller.activeToolMode, "Tab 2 has no tool mode; controller should be nil after switch")

        // When — switch back to tab 1
        tabCollectionViewModel.select(at: .unpinned(0))

        // Then
        XCTAssertEqual(controller.activeToolMode, .imageGeneration,
                       "Controller should restore tab 1's saved tool mode on switch back")
    }

    func testWhenCleanupRuns_ThenActiveTabToolModePersistIsSuppressed() {
        // Given — tab has tool mode saved via user toggle
        controller.toggleImageGenerationMode()
        let sharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        XCTAssertEqual(sharedState?.aiChatToolMode, .imageGeneration)

        // When — cleanup zeroes the controller's local state
        controller.cleanup()

        // Then — the shared state MUST NOT be wiped; the `isCleaningUp` guard stops the $activeToolMode
        // sink from echoing `nil` back to the current tab. Otherwise a tab-switch-driven cleanup would
        // wipe the outgoing tab's preserved tool mode.
        XCTAssertEqual(sharedState?.aiChatToolMode, .imageGeneration,
                       "Cleanup must not propagate its zeroed state back to the tab's shared state")
        XCTAssertNil(controller.activeToolMode, "Controller-local state is cleared by cleanup")
    }

    func testWhenPersistAttachmentsToActiveTab_ThenSharedStateUpdated() {
        // Given
        let attachment = makeAttachment()

        // When
        controller.persistAttachmentsToActiveTab([attachment])

        // Then
        let sharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        XCTAssertEqual(sharedState?.aiChatAttachments.count, 1)
        XCTAssertEqual(sharedState?.aiChatAttachments.first?.id, attachment.id)
    }

    func testWhenTabSwitchesToTabWithSavedAttachments_ThenOnActiveTabAttachmentsRestoreRequestedFires() {
        // Given — tab 1 has a saved attachment, tab 2 is fresh. Register the restore callback.
        let attachment = makeAttachment()
        tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState.setAIChatAttachments([attachment])

        var receivedAttachmentLists: [[AIChatImageAttachment]] = []
        controller.onActiveTabAttachmentsRestoreRequested = { attachments in
            receivedAttachmentLists.append(attachments)
        }

        // When — switch to a fresh tab; callback should fire with empty list
        tabCollectionViewModel.appendNewTab()

        // And switch back to tab 1; callback should fire with [attachment]
        tabCollectionViewModel.select(at: .unpinned(0))

        // Then
        XCTAssertEqual(receivedAttachmentLists.count, 2,
                       "Callback fires once per tab switch to inform the container VC which attachments to reinstall")
        XCTAssertEqual(receivedAttachmentLists.first?.count, 0, "Switch to tab 2 — no attachments")
        XCTAssertEqual(receivedAttachmentLists.last?.first?.id, attachment.id,
                       "Switch back to tab 1 — its saved attachment is handed back")
    }

    func testWhenUpdateSelection_ThenPersistedToActiveTabSharedState() {
        // Given
        controller.updateText("hello world")

        // When
        controller.updateSelection(NSRange(location: 6, length: 0))

        // Then
        let sharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        XCTAssertEqual(sharedState?.selectionRange, NSRange(location: 6, length: 0))
    }

    func testCurrentSelectionRangeReflectsActiveTabSharedState() {
        // Given
        tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState.updateText("hello")
        tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
            .updateSelection(NSRange(location: 3, length: 2))

        // Then
        XCTAssertEqual(controller.currentSelectionRange, NSRange(location: 3, length: 2))
    }

    func testWhenOnOmnibarActivatedAfterCleanup_ThenRestoresTextToolModeAndAttachmentsFromSharedState() {
        // Given — simulate a draft: user typed, selected a tool, attached a file on this tab.
        let sharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        sharedState?.updateText("my prompt")
        sharedState?.setAIChatToolMode(.webSearch)
        let attachment = makeAttachment()
        sharedState?.setAIChatAttachments([attachment])

        // Cleanup wipes the controller's local state (e.g. user toggled Duck.ai off).
        controller.cleanup()
        XCTAssertEqual(controller.currentText, "")
        XCTAssertNil(controller.activeToolMode)

        var restoredAttachmentLists: [[AIChatImageAttachment]] = []
        controller.onActiveTabAttachmentsRestoreRequested = { restoredAttachmentLists.append($0) }

        // When — user toggles Duck.ai back on; the panel calls onOmnibarActivated.
        controller.onOmnibarActivated(shouldFetchSuggestions: false)

        // Then — the controller pulls text / tool mode / attachments from the tab's shared state so the
        // user sees their draft again instead of an empty panel.
        XCTAssertEqual(controller.currentText, "my prompt")
        XCTAssertEqual(controller.activeToolMode, .webSearch)
        XCTAssertEqual(restoredAttachmentLists.last?.first?.id, attachment.id)
    }

    // MARK: - URL Classification with Multi-Word Input

    func testWhenSubmittedWithURLFollowedByNewlineAndText_ThenTreatedAsPrompt() async {
        // Given
        controller.updateText("https://google.com\ntest")

        // When
        controller.submit()
        await Task.yield()

        // Then — the multi-word pre-filter in `classifyAsNavigableURL` rejects this as a URL and falls
        // through to the chat-query path. Previously URL.init would strip the newline and the browser
        // would navigate to "https://google.comtest/".
        XCTAssertFalse(mockDelegate.didRequestNavigationToURLCalled,
                       "Input with a newline after a URL is a prompt, not a URL")
        XCTAssertTrue(mockDelegate.didSubmitCalled)
        XCTAssertTrue(mockTabOpener.openAIChatTabCalled)
    }

    func testWhenSubmittedWithURLFollowedBySpaceAndText_ThenTreatedAsPrompt() async {
        // Given
        controller.updateText("https://google.com tell me about it")

        // When
        controller.submit()
        await Task.yield()

        // Then
        XCTAssertFalse(mockDelegate.didRequestNavigationToURLCalled)
        XCTAssertTrue(mockDelegate.didSubmitCalled)
        XCTAssertTrue(mockTabOpener.openAIChatTabCalled)
    }

    func testWhenSubmittedWithURLFollowedByTabAndText_ThenTreatedAsPrompt() async {
        // Given
        controller.updateText("https://google.com\tcontext")

        // When
        controller.submit()
        await Task.yield()

        // Then
        XCTAssertFalse(mockDelegate.didRequestNavigationToURLCalled)
        XCTAssertTrue(mockDelegate.didSubmitCalled)
        XCTAssertTrue(mockTabOpener.openAIChatTabCalled)
    }

    func testWhenSubmittedWithPureURL_ThenStillNavigates() {
        // Regression guard for the multi-word filter — a pure URL (no internal whitespace) must still
        // navigate. Covered loosely by other tests but asserted explicitly here with the exact form
        // from the bug report.
        controller.updateText("https://google.com")
        controller.submit()
        XCTAssertTrue(mockDelegate.didRequestNavigationToURLCalled)
        XCTAssertEqual(mockDelegate.lastNavigationURL?.host, "google.com")
    }

    // MARK: - Web Search Model Support Tests

    func testWhenModelsNotLoaded_ThenSelectedModelSupportsWebSearchDefaultsToTrue() {
        // Then — conservative default keeps the Tools menu item visible until we know otherwise
        XCTAssertTrue(controller.models.isEmpty)
        XCTAssertTrue(controller.selectedModelSupportsWebSearch)
    }

    func testWhenSelectedModelSupportsWebSearch_ThenSelectedModelSupportsWebSearchReturnsTrue() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "ws-model", supportedTools: ["WebSearch"])
        ]
        mockPreferences.selectedModelId = "ws-model"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertTrue(controller.selectedModelSupportsWebSearch)
    }

    func testWhenSelectedModelDoesNotSupportWebSearch_ThenSelectedModelSupportsWebSearchReturnsFalse() async {
        // Given — model advertises other tools but not WebSearch
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "no-ws-model", supportedTools: ["NewsSearch"])
        ]
        mockPreferences.selectedModelId = "no-ws-model"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertFalse(controller.selectedModelSupportsWebSearch)
    }

    func testWhenSwitchingToUnsupportedModel_ThenWebSearchModeIsDeactivated() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "ws-supported", supportedTools: ["WebSearch"]),
            makeRemoteModel(id: "ws-unsupported", supportedTools: [])
        ]
        mockPreferences.selectedModelId = "ws-supported"
        controller.onOmnibarActivated()
        await waitForModels()
        controller.toggleWebSearchMode()
        XCTAssertTrue(controller.isWebSearchMode)

        // When
        controller.updateSelectedModel("ws-unsupported")

        // Then
        XCTAssertFalse(controller.isWebSearchMode)
    }

    func testWhenSwitchingBetweenSupportingModels_ThenWebSearchModeIsPreserved() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "ws-a", supportedTools: ["WebSearch"]),
            makeRemoteModel(id: "ws-b", supportedTools: ["WebSearch"])
        ]
        mockPreferences.selectedModelId = "ws-a"
        controller.onOmnibarActivated()
        await waitForModels()
        controller.toggleWebSearchMode()
        XCTAssertTrue(controller.isWebSearchMode)

        // When
        controller.updateSelectedModel("ws-b")

        // Then
        XCTAssertTrue(controller.isWebSearchMode)
    }

    func testWhenFetchModelsRevealsUnsupportedPersistedModel_ThenWebSearchModeIsDeactivated() async {
        // Given — user toggled Web Search before models loaded (conservative default allowed it),
        // persisted model turns out not to support it
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "no-ws", supportedTools: [])
        ]
        mockPreferences.selectedModelId = "no-ws"
        controller.toggleWebSearchMode()
        XCTAssertTrue(controller.isWebSearchMode)

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertFalse(controller.isWebSearchMode)
    }

    // MARK: - Reasoning Effort Tests

    func testWhenReasoningEffortFeatureFlagEnabled_ThenIsReasoningEffortEnabledIsTrue() {
        // Given
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true

        // Then
        XCTAssertTrue(controller.isReasoningEffortEnabled)
    }

    func testWhenReasoningEffortFeatureFlagDisabled_ThenIsReasoningEffortEnabledIsFalse() {
        // Given
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = false

        // Then
        XCTAssertFalse(controller.isReasoningEffortEnabled)
    }

    func testWhenUpdateSelectedReasoningEffort_ThenValueIsPersistedToPreferences() {
        // When
        controller.updateSelectedReasoningEffort(.low)

        // Then
        XCTAssertEqual(mockPreferences.selectedReasoningEffort, "low")
    }

    func testWhenReasoningEffortIsPersisted_ThenSelectedReasoningEffortReturnsPersistedValue() {
        // Given
        mockPreferences.selectedReasoningEffort = "medium"

        // Then
        XCTAssertEqual(controller.selectedReasoningEffort, .medium)
    }

    func testWhenPersistedReasoningEffortRawValueIsUnknown_ThenSelectedReasoningEffortIsNil() {
        // Given — backend or older build stored a raw value this app version doesn't know about
        mockPreferences.selectedReasoningEffort = "extreme"

        // Then — safely surfaces as nil rather than leaking the raw string through the typed API
        XCTAssertNil(controller.selectedReasoningEffort)
    }

    func testWhenUpdateSelectedReasoningEffortToNil_ThenPreferencesValueIsCleared() {
        // Given
        mockPreferences.selectedReasoningEffort = "low"

        // When
        controller.updateSelectedReasoningEffort(nil)

        // Then
        XCTAssertNil(mockPreferences.selectedReasoningEffort)
    }

    func testWhenCleanupCalled_ThenSelectedReasoningEffortIsPreserved() {
        // Given
        mockPreferences.selectedReasoningEffort = "medium"

        // When
        controller.cleanup()

        // Then — persisted preference is not reset by cleanup
        XCTAssertEqual(controller.selectedReasoningEffort, .medium)
    }

    func testWhenModelSupportsReasoningEfforts_ThenSelectedModelReasoningEffortsReturnsList() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "reasoning-model", entityHasAccess: true, supportedReasoningEffort: [.none, .low, .medium])
        ]
        mockPreferences.selectedModelId = "reasoning-model"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertEqual(controller.selectedModelReasoningEfforts, [.none, .low, .medium])
    }

    func testWhenModelSupportsHighReasoningEffort_ThenHighValueIsAvailable() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "forward-compat-model", entityHasAccess: true, supportedReasoningEffort: [.none, .low, .high])
        ]
        mockPreferences.selectedModelId = "forward-compat-model"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertEqual(controller.selectedModelReasoningEfforts, [.none, .low, .high])
    }

    func testWhenModelSupportsHighReasoningEffort_ThenItIsParsed() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "high-model", entityHasAccess: true, supportedReasoningEffort: [.low, .high])
        ]
        mockPreferences.selectedModelId = "high-model"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then — `.high` is recognized and surfaced from the supported list
        XCTAssertEqual(controller.selectedModelReasoningEfforts, [.low, .high])
    }

    func testWhenModelSupportsBothMediumAndHigh_ThenPickerDropsMediumButValidationKeepsIt() async {
        // Given — model advertises both medium and high
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "dual-model", entityHasAccess: true, supportedReasoningEffort: [.low, .medium, .high])
        ]
        mockPreferences.selectedModelId = "dual-model"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then — the picker collapses to a single Extended Reasoning option backed by `.high`
        XCTAssertEqual(controller.pickerReasoningEfforts, [.low, .high])
        // …but the un-deduped server-truth list still contains `.medium` for validation/submission
        XCTAssertEqual(controller.selectedModelReasoningEfforts, [.low, .medium, .high])
    }

    func testWhenModelSupportsOnlyMediumNotHigh_ThenPickerKeepsMedium() async {
        // Given — high not in the supported list, so dedup must not trigger
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "medium-model", entityHasAccess: true, supportedReasoningEffort: [.low, .medium])
        ]
        mockPreferences.selectedModelId = "medium-model"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then — picker shows medium as the Extended Reasoning option
        XCTAssertEqual(controller.pickerReasoningEfforts, [.low, .medium])
    }

    func testWhenStoredEffortIsMediumAndModelAlsoAdvertisesHigh_ThenMediumIsStillSubmitted() async {
        // Given — user previously picked `.medium`; model now advertises both medium and high.
        // The picker no longer surfaces `.medium` (high preferred), but the user's actual choice
        // must continue to flow through to the backend unchanged.
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "dual-model", entityHasAccess: true, supportedReasoningEffort: [.low, .medium, .high])
        ]
        mockPreferences.selectedModelId = "dual-model"
        mockPreferences.selectedReasoningEffort = "medium"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then — `medium` is preserved and submitted (not silently reset by the picker dedup)
        XCTAssertEqual(controller.effectiveReasoningEffort, .medium)
        XCTAssertEqual(mockPreferences.selectedReasoningEffort, "medium")
    }

    func testWhenStoredEffortIsMediumAndPickerDedupsToHigh_ThenDisplayedEffortIsHigh() async {
        // Given — picker dedup hides `.medium` in favor of `.high`, but the user's stored choice
        // is still `.medium`. The chip should render the bucket-equivalent picker effort so its
        // label/icon stay consistent with what's actually submitted.
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "dual-model", entityHasAccess: true, supportedReasoningEffort: [.low, .medium, .high])
        ]
        mockPreferences.selectedModelId = "dual-model"
        mockPreferences.selectedReasoningEffort = "medium"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then — chip resolves to `.high` (same Extended Reasoning UI as `.medium`), and
        // submission still sends "medium" (preserving the user's actual choice).
        XCTAssertEqual(controller.displayedReasoningEffort, .high)
        XCTAssertEqual(controller.effectiveReasoningEffort, .medium)
    }

    func testWhenStoredEffortIsMinimalAndPickerDedupsToNone_ThenDisplayedEffortIsNone() async {
        // Given — symmetric to the medium/high case for the Fast bucket
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "fast-dual-model", entityHasAccess: true, supportedReasoningEffort: [.none, .minimal, .low])
        ]
        mockPreferences.selectedModelId = "fast-dual-model"
        mockPreferences.selectedReasoningEffort = "minimal"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertEqual(controller.displayedReasoningEffort, .none)
        XCTAssertEqual(controller.effectiveReasoningEffort, .minimal)
    }

    func testWhenStoredEffortIsInPickerList_ThenDisplayedEffortMatchesStored() async {
        // Given — no dedup applies (model has only `.high`, not `.medium`)
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "high-model", entityHasAccess: true, supportedReasoningEffort: [.low, .high])
        ]
        mockPreferences.selectedModelId = "high-model"
        mockPreferences.selectedReasoningEffort = "high"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertEqual(controller.displayedReasoningEffort, .high)
    }

    func testWhenStoredEffortIsNotSupportedByModel_ThenDisplayedEffortIsNil() async {
        // Given — stored effort the current model doesn't list at all
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "limited-model", entityHasAccess: true, supportedReasoningEffort: [.low])
        ]
        mockPreferences.selectedModelId = "limited-model"
        mockPreferences.selectedReasoningEffort = "high"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then — chip falls through to nil so the view layer can use its fallback
        XCTAssertNil(controller.displayedReasoningEffort)
    }

    func testWhenStoredEffortIsHigh_ThenHighIsSubmitted() async {
        // Given
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "high-model", entityHasAccess: true, supportedReasoningEffort: [.low, .high])
        ]
        mockPreferences.selectedModelId = "high-model"
        mockPreferences.selectedReasoningEffort = "high"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then — the user's `.high` selection flows through to submission
        XCTAssertEqual(controller.effectiveReasoningEffort, .high)
    }

    func testWhenModelDoesNotSupportReasoningEfforts_ThenSelectedModelReasoningEffortsIsEmpty() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "plain-model", entityHasAccess: true)
        ]
        mockPreferences.selectedModelId = "plain-model"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertTrue(controller.selectedModelReasoningEfforts.isEmpty)
    }

    func testWhenFeatureFlagEnabledAndEffortSupportedByModel_ThenEffectiveReasoningEffortReturnsSelection() async {
        // Given
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "reasoning-model", entityHasAccess: true, supportedReasoningEffort: [.none, .low, .medium])
        ]
        mockPreferences.selectedModelId = "reasoning-model"
        mockPreferences.selectedReasoningEffort = "low"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertEqual(controller.effectiveReasoningEffort, .low)
    }

    func testWhenFeatureFlagDisabled_ThenEffectiveReasoningEffortIsNilEvenIfSelected() {
        // Given — user previously selected an effort while flag was on
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = false
        mockPreferences.selectedReasoningEffort = "medium"

        // Then — nothing is sent when the flag is off, even if a value is persisted
        XCTAssertNil(controller.effectiveReasoningEffort)
    }

    func testWhenImageGenerationModeActive_ThenEffectiveReasoningEffortIsNil() async {
        // Given — a valid persisted effort on a model that supports reasoning
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "reasoning-model", entityHasAccess: true, supportedReasoningEffort: [.low])
        ]
        mockPreferences.selectedModelId = "reasoning-model"
        mockPreferences.selectedReasoningEffort = "low"
        controller.onOmnibarActivated()
        await waitForModels()

        // When — image generation mode is turned on
        controller.toggleImageGenerationMode()

        // Then — reasoning is not attached to image-generation submissions
        XCTAssertNil(controller.effectiveReasoningEffort)
    }

    func testWhenPersistedEffortNotSupportedByCurrentModel_ThenEffectiveReasoningEffortIsNil() async {
        // Given — persisted "medium" but current model only lists "low"
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "limited-model", entityHasAccess: true, supportedReasoningEffort: [.low])
        ]
        mockPreferences.selectedModelId = "limited-model"
        mockPreferences.selectedReasoningEffort = "medium"

        // When — stale-clear runs on model load
        controller.onOmnibarActivated()
        await waitForModels()

        // Then — nothing is sent (persisted value was stale)
        XCTAssertNil(controller.effectiveReasoningEffort)
    }

    func testWhenModelsLoaded_ThenStalePersistedReasoningEffortIsCleared() async {
        // Given — persisted effort that doesn't match the new model's supported list
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "limited-model", entityHasAccess: true, supportedReasoningEffort: [.low])
        ]
        mockPreferences.selectedModelId = "limited-model"
        mockPreferences.selectedReasoningEffort = "medium"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then — stale preference is wiped from persistence
        XCTAssertNil(mockPreferences.selectedReasoningEffort)
    }

    func testWhenModelsLoadedAndPersistedEffortSupported_ThenSelectionIsPreserved() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "reasoning-model", entityHasAccess: true, supportedReasoningEffort: [.none, .low, .medium])
        ]
        mockPreferences.selectedModelId = "reasoning-model"
        mockPreferences.selectedReasoningEffort = "low"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then — valid preference is kept
        XCTAssertEqual(mockPreferences.selectedReasoningEffort, "low")
    }

    func testWhenUpdateSelectedModelToIncompatibleOne_ThenStalePersistedReasoningEffortIsCleared() async {
        // Given — two models loaded, user has picked a reasoning effort valid on the first
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "reasoning-model", entityHasAccess: true, supportedReasoningEffort: [.none, .low, .medium]),
            makeRemoteModel(id: "limited-model", entityHasAccess: true, supportedReasoningEffort: [.low])
        ]
        mockPreferences.selectedModelId = "reasoning-model"
        mockPreferences.selectedReasoningEffort = "medium"
        controller.onOmnibarActivated()
        await waitForModels()

        // When — user switches to a model that doesn't support "medium"
        controller.updateSelectedModel("limited-model")

        // Then — controller clears the stale preference; nothing is silently retained
        XCTAssertNil(mockPreferences.selectedReasoningEffort)
    }

    func testWhenUpdateSelectedModelToCompatibleOne_ThenPersistedReasoningEffortIsPreserved() async {
        // Given — two models that both support "low"
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "model-a", entityHasAccess: true, supportedReasoningEffort: [.none, .low, .medium]),
            makeRemoteModel(id: "model-b", entityHasAccess: true, supportedReasoningEffort: [.low, .medium])
        ]
        mockPreferences.selectedModelId = "model-a"
        mockPreferences.selectedReasoningEffort = "low"
        controller.onOmnibarActivated()
        await waitForModels()

        // When — switching to another model that still supports "low"
        controller.updateSelectedModel("model-b")

        // Then — the preference is kept
        XCTAssertEqual(mockPreferences.selectedReasoningEffort, "low")
    }

    // MARK: - Helpers

    /// Creates a remote model for testing. Access is resolved locally from `accessTier`
    /// (not `entityHasAccess`), so `accessTier` must include `"free"` for the model to be
    /// accessible to the default free-tier test user.
    private func makeRemoteModel(
        id: String,
        supportsImageUpload: Bool = false,
        entityHasAccess: Bool = true,
        supportedTools: [String] = [],
        supportedReasoningEffort: [AIChatReasoningEffort] = []
    ) -> AIChatRemoteModel {
        AIChatRemoteModel(
            id: id,
            name: id,
            modelShortName: nil,
            provider: "openai",
            entityHasAccess: entityHasAccess,
            supportsImageUpload: supportsImageUpload,
            supportedTools: supportedTools,
            accessTier: entityHasAccess ? ["free"] : ["plus", "pro"],
            supportedReasoningEffort: supportedReasoningEffort
        )
    }

    private func waitForModels() async {
        // Allow the async Task inside onOmnibarActivated to complete
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    private func makeAttachment(id: UUID = UUID()) -> AIChatImageAttachment {
        AIChatImageAttachment(id: id, image: NSImage(), fileName: "\(id.uuidString).png", fileURL: nil, skipResize: true)
    }
}

// MARK: - Mock Delegate

private class MockAIChatOmnibarControllerDelegate: AIChatOmnibarControllerDelegate {
    var didSubmitCalled = false
    var didRequestNavigationToURLCalled = false
    var lastNavigationURL: URL?
    var didSelectSuggestionCalled = false
    var lastSelectedSuggestion: AIChatSuggestion?

    func aiChatOmnibarControllerDidSubmit(_ controller: AIChatOmnibarController) {
        didSubmitCalled = true
    }

    func aiChatOmnibarController(_ controller: AIChatOmnibarController, didRequestNavigationToURL url: URL) {
        didRequestNavigationToURLCalled = true
        lastNavigationURL = url
    }

    func aiChatOmnibarController(_ controller: AIChatOmnibarController, didSelectSuggestion suggestion: AIChatSuggestion) {
        didSelectSuggestionCalled = true
        lastSelectedSuggestion = suggestion
    }
}

// MARK: - Mock Search Preferences Persistor

private class AIChatMockSearchPreferencesPersistor: SearchPreferencesPersistor {
    var showAutocompleteSuggestions: Bool = true
}

// MARK: - Mock AI Chat Preferences

private class MockAIChatPreferencesPersisting: AIChatPreferencesPersisting {
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningEffort: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

// MARK: - Mock Models Service

private class MockAIChatModelsProviding: AIChatModelsProviding {
    var modelsToReturn: [AIChatRemoteModel] = []
    var errorToThrow: Error?

    func fetchModels() async throws -> [AIChatRemoteModel] {
        if let error = errorToThrow {
            throw error
        }
        return modelsToReturn
    }
}
