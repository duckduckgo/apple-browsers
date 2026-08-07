//
//  UnifiedToggleInputCoordinatorPerTabStateTests.swift
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
import UIKit
import XCTest
@testable import DuckDuckGo

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
