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
@testable import Subscription

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
    private var mockSubscriptionUpsellPresenter: MockAIChatOmnibarSubscriptionUpselling!
    private var mockBadgeImpressionPersistor: MockFreeTrialBadgePersistor!
    private var tabCollectionViewModel: TabCollectionViewModel!

    override func setUp() {
        super.setUp()
        // `AIChatPromptHandler.shared` is a singleton — drain anything a previous test (or a
        // suite that ran first) might have left in it, so submit-tests that read back the
        // posted prompt see only what the test under inspection wrote.
        _ = AIChatPromptHandler.shared.consumeData()

        mockDelegate = MockAIChatOmnibarControllerDelegate()
        mockTabOpener = MockAIChatTabOpener()
        featureFlagger = MockFeatureFlagger()
        searchPreferencesPersistor = AIChatMockSearchPreferencesPersistor()
        mockPreferences = MockAIChatPreferencesPersisting()
        mockModelsService = MockAIChatModelsProviding()
        mockSubscriptionManager = SubscriptionManagerMock()
        mockSubscriptionUpsellPresenter = MockAIChatOmnibarSubscriptionUpselling()
        // Injected (rather than the real UserDefaults-backed default) so the impression cap is
        // controllable and no test leaks state into the shared standard defaults.
        mockBadgeImpressionPersistor = MockFreeTrialBadgePersistor(initialCount: 0, cap: 4)
        tabCollectionViewModel = TabCollectionViewModel(isPopup: false)

        controller = AIChatOmnibarController(
            aiChatTabOpener: mockTabOpener,
            tabCollectionViewModel: tabCollectionViewModel,
            featureFlagger: featureFlagger,
            searchPreferencesPersistor: searchPreferencesPersistor,
            preferences: mockPreferences,
            modelsService: mockModelsService,
            subscriptionManager: mockSubscriptionManager,
            subscriptionUpsellPresenter: mockSubscriptionUpsellPresenter,
            badgeImpressionPersistor: mockBadgeImpressionPersistor
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
        mockSubscriptionUpsellPresenter = nil
        mockBadgeImpressionPersistor = nil
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

    // MARK: - Voice Chat

    func testOpenNewVoiceChat_DelegatesToOpenVoiceSessionWithNewSelectedTab() {
        // When
        controller.openNewVoiceChat()

        // `openNewVoiceChat` defers the open to the next main-queue turn; enqueue our wait behind it
        // so FIFO ordering guarantees the deferred open has run by the time this fulfills.
        let expectation = expectation(description: "deferred voice session open")
        DispatchQueue.main.async { expectation.fulfill() }
        waitForExpectations(timeout: 1)

        // Then — controller hands off to `openVoiceSession`, which encapsulates the
        // "focus existing voice tab in the same window if active, otherwise open new" decision.
        XCTAssertTrue(mockTabOpener.openVoiceSessionCalled)
        XCTAssertEqual(mockTabOpener.lastVoiceSessionBehavior, .newTab(selected: true))
        XCTAssertTrue(mockTabOpener.lastVoiceSessionSourceCollection === tabCollectionViewModel)
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

    func testWhenTabSwitchesToTabWithSavedAttachments_ThenOnActiveTabPanelAttachmentsChangedFires() {
        // Given — tab 1 has a saved image attachment, tab 2 is fresh. Register the panel-attachments
        // callback (the unified channel that drives the carousel for image / tab / file kinds).
        let attachment = makeAttachment()
        tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState.setAIChatAttachments([attachment])

        var receivedPanelLists: [[AIChatPanelAttachment]] = []
        controller.onActiveTabPanelAttachmentsChanged = { panelAttachments in
            receivedPanelLists.append(panelAttachments)
        }

        // When — switch to a fresh tab; callback should fire with empty list
        tabCollectionViewModel.appendNewTab()

        // And switch back to tab 1; callback should fire with the saved image attachment
        tabCollectionViewModel.select(at: .unpinned(0))

        // Then
        XCTAssertEqual(receivedPanelLists.count, 2,
                       "Callback fires once per tab switch (the publisher emits the new tab's current value on subscription)")
        XCTAssertEqual(receivedPanelLists.first?.count, 0, "Switch to tab 2 — no attachments")
        XCTAssertEqual(receivedPanelLists.last?.count, 1, "Switch back to tab 1 — one attachment")
        if case .image(let restored) = receivedPanelLists.last?.first {
            XCTAssertEqual(restored.id, attachment.id, "The restored panel entry is the saved image")
        } else {
            XCTFail("Expected the restored panel entry to be an image attachment")
        }
    }

    // MARK: - Tab Attachments (Attach Page Content)

    func testWhenPersistTabAttachmentsToActiveTab_ThenSharedStateUpdated() {
        // Given
        let attachment = makeTabAttachment()

        // When
        controller.persistTabAttachmentsToActiveTab([attachment])

        // Then
        let sharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        XCTAssertEqual(sharedState?.aiChatTabAttachments.count, 1)
        XCTAssertEqual(sharedState?.aiChatTabAttachments.first?.id, attachment.id)
    }

    func testWhenToggleTabAttachmentForUnattachedTab_ThenItIsAdded() {
        // Given — no attachments yet
        let attachment = makeTabAttachment(id: "tab-1")

        // When
        controller.toggleTabAttachment(attachment)

        // Then
        XCTAssertEqual(controller.activeTabAttachments.map(\.id), ["tab-1"])
        let sharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        XCTAssertEqual(sharedState?.aiChatTabAttachments.map(\.id), ["tab-1"],
                       "Toggle-on must persist to the active tab's shared state")
    }

    func testWhenToggleTabAttachmentForAttachedTab_ThenItIsRemoved() {
        // Given — attachment is already attached
        let attachment = makeTabAttachment(id: "tab-1")
        controller.toggleTabAttachment(attachment)
        XCTAssertEqual(controller.activeTabAttachments.count, 1)

        // When — toggle the same id again
        controller.toggleTabAttachment(attachment)

        // Then
        XCTAssertTrue(controller.activeTabAttachments.isEmpty)
        let sharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        XCTAssertTrue(sharedState?.aiChatTabAttachments.isEmpty ?? false)
    }

    func testWhenToggleTabAttachmentMultipleDistinctIds_ThenAllAdded() {
        controller.toggleTabAttachment(makeTabAttachment(id: "tab-1"))
        controller.toggleTabAttachment(makeTabAttachment(id: "tab-2"))
        controller.toggleTabAttachment(makeTabAttachment(id: "tab-3"))

        XCTAssertEqual(controller.activeTabAttachments.map(\.id), ["tab-1", "tab-2", "tab-3"],
                       "Order matches the toggle-on order; the duck.ai web app preserves this on submit")
    }

    func testWhenSubmitWithTabAttachments_ThenSharedStateClearsTabAttachments() async {
        // Given — a tab is attached and there's a prompt to submit
        let attachment = makeTabAttachment(id: "tab-1")
        controller.toggleTabAttachment(attachment)
        XCTAssertFalse(controller.activeTabAttachments.isEmpty)
        controller.updateText("summarize this")

        // When
        controller.submit()
        // Submit awaits per-tab page-context extraction (M8) before clearing shared state.
        // See sibling test for the rationale on sleep vs yield-loop.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then — submit clears the active tab's saved tab attachments (the publisher then drives
        // the carousel back to empty). The active tab's image attachments are cleared by the same
        // submit flow via the existing image-side path.
        let sharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        XCTAssertTrue(sharedState?.aiChatTabAttachments.isEmpty ?? false,
                      "Tab attachments are cleared from shared state after a successful submit")
    }

    func testWhenSubmitWithTabAttachments_ThenSubmitProceedsAndPixelFires() async {
        // Given — two tab attachments. Note: in this unit test, the `TabCollectionViewModel`
        // doesn't contain real `Tab` instances for "tab-A" / "tab-B", so the page-context
        // extractor returns nil for both and the prompt's `pageContext` ends up nil. We
        // can't unit-test the full extraction → `.multiple([...])` path here without real
        // webviews; the encoding side is covered in `AIChatNativePromptTests`.
        controller.toggleTabAttachment(makeTabAttachment(id: "tab-A"))
        controller.toggleTabAttachment(makeTabAttachment(id: "tab-B"))
        controller.updateText("summarize these")

        // When
        controller.submit()
        // Brief sleep instead of `Task.yield`s: submit's `await extractPageContextsForOmnibarSubmit`
        // dispatches a `withTaskGroup` with one `@MainActor` child task per attached tab. With
        // both child tasks competing for the main actor with the submit task itself, the
        // scheduler interleaving isn't deterministic across runs — a fixed-count yield loop
        // sometimes finishes before the group's `for await pair in group` drains. Sleeping
        // hands the scheduler a real time slice so everything settles before we assert.
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then — submit didn't crash, the tab-opener was called, and the prompt was posted as
        // a `.query` tool. The fact that the tab ids existed at submit time is enough to
        // exercise the per-tab fetch path; whether they produce a non-nil `pageContext`
        // depends on extraction (which we don't mock here).
        XCTAssertTrue(mockTabOpener.openAIChatTabCalled, "Submit opens the duck.ai tab")
        let prompt = AIChatPromptHandler.shared.consumeData()
        if case .query = prompt?.tool {
            // OK
        } else {
            XCTFail("Expected a `.query` tool in the submitted prompt")
        }
    }

    // MARK: - File attachments (PDFs etc.)

    func testWhenAddFileAttachment_ThenSharedStateContainsIt() {
        let attachment = makeFileAttachment(fileName: "spec.pdf")
        controller.addFileAttachmentToActiveTab(attachment)

        XCTAssertEqual(controller.activeFileAttachments.map(\.id), [attachment.id])
        let sharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        XCTAssertEqual(sharedState?.aiChatFileAttachments.map(\.id), [attachment.id],
                       "File attachment is persisted to the active tab's shared state")
    }

    func testWhenRemoveFileAttachment_ThenSharedStateDropsIt() {
        let attachment = makeFileAttachment()
        controller.addFileAttachmentToActiveTab(attachment)
        XCTAssertFalse(controller.activeFileAttachments.isEmpty)

        controller.removeFileAttachmentFromActiveTab(id: attachment.id)

        XCTAssertTrue(controller.activeFileAttachments.isEmpty)
    }

    func testWhenSubmitWithFileAttachments_ThenPromptCarriesFiles() async {
        // Given — a model that supports file upload, plus an attached PDF
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "pdf-model", supportedFileTypes: ["application/pdf"], entityHasAccess: true)
        ]
        mockPreferences.selectedModelId = "pdf-model"
        controller.onOmnibarActivated()
        await waitForModels()

        let pdfData = Data("%PDF-1.4 mock".utf8)
        let attachment = AIChatFileAttachment(
            data: pdfData,
            fileName: "spec.pdf",
            mimeType: "application/pdf"
        )
        controller.addFileAttachmentToActiveTab(attachment)
        controller.updateText("summarise this PDF")

        // When
        controller.submit()
        await Task.yield()

        // Then — prompt's `query.files` carries the encoded PDF.
        let prompt = AIChatPromptHandler.shared.consumeData()
        guard case let .query(query) = prompt?.tool else {
            XCTFail("Expected a `.query` tool in the submitted prompt")
            return
        }
        XCTAssertEqual(query.files?.count, 1)
        XCTAssertEqual(query.files?.first?.fileName, "spec.pdf")
        XCTAssertEqual(query.files?.first?.mimeType, "application/pdf")
        XCTAssertEqual(query.files?.first?.data, pdfData.base64EncodedString(),
                       "File data is sent as base64")
    }

    func testWhenSubmitWithFileAttachments_ThenSharedStateClearsFileAttachments() async {
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "pdf-model", supportedFileTypes: ["application/pdf"], entityHasAccess: true)
        ]
        mockPreferences.selectedModelId = "pdf-model"
        controller.onOmnibarActivated()
        await waitForModels()

        controller.addFileAttachmentToActiveTab(makeFileAttachment(fileName: "a.pdf"))
        controller.updateText("summarise")

        controller.submit()
        await Task.yield()

        let sharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        XCTAssertTrue(sharedState?.aiChatFileAttachments.isEmpty ?? false,
                      "File attachments are cleared from shared state after a successful submit")
    }

    func testWhenSubmitWithoutTabAttachments_ThenPromptOmitsPageContext() async {
        // Given — only text, no attachments
        controller.updateText("just text")

        // When
        controller.submit()
        await Task.yield()

        // Then — the prompt's top-level `pageContext` is nil so the duck.ai web app sees no
        // extra field (the omnibar never auto-attaches the current page — current-page
        // behavior is sidebar-only).
        let prompt = AIChatPromptHandler.shared.consumeData()
        XCTAssertNil(prompt?.pageContext,
                     "No tab attachments → omnibar omits `pageContext` entirely on the prompt")
    }

    func testWhenTabSwitchesToTabWithSavedTabAttachments_ThenPanelAttachmentsCallbackFires() {
        // Given — tab 1 has a saved tab attachment; register the unified-panel callback.
        let attachment = makeTabAttachment(id: "tab-A")
        tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState.setAIChatTabAttachments([attachment])

        var receivedLists: [[AIChatPanelAttachment]] = []
        controller.onActiveTabPanelAttachmentsChanged = { lists in
            receivedLists.append(lists)
        }

        // When — switch to fresh tab 2 and back to tab 1
        tabCollectionViewModel.appendNewTab()
        tabCollectionViewModel.select(at: .unpinned(0))

        // Then — the publisher emits the current value on each new subscription, so we expect
        // one callback per tab switch with that tab's saved list.
        XCTAssertGreaterThanOrEqual(receivedLists.count, 2,
                       "Callback fires on every tab switch (publisher delivers initial value on subscribe)")
        XCTAssertTrue(receivedLists.contains { $0.isEmpty }, "Tab 2 has no panel attachments")
        XCTAssertTrue(
            receivedLists.contains { list in
                if case .tab(let tab) = list.first { return tab.id == attachment.id }
                return false
            },
            "Tab 1's saved tab attachment is handed back when switching back"
        )
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

    func testWhenOnOmnibarActivatedAfterCleanup_ThenRestoresTextAndToolModeFromSharedState() {
        // Given — simulate a draft: user typed, selected a tool, attached an image on this tab.
        let sharedState = tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
        sharedState?.updateText("my prompt")
        sharedState?.setAIChatToolMode(.webSearch)
        let attachment = makeAttachment()
        sharedState?.setAIChatAttachments([attachment])

        // Cleanup wipes the controller's local state (e.g. user toggled Duck.ai off). It does NOT
        // clear shared state — the carousel re-syncs via the always-on `$aiChatPanelAttachments`
        // subscription, so no separate "restore on activate" callback is needed any more.
        controller.cleanup()
        XCTAssertEqual(controller.currentText, "")
        XCTAssertNil(controller.activeToolMode)

        // When — user toggles Duck.ai back on; the panel calls onOmnibarActivated.
        controller.onOmnibarActivated(shouldFetchSuggestions: false)

        // Then — the controller pulls text / tool mode from shared state so the user sees their draft.
        XCTAssertEqual(controller.currentText, "my prompt")
        XCTAssertEqual(controller.activeToolMode, .webSearch)
        // Attachments are preserved on shared state across the cleanup → activate cycle.
        XCTAssertEqual(sharedState?.aiChatAttachments.first?.id, attachment.id)
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

    // MARK: - Image Generation Model Support Tests

    func testWhenModelsNotLoaded_ThenSelectedModelSupportsImageGenerationDefaultsToTrue() {
        // Then — conservative default keeps the Tools menu item visible until we know otherwise
        XCTAssertTrue(controller.models.isEmpty)
        XCTAssertTrue(controller.selectedModelSupportsImageGeneration)
    }

    func testWhenSelectedModelSupportsGenerateImage_ThenSelectedModelSupportsImageGenerationReturnsTrue() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "img-model", supportedTools: ["GenerateImage"])
        ]
        mockPreferences.selectedModelId = "img-model"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertTrue(controller.selectedModelSupportsImageGeneration)
    }

    func testWhenSelectedModelDoesNotSupportGenerateImage_ThenSelectedModelSupportsImageGenerationReturnsFalse() async {
        // Given — model advertises other tools but not GenerateImage
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "mistral", supportedTools: ["NewsSearch"])
        ]
        mockPreferences.selectedModelId = "mistral"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertFalse(controller.selectedModelSupportsImageGeneration)
    }

    func testWhenSwitchingToUnsupportedModel_ThenImageGenerationModeIsDeactivated() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "img-supported", supportedTools: ["GenerateImage"]),
            makeRemoteModel(id: "img-unsupported", supportedTools: [])
        ]
        mockPreferences.selectedModelId = "img-supported"
        controller.onOmnibarActivated()
        await waitForModels()
        controller.toggleImageGenerationMode()
        XCTAssertTrue(controller.isImageGenerationMode)

        // When
        controller.updateSelectedModel("img-unsupported")

        // Then
        XCTAssertFalse(controller.isImageGenerationMode)
    }

    func testWhenSwitchingBetweenSupportingModels_ThenImageGenerationModeIsPreserved() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "img-a", supportedTools: ["GenerateImage"]),
            makeRemoteModel(id: "img-b", supportedTools: ["GenerateImage"])
        ]
        mockPreferences.selectedModelId = "img-a"
        controller.onOmnibarActivated()
        await waitForModels()
        controller.toggleImageGenerationMode()
        XCTAssertTrue(controller.isImageGenerationMode)

        // When
        controller.updateSelectedModel("img-b")

        // Then
        XCTAssertTrue(controller.isImageGenerationMode)
    }

    func testWhenFetchModelsRevealsUnsupportedPersistedModel_ThenImageGenerationModeIsDeactivated() async {
        // Given — user toggled Create Image before models loaded (conservative default allowed it),
        // persisted model turns out not to support it
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "no-img", supportedTools: [])
        ]
        mockPreferences.selectedModelId = "no-img"
        controller.toggleImageGenerationMode()
        XCTAssertTrue(controller.isImageGenerationMode)

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertFalse(controller.isImageGenerationMode)
    }

    // MARK: - Image Generation Submission Parameter Tests

    func testWhenImageGenerationModeWithCapableSelectedModel_ThenSubmissionUsesSelectedModelAndToolChoice() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "img-model", supportedTools: ["GenerateImage"])
        ]
        mockPreferences.selectedModelId = "img-model"
        controller.onOmnibarActivated()
        await waitForModels()

        // When
        controller.toggleImageGenerationMode()

        // Then — explicit model + GenerateImage tool choice, no legacy mode handoff
        XCTAssertEqual(controller.effectiveModelId, "img-model")
        XCTAssertEqual(controller.effectiveToolChoice, [AIChatRAGTool.imageGeneration.rawValue])
        XCTAssertNil(controller.effectiveMode)
    }

    func testWhenImageGenerationModeWithIncapableSelectedModel_ThenSubmissionFallsBackToFirstCapableModel() async {
        // Given — image mode active with a non-capable model selected. Gating normally prevents
        // this, but the tool mode can be restored from a tab's saved state, so submission must
        // still resolve an image-capable model.
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "mistral", supportedTools: []),
            makeRemoteModel(id: "premium-img", entityHasAccess: false, supportedTools: ["GenerateImage"]),
            makeRemoteModel(id: "free-img", supportedTools: ["GenerateImage"])
        ]
        mockPreferences.selectedModelId = "mistral"
        controller.onOmnibarActivated()
        await waitForModels()

        // When
        controller.toggleImageGenerationMode()

        // Then — inaccessible capable model is skipped, first accessible capable one wins
        XCTAssertEqual(controller.effectiveModelId, "free-img")
        XCTAssertEqual(controller.effectiveToolChoice, [AIChatRAGTool.imageGeneration.rawValue])
        XCTAssertNil(controller.effectiveMode)
    }

    func testWhenImageGenerationModeAndModelsNotLoaded_ThenSubmissionFallsBackToModeHandoff() {
        // Given — no models fetched

        // When
        controller.toggleImageGenerationMode()

        // Then — legacy shape: duck.ai routes the request from the mode field
        XCTAssertNil(controller.effectiveModelId)
        XCTAssertNil(controller.effectiveToolChoice)
        XCTAssertEqual(controller.effectiveMode, AIChatNativePrompt.imageGenerationMode)
    }

    func testWhenNotInImageGenerationMode_ThenModeAndImageToolChoiceAreNotSent() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "img-model", supportedTools: ["GenerateImage"])
        ]
        mockPreferences.selectedModelId = "img-model"
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertEqual(controller.effectiveModelId, "img-model")
        XCTAssertNil(controller.effectiveToolChoice)
        XCTAssertNil(controller.effectiveMode)
    }

    func testWhenSubmitInImageGenerationMode_ThenPromptCarriesModelIdAndToolChoice() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "img-model", supportedTools: ["GenerateImage"])
        ]
        mockPreferences.selectedModelId = "img-model"
        controller.onOmnibarActivated()
        await waitForModels()
        controller.toggleImageGenerationMode()
        controller.updateText("a war potato")

        // When
        controller.submit()
        try? await Task.sleep(nanoseconds: 100_000_000)

        // Then
        XCTAssertTrue(mockTabOpener.openAIChatTabCalled, "Submit opens the duck.ai tab")
        let prompt = AIChatPromptHandler.shared.consumeData()
        guard case .query(let query) = prompt?.tool else {
            XCTFail("Expected a `.query` tool in the submitted prompt")
            return
        }
        XCTAssertEqual(query.prompt, "a war potato")
        XCTAssertEqual(query.modelId, "img-model")
        XCTAssertEqual(query.toolChoice, [AIChatRAGTool.imageGeneration.rawValue])
        XCTAssertNil(query.mode)
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
        XCTAssertEqual(controller.displayedReasoningEffort, AIChatReasoningEffort.none)
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

    func testWhenPersistedEffortIsSupportedButGatedAboveTier_ThenEffectiveReasoningEffortIsNil() async {
        // Given — a free user with a persisted `.medium` effort that the model still *supports* but
        // that is gated to plus/pro (e.g. selected while on Plus, then lapsed to free). It survives
        // stale-effort cleanup (still supported), so the submit path must be the one to drop it.
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        setUserTier(nil)
        mockModelsService.modelsToReturn = [
            makeRemoteModel(
                id: "gated-effort-model",
                entityHasAccess: true,
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: [
                    AIChatReasoningEffortAccess(effort: .none, accessTier: ["free", "plus", "pro"], entityHasAccess: true),
                    AIChatReasoningEffortAccess(effort: .low, accessTier: ["free", "plus", "pro"], entityHasAccess: true),
                    AIChatReasoningEffortAccess(effort: .medium, accessTier: ["plus", "pro"], entityHasAccess: false)
                ]
            )
        ]
        mockPreferences.selectedModelId = "gated-effort-model"
        mockPreferences.selectedReasoningEffort = "medium"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then — the model supports `.medium` (so it isn't cleared as stale) but the free user can't
        // access it, so it must not be attached to the submission.
        XCTAssertTrue(controller.selectedModelReasoningEfforts.contains(.medium), "precondition: model still supports the effort")
        XCTAssertFalse(controller.isReasoningEffortAccessible(.medium), "precondition: effort is gated for this tier")
        XCTAssertNil(controller.effectiveReasoningEffort)
    }

    func testWhenPersistedEffortIsGatedAboveTier_ThenDisplayedReasoningEffortIsNil() async {
        // Given — same downgrade scenario: a free user with a persisted `.medium` the model still
        // supports but the tier can't access. The chip must not present a gated effort as selected;
        // it falls back to the accessible default (mirrors effectiveReasoningEffort).
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        setUserTier(nil)
        mockModelsService.modelsToReturn = [
            makeRemoteModel(
                id: "gated-effort-model",
                entityHasAccess: true,
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: [
                    AIChatReasoningEffortAccess(effort: .none, accessTier: ["free", "plus", "pro"], entityHasAccess: true),
                    AIChatReasoningEffortAccess(effort: .low, accessTier: ["free", "plus", "pro"], entityHasAccess: true),
                    AIChatReasoningEffortAccess(effort: .medium, accessTier: ["plus", "pro"], entityHasAccess: false)
                ]
            )
        ]
        mockPreferences.selectedModelId = "gated-effort-model"
        mockPreferences.selectedReasoningEffort = "medium"

        // When
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertNil(controller.displayedReasoningEffort)
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

    // MARK: - Subscription Gating Tests

    func testWhenModelHasNoReasoningEffortAccess_ThenEffortIsAccessible() async {
        // Given — graceful degradation: a model predating `reasoningEffortAccess` gates nothing
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "legacy-model", entityHasAccess: true, supportedReasoningEffort: [.none, .low, .medium])
        ]
        mockPreferences.selectedModelId = "legacy-model"
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertTrue(controller.isReasoningEffortAccessible(.medium))
        XCTAssertNil(controller.requiredTier(for: .medium))
    }

    func testWhenEffortIsGatedForFreeUser_ThenIsReasoningEffortAccessibleReturnsFalse() async {
        // Given — free user, `.medium` requires plus/pro
        setUserTier(nil)
        mockModelsService.modelsToReturn = [
            makeRemoteModel(
                id: "gated-model",
                entityHasAccess: true,
                supportedReasoningEffort: [.none, .low, .medium],
                reasoningEffortAccess: [
                    AIChatReasoningEffortAccess(effort: .none, accessTier: ["free", "plus", "pro"], entityHasAccess: true),
                    AIChatReasoningEffortAccess(effort: .low, accessTier: ["free", "plus", "pro"], entityHasAccess: true),
                    AIChatReasoningEffortAccess(effort: .medium, accessTier: ["plus", "pro"], entityHasAccess: false)
                ]
            )
        ]
        mockPreferences.selectedModelId = "gated-model"
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertFalse(controller.isReasoningEffortAccessible(.medium))
        XCTAssertTrue(controller.isReasoningEffortAccessible(.low))
    }

    func testWhenEffortIsGated_ThenRequiredTierMatchesLowestAccessTier() async {
        // Given — `.medium` requires plus or pro; lowest is plus
        mockModelsService.modelsToReturn = [
            makeRemoteModel(
                id: "gated-model",
                entityHasAccess: true,
                supportedReasoningEffort: [.none, .medium],
                reasoningEffortAccess: [
                    AIChatReasoningEffortAccess(effort: .none, accessTier: ["free", "plus", "pro"], entityHasAccess: true),
                    AIChatReasoningEffortAccess(effort: .medium, accessTier: ["plus", "pro"], entityHasAccess: false)
                ]
            )
        ]
        mockPreferences.selectedModelId = "gated-model"
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertEqual(controller.requiredTier(for: .medium), .plus)
    }

    func testWhenEffortIsGatedToProOnly_ThenRequiredTierIsPro() async {
        // Given — `.medium` requires pro only
        mockModelsService.modelsToReturn = [
            makeRemoteModel(
                id: "pro-gated-model",
                entityHasAccess: true,
                supportedReasoningEffort: [.none, .medium],
                reasoningEffortAccess: [
                    AIChatReasoningEffortAccess(effort: .none, accessTier: ["free", "plus", "pro"], entityHasAccess: true),
                    AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro"], entityHasAccess: false)
                ]
            )
        ]
        mockPreferences.selectedModelId = "pro-gated-model"
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertEqual(controller.requiredTier(for: .medium), .pro)
    }

    func testWhenHandleReasoningEffortSelectionForAccessibleEffort_ThenEffortIsSelectedAndPersisted() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "open-model", entityHasAccess: true, supportedReasoningEffort: [.none, .low])
        ]
        mockPreferences.selectedModelId = "open-model"
        controller.onOmnibarActivated()
        await waitForModels()

        // When
        let outcome = controller.handleReasoningEffortSelection(.low)

        // Then
        XCTAssertEqual(outcome, .selected(.low))
        XCTAssertEqual(mockPreferences.selectedReasoningEffort, "low")
        XCTAssertFalse(mockSubscriptionUpsellPresenter.routeGatedSelectionCalled,
                        "Selecting an accessible effort must not touch the upsell presenter")
    }

    func testWhenHandleReasoningEffortSelectionForGatedEffort_ThenOutcomeIsGatedAndSelectionUnchanged() async {
        // Given — `.medium` is gated; nothing persisted yet
        mockModelsService.modelsToReturn = [
            makeRemoteModel(
                id: "gated-model",
                entityHasAccess: true,
                supportedReasoningEffort: [.none, .medium],
                reasoningEffortAccess: [
                    AIChatReasoningEffortAccess(effort: .none, accessTier: ["free", "plus", "pro"], entityHasAccess: true),
                    AIChatReasoningEffortAccess(effort: .medium, accessTier: ["pro"], entityHasAccess: false)
                ]
            )
        ]
        mockPreferences.selectedModelId = "gated-model"
        controller.onOmnibarActivated()
        await waitForModels()

        // When
        let outcome = controller.handleReasoningEffortSelection(.medium)

        // Then — outcome reports the gate; the controller itself does not navigate (that's the
        // caller's job, after showing a confirmation dialog) or change the persisted selection.
        XCTAssertEqual(outcome, .gated(requiredTier: .pro))
        XCTAssertNil(mockPreferences.selectedReasoningEffort)
        XCTAssertFalse(mockSubscriptionUpsellPresenter.routeGatedSelectionCalled,
                        "handleReasoningEffortSelection must not navigate directly — the reasoning-picker flow shows a confirmation dialog first")
    }

    func testWhenPresentSubscriptionUpsellCalled_ThenPresenterRoutesWithCurrentUserTierAndOrigin() {
        // Given — a plus user (as if resolved from a prior fetch)
        setUserTier(.plus)

        // When
        controller.presentSubscriptionUpsell(requiredTier: .pro, origin: .addressBarReasoningPicker)

        // Then
        XCTAssertTrue(mockSubscriptionUpsellPresenter.routeGatedSelectionCalled)
        XCTAssertEqual(mockSubscriptionUpsellPresenter.lastRequiredTier, .pro)
        XCTAssertEqual(mockSubscriptionUpsellPresenter.lastOrigin, .addressBarReasoningPicker)
    }

    func testWhenRequiredTierForGatedModel_ThenReturnsModelsLowestPublicAccessTier() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "gated-model", entityHasAccess: false, accessTier: ["pro"])
        ]
        controller.onOmnibarActivated()
        await waitForModels()
        let gatedModel = controller.models.first { $0.id == "gated-model" }!

        // When
        let requiredTier = controller.requiredTier(for: gatedModel)

        // Then — the controller only reports the gate; the caller (view controller) shows a
        // confirmation dialog before calling presentSubscriptionUpsell, same as a gated reasoning effort.
        XCTAssertEqual(requiredTier, .pro)
        XCTAssertFalse(mockSubscriptionUpsellPresenter.routeGatedSelectionCalled)
    }

    func testWhenRequiredTierForAccessibleModel_ThenReturnsNil() async {
        // Given
        mockModelsService.modelsToReturn = [
            makeRemoteModel(id: "open-model", entityHasAccess: true)
        ]
        controller.onOmnibarActivated()
        await waitForModels()
        let accessibleModel = controller.models.first { $0.id == "open-model" }!

        // When
        let requiredTier = controller.requiredTier(for: accessibleModel)

        // Then
        XCTAssertNil(requiredTier, "An already-accessible model must never report a required tier")
    }

    // MARK: - Free-Trial Eligibility Tests

    func testWhenFreeUserIsTrialEligible_ThenShouldOfferFreeTrialIsTrue() async {
        // Given — a free user whose device is still eligible for an introductory trial
        setUserTier(nil)
        mockSubscriptionManager.isEligibleForFreeTrialResult = true
        mockModelsService.modelsToReturn = [makeRemoteModel(id: "m", entityHasAccess: true)]
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertTrue(controller.shouldOfferFreeTrial)
    }

    func testWhenFreeUserIsTrialIneligible_ThenShouldOfferFreeTrialIsFalse() async {
        // Given — a free user who has already used their trial
        setUserTier(nil)
        mockSubscriptionManager.isEligibleForFreeTrialResult = false
        mockModelsService.modelsToReturn = [makeRemoteModel(id: "m", entityHasAccess: true)]
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertFalse(controller.shouldOfferFreeTrial)
    }

    func testWhenUserIsPlus_ThenShouldOfferFreeTrialIsFalseRegardlessOfEligibility() async {
        // Given — a Plus subscriber; trial eligibility must not matter, they upgrade, not trial
        setUserTier(.plus)
        mockSubscriptionManager.isEligibleForFreeTrialResult = true
        mockModelsService.modelsToReturn = [makeRemoteModel(id: "m", entityHasAccess: true)]
        controller.onOmnibarActivated()
        await waitForModels()

        // Then
        XCTAssertFalse(controller.shouldOfferFreeTrial, "An existing subscriber always sees Upgrade, never Try for Free")
    }

    // MARK: - Badge Impression Cap Tests

    func testWhenImpressionCapNotReached_ThenBadgeIsNotMuted() {
        // Given — three views of a four-view cap
        controller.recordBadgeImpression()
        controller.recordBadgeImpression()
        controller.recordBadgeImpression()

        // Then — still shown in full color
        XCTAssertFalse(controller.isBadgeMuted)
    }

    func testWhenImpressionCapReached_ThenBadgeIsMuted() {
        // Given — four views reaches the cap
        controller.recordBadgeImpression()
        controller.recordBadgeImpression()
        controller.recordBadgeImpression()
        controller.recordBadgeImpression()

        // Then — the badge stays but is muted from here on
        XCTAssertTrue(controller.isBadgeMuted)
    }

    // MARK: - Subscription Activation Tests

    func testWhenPresentSubscriptionActivationFlow_ThenPresenterActivationIsCalled() {
        // When
        controller.presentSubscriptionActivationFlow()

        // Then — routed through the injected presenter, not the app-delegate singleton
        XCTAssertTrue(mockSubscriptionUpsellPresenter.presentSubscriptionActivationCalled)
    }

    // MARK: - Model Picker Content (modelPickerItems)

    func testModelPickerItems_freeUserUpsellOn_accessibleThenSubscriberExclusiveGatedSection() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarSubscriptionUpsell.rawValue] = true
        await loadModels([
            makeRemoteModel(id: "free-a", accessTier: ["free"]),
            makeRemoteModel(id: "free-b", accessTier: ["free"]),
            makeRemoteModel(id: "gated-plus", accessTier: ["plus", "pro"]),
            makeRemoteModel(id: "gated-pro", accessTier: ["pro"]),
        ], tier: nil, trialEligible: true)

        let items = controller.modelPickerItems(selectedModelId: nil)

        let accessible = accessibleRows(items)
        XCTAssertEqual(accessible.map(\.id), ["free-a", "free-b"])
        XCTAssertNil(accessible[0].badge, "Free-tier models carry no trailing badge")

        XCTAssertTrue(hasSeparator(items))

        let header = gatedHeader(in: items)
        XCTAssertEqual(header?.title, UserText.aiChatModelPickerSubscriberExclusive)
        XCTAssertEqual(header?.badge, UserText.aiChatModelPickerTryForFree, "Trial-eligible free user sees Try for free")
        XCTAssertEqual(header?.representativeId, "gated-plus", "First gated model represents the header's routing tier")

        let gated = gatedRows(items)
        XCTAssertEqual(gated.map(\.id), ["gated-plus", "gated-pro"])
        XCTAssertEqual(gated[0].badge, UserText.aiChatModelPickerTierBadgePlus)
        XCTAssertEqual(gated[1].badge, UserText.aiChatModelPickerTierBadgePro)
    }

    func testModelPickerItems_plusUserUpsellOn_proExclusiveHeaderUpgradeBadgeAndPlusModelsBadged() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarSubscriptionUpsell.rawValue] = true
        await loadModels([
            makeRemoteModel(id: "basic", accessTier: ["free", "plus"]),
            makeRemoteModel(id: "plus-only", accessTier: ["plus"]),
            makeRemoteModel(id: "pro-only", accessTier: ["pro"]),
        ], tier: .plus, trialEligible: true)

        let items = controller.modelPickerItems(selectedModelId: nil)

        let accessible = accessibleRows(items)
        XCTAssertEqual(accessible.map(\.id), ["basic", "plus-only"])
        XCTAssertNil(accessible[0].badge, "A free+plus model resolves to the free tier — no badge")
        XCTAssertEqual(accessible[1].badge, UserText.aiChatModelPickerTierBadgePlus,
                       "An already-accessible plus-only model is still badged PLUS")

        let header = gatedHeader(in: items)
        XCTAssertEqual(header?.title, UserText.aiChatModelPickerProExclusive,
                       "A Plus user's remaining gated models are all Pro-only")
        XCTAssertEqual(header?.badge, UserText.aiChatModelPickerUpgrade,
                       "A subscriber always sees Upgrade, never Try for free, regardless of trial eligibility")

        XCTAssertEqual(gatedRows(items).map(\.id), ["pro-only"])
        XCTAssertEqual(gatedRows(items).first?.badge, UserText.aiChatModelPickerTierBadgePro)
    }

    func testModelPickerItems_freeUserTrialIneligible_usesUpgradeBadge() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarSubscriptionUpsell.rawValue] = true
        await loadModels([
            makeRemoteModel(id: "gated-plus", accessTier: ["plus"]),
        ], tier: nil, trialEligible: false)

        let items = controller.modelPickerItems(selectedModelId: nil)

        XCTAssertEqual(gatedHeader(in: items)?.badge, UserText.aiChatModelPickerUpgrade,
                       "A free user who already used their trial sees Upgrade")
    }

    func testModelPickerItems_upsellOff_gatedRowsShownWithoutHeaderAndNoImpression() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarSubscriptionUpsell.rawValue] = false
        await loadModels([
            makeRemoteModel(id: "free-a", accessTier: ["free"]),
            makeRemoteModel(id: "gated-pro", accessTier: ["pro"]),
        ], tier: nil)

        let before = mockBadgeImpressionPersistor.viewCount
        let items = controller.modelPickerItems(selectedModelId: nil)

        XCTAssertTrue(hasSeparator(items), "Separator still divides accessible from gated when the flag is off")
        XCTAssertNil(gatedHeader(in: items), "No upsell header when the flag is off")
        XCTAssertEqual(gatedRows(items).map(\.id), ["gated-pro"], "Gated rows still render (dimmed) so they can't be selected")
        XCTAssertEqual(mockBadgeImpressionPersistor.viewCount, before, "No badge impression recorded when no header is shown")
    }

    func testModelPickerItems_noGatedModels_noSeparatorHeaderOrImpression() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarSubscriptionUpsell.rawValue] = true
        await loadModels([
            makeRemoteModel(id: "free-a", accessTier: ["free"]),
            makeRemoteModel(id: "free-b", accessTier: ["free"]),
        ], tier: nil, trialEligible: true)

        let before = mockBadgeImpressionPersistor.viewCount
        let items = controller.modelPickerItems(selectedModelId: nil)

        XCTAssertEqual(accessibleRows(items).map(\.id), ["free-a", "free-b"])
        XCTAssertFalse(hasSeparator(items))
        XCTAssertNil(gatedHeader(in: items))
        XCTAssertTrue(gatedRows(items).isEmpty)
        XCTAssertEqual(mockBadgeImpressionPersistor.viewCount, before)
    }

    func testModelPickerItems_recordsOneBadgeImpressionPerCallWhenHeaderShown() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarSubscriptionUpsell.rawValue] = true
        await loadModels([
            makeRemoteModel(id: "gated-pro", accessTier: ["pro"]),
        ], tier: nil, trialEligible: true)

        XCTAssertEqual(mockBadgeImpressionPersistor.viewCount, 0)
        _ = controller.modelPickerItems(selectedModelId: nil)
        XCTAssertEqual(mockBadgeImpressionPersistor.viewCount, 1, "One impression per menu open")
        _ = controller.modelPickerItems(selectedModelId: nil)
        XCTAssertEqual(mockBadgeImpressionPersistor.viewCount, 2)
    }

    func testModelPickerItems_headerMutedWhenImpressionCapReached() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarSubscriptionUpsell.rawValue] = true
        await loadModels([
            makeRemoteModel(id: "gated-pro", accessTier: ["pro"]),
        ], tier: nil, trialEligible: true)
        // Reach the 4-view cap configured in setUp.
        for _ in 0..<4 { controller.recordBadgeImpression() }
        XCTAssertTrue(controller.isBadgeMuted)

        let items = controller.modelPickerItems(selectedModelId: nil)

        XCTAssertEqual(gatedHeader(in: items)?.isMuted, true)
    }

    func testModelPickerItems_marksSelectedAccessibleRow() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarSubscriptionUpsell.rawValue] = true
        await loadModels([
            makeRemoteModel(id: "free-a", accessTier: ["free"]),
            makeRemoteModel(id: "free-b", accessTier: ["free"]),
        ], tier: nil)

        let rows = accessibleRows(controller.modelPickerItems(selectedModelId: "free-b"))

        XCTAssertEqual(rows.first { $0.id == "free-a" }?.isSelected, false)
        XCTAssertEqual(rows.first { $0.id == "free-b" }?.isSelected, true)
    }

    // MARK: - Reasoning Picker Item Tests

    /// A model whose `.medium` effort is gated to plus/pro, with `.none`/`.low` open to everyone.
    private func gatedEffortModel() -> AIChatRemoteModel {
        makeRemoteModel(
            id: "reasoning-model",
            entityHasAccess: true,
            supportedReasoningEffort: [.none, .low, .medium],
            reasoningEffortAccess: [
                AIChatReasoningEffortAccess(effort: .none, accessTier: ["free", "plus", "pro"], entityHasAccess: true),
                AIChatReasoningEffortAccess(effort: .low, accessTier: ["free", "plus", "pro"], entityHasAccess: true),
                AIChatReasoningEffortAccess(effort: .medium, accessTier: ["plus", "pro"], entityHasAccess: false)
            ]
        )
    }

    func testReasoningPickerItems_freeUserUpsellOn_gatedEffortHasTryForFreeBadge() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarSubscriptionUpsell.rawValue] = true
        mockPreferences.selectedModelId = "reasoning-model"
        await loadModels([gatedEffortModel()], tier: nil, trialEligible: true)

        let items = controller.reasoningPickerItems()
        let gated = items.first { $0.effort == .medium }
        let open = items.first { $0.effort == .low }

        XCTAssertEqual(gated?.isGated, true)
        XCTAssertEqual(gated?.upsellBadge, UserText.aiChatModelPickerTryForFree)
        XCTAssertNil(gated?.trailingText, "Upsell badge replaces the plain PLUS/PRO label")
        XCTAssertEqual(gated?.isSelected, false)
        XCTAssertEqual(open?.isGated, false)
        XCTAssertNil(open?.upsellBadge)
    }

    func testReasoningPickerItems_freeUserTrialIneligible_gatedEffortHasUpgradeBadge() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarSubscriptionUpsell.rawValue] = true
        mockPreferences.selectedModelId = "reasoning-model"
        await loadModels([gatedEffortModel()], tier: nil, trialEligible: false)

        let gated = controller.reasoningPickerItems().first { $0.effort == .medium }

        XCTAssertEqual(gated?.upsellBadge, UserText.aiChatModelPickerUpgrade)
    }

    func testReasoningPickerItems_upsellOff_gatedEffortShowsTierLabelNoBadge() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        // Upsell flag left off.
        mockPreferences.selectedModelId = "reasoning-model"
        await loadModels([gatedEffortModel()], tier: nil, trialEligible: true)

        let gated = controller.reasoningPickerItems().first { $0.effort == .medium }

        XCTAssertEqual(gated?.isGated, true)
        XCTAssertNil(gated?.upsellBadge, "No badge when the upsell is off")
        XCTAssertEqual(gated?.trailingText, UserText.aiChatModelPickerTierBadgePlus)
    }

    func testReasoningPickerItems_recordsOneImpressionWhenUpsellBadgeShown() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarSubscriptionUpsell.rawValue] = true
        mockPreferences.selectedModelId = "reasoning-model"
        await loadModels([gatedEffortModel()], tier: nil, trialEligible: true)

        _ = controller.reasoningPickerItems()

        XCTAssertEqual(mockBadgeImpressionPersistor.viewCount, 1, "One impression per open, not one per gated row")
    }

    func testReasoningPickerItems_upsellOff_recordsNoImpression() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        mockPreferences.selectedModelId = "reasoning-model"
        await loadModels([gatedEffortModel()], tier: nil, trialEligible: true)

        _ = controller.reasoningPickerItems()

        XCTAssertEqual(mockBadgeImpressionPersistor.viewCount, 0)
    }

    func testReasoningPickerItems_marksCurrentAccessibleEffortSelected() async {
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarReasoningEffort.rawValue] = true
        featureFlagger.featuresStub[FeatureFlag.aiChatOmnibarSubscriptionUpsell.rawValue] = true
        mockPreferences.selectedModelId = "reasoning-model"
        mockPreferences.selectedReasoningEffort = "low"
        await loadModels([gatedEffortModel()], tier: nil, trialEligible: true)

        let items = controller.reasoningPickerItems()

        XCTAssertEqual(items.first { $0.effort == .low }?.isSelected, true)
        XCTAssertEqual(items.first { $0.effort == .medium }?.isSelected, false, "A gated effort is never marked selected")
    }

    // MARK: - Helpers

    /// Creates a remote model for testing. Access is resolved locally from `accessTier`
    /// (not `entityHasAccess`), so `accessTier` must include `"free"` for the model to be
    /// accessible to the default free-tier test user.
    ///
    /// `supportedFileTypes` defaults to `nil` (no file upload support). Tests that exercise
    /// the PDF/file-attachment submission path must pass a non-empty array — the controller's
    /// `selectedModelSupportsFileUpload` gate is `!supportedFileTypes.isEmpty`, and the
    /// submit body silently drops the file payload when that returns `false`.
    private func makeRemoteModel(
        id: String,
        supportsImageUpload: Bool = false,
        supportedFileTypes: [String]? = nil,
        entityHasAccess: Bool = true,
        supportedTools: [String] = [],
        supportedReasoningEffort: [AIChatReasoningEffort] = [],
        accessTier: [String]? = nil,
        reasoningEffortAccess: [AIChatReasoningEffortAccess]? = nil
    ) -> AIChatRemoteModel {
        AIChatRemoteModel(
            id: id,
            name: id,
            modelShortName: nil,
            provider: "openai",
            entityHasAccess: entityHasAccess,
            supportsImageUpload: supportsImageUpload,
            supportedFileTypes: supportedFileTypes,
            supportedTools: supportedTools,
            accessTier: accessTier ?? (entityHasAccess ? ["free"] : ["plus", "pro"]),
            supportedReasoningEffort: supportedReasoningEffort,
            reasoningEffortAccess: reasoningEffortAccess
        )
    }

    /// Configures the mock subscription manager to resolve to `tier` (`nil` maps to a free/no-tier
    /// active subscription). `AIChatOmnibarController.resolveUserTier()` reads this via
    /// `subscriptionManager.getSubscription(forceRefresh:)`.
    private func setUserTier(_ tier: TierName?) {
        let subscription = DuckDuckGoSubscription(
            productId: "test",
            name: "test",
            billingPeriod: .yearly,
            startedAt: Date(),
            expiresOrRenewsAt: Date().addingTimeInterval(86400 * 30),
            platform: .apple,
            status: .autoRenewable,
            activeOffers: [],
            tier: tier,
            availableChanges: nil,
            pendingPlans: nil
        )
        mockSubscriptionManager.resultSubscription = .success(subscription)
    }

    private func waitForModels() async {
        // Allow the async Task inside onOmnibarActivated to complete
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    private func makeAttachment(id: UUID = UUID()) -> AIChatImageAttachment {
        AIChatImageAttachment(id: id, image: NSImage(), fileName: "\(id.uuidString).png", fileURL: nil, skipResize: true)
    }

    private func makeTabAttachment(id: String = UUID().uuidString) -> AIChatTabAttachment {
        AIChatTabAttachment(
            id: id,
            title: "Example",
            url: URL(string: "https://example.com")!,
            favicon: nil
        )
    }

    private func makeFileAttachment(fileName: String = "spec.pdf") -> AIChatFileAttachment {
        AIChatFileAttachment(
            data: Data("%PDF-1.4 mock".utf8),
            fileName: fileName,
            mimeType: "application/pdf"
        )
    }

    /// Loads `models` and resolves the user's tier + trial eligibility, mirroring a real fetch.
    private func loadModels(_ models: [AIChatRemoteModel], tier: TierName?, trialEligible: Bool = false) async {
        setUserTier(tier)
        mockSubscriptionManager.isEligibleForFreeTrialResult = trialEligible
        mockModelsService.modelsToReturn = models
        controller.onOmnibarActivated()
        await waitForModels()
    }

    // Accessors that flatten `[AIChatModelPickerItem]` for assertions (the enum isn't Equatable).
    private struct PickerRow { let id: String; let badge: String?; let isSelected: Bool }
    private struct PickerHeader { let title: String; let badge: String; let isMuted: Bool; let representativeId: String? }

    private func accessibleRows(_ items: [AIChatModelPickerItem]) -> [PickerRow] {
        items.compactMap { item -> PickerRow? in
            guard case let .model(model, badge, isSelected) = item else { return nil }
            return PickerRow(id: model.id, badge: badge, isSelected: isSelected)
        }
    }

    private func gatedRows(_ items: [AIChatModelPickerItem]) -> [PickerRow] {
        items.compactMap { item -> PickerRow? in
            guard case let .gatedModel(model, badge) = item else { return nil }
            return PickerRow(id: model.id, badge: badge, isSelected: false)
        }
    }

    private func gatedHeader(in items: [AIChatModelPickerItem]) -> PickerHeader? {
        for item in items {
            guard case let .gatedHeader(title, badge, isMuted, representative) = item else { continue }
            return PickerHeader(title: title, badge: badge, isMuted: isMuted, representativeId: representative?.id)
        }
        return nil
    }

    private func hasSeparator(_ items: [AIChatModelPickerItem]) -> Bool {
        items.contains { if case .separator = $0 { return true }; return false }
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
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}

// MARK: - Mock Models Service

@MainActor
private class MockAIChatModelsProviding: AIChatModelsProviding {
    var modelsToReturn: [AIChatRemoteModel] = []
    var errorToThrow: Error?

    func fetchModels() async throws -> AIChatModelsResponse {
        if let error = errorToThrow {
            throw error
        }
        return AIChatModelsResponse(models: modelsToReturn)
    }
}

// MARK: - Mock Subscription Upsell Presenter

@MainActor
private class MockAIChatOmnibarSubscriptionUpselling: AIChatOmnibarSubscriptionUpselling {
    var routeGatedSelectionCalled = false
    var lastRequiredTier: AIChatModelPublicAccessTier?
    var lastUserTier: AIChatUserTier?
    var lastOrigin: SubscriptionFunnelOrigin?
    var returnValue = true
    var presentSubscriptionActivationCalled = false

    func routeGatedSelection(requiredTier: AIChatModelPublicAccessTier, userTier: AIChatUserTier, origin: SubscriptionFunnelOrigin) -> Bool {
        routeGatedSelectionCalled = true
        lastRequiredTier = requiredTier
        lastUserTier = userTier
        lastOrigin = origin
        return returnValue
    }

    func presentSubscriptionActivation() {
        presentSubscriptionActivationCalled = true
    }
}

private final class MockFreeTrialBadgePersistor: FreeTrialBadgePersisting {
    private(set) var viewCount: Int
    private let cap: Int

    init(initialCount: Int, cap: Int) {
        self.viewCount = initialCount
        self.cap = cap
    }

    var hasReachedViewLimit: Bool { viewCount >= cap }

    func incrementViewCount() {
        if viewCount < cap { viewCount += 1 }
    }
}
