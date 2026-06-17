//
//  AIChatOmnibarController.swift
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

import Cocoa
import Combine
import AIChat
import FeatureFlags
import os.log
import Persistence
import PixelKit
import PrivacyConfig
import Subscription
import URLPredictor

protocol AIChatOmnibarControllerDelegate: AnyObject {
    func aiChatOmnibarControllerDidSubmit(_ controller: AIChatOmnibarController)
    func aiChatOmnibarController(_ controller: AIChatOmnibarController, didRequestNavigationToURL url: URL)
    func aiChatOmnibarController(_ controller: AIChatOmnibarController, didSelectSuggestion suggestion: AIChatSuggestion)
}

/// Duck.ai omnibar tool selection. Preserved across tab switches via `AddressBarSharedTextState`.
enum AIChatToolMode: Equatable {
    case imageGeneration
    case webSearch
}

/// Controller that manages the state and actions for the AI Chat omnibar.
/// This controller is shared between AIChatOmnibarContainerViewController and AIChatOmnibarTextContainerViewController
/// to coordinate text input and submission.
@MainActor
final class AIChatOmnibarController {
    @Published private(set) var currentText: String = ""
    @Published private(set) var activeToolMode: AIChatToolMode?
    @Published var hasImageAttachments: Bool = false

    /// The last selected reasoning effort, persisted across sessions. `nil` if no selection has
    /// been made, or the persisted raw value doesn't map to a known `AIChatReasoningEffort` case.
    var selectedReasoningEffort: AIChatReasoningEffort? {
        preferences.selectedReasoningEffort.flatMap(AIChatReasoningEffort.init(rawValue:))
    }

    var isImageGenerationMode: Bool { activeToolMode == .imageGeneration }
    var isWebSearchMode: Bool { activeToolMode == .webSearch }
    weak var delegate: AIChatOmnibarControllerDelegate?
    private let aiChatTabOpener: AIChatTabOpening
    private let promptHandler: AIChatPromptHandler
    private let tabCollectionViewModel: TabCollectionViewModel
    private let featureFlagger: FeatureFlagger
    private let searchPreferencesPersistor: SearchPreferencesPersistor
    private let suggestionsReader: AIChatSuggestionsReading?
    private let modelsService: AIChatModelsProviding
    private let subscriptionManager: any SubscriptionManager
    private var preferences: AIChatPreferencesPersisting
    private var cancellables = Set<AnyCancellable>()
    private var sharedTextStateCancellable: AnyCancellable?
    private var isUpdatingFromSharedState = false
    /// True while `cleanup()` is zeroing out controller-local state. Cleanup is a teardown of the controller's
    /// transient state, not a user action, so its side-effect writes must not reach shared state — otherwise
    /// when cleanup runs during a tab switch before the controller's `$selectedTabViewModel` sink has swapped
    /// `sharedTextState` to the incoming tab, the zeros stomp the *outgoing* tab's per-tab state.
    private(set) var isCleaningUp = false
    private var currentFetchTask: Task<Void, Never>?
    private var modelsFetchTask: Task<Void, Never>?
    private var hasBeenActivated = false

    /// Available AI models. Empty until successfully fetched from the API.
    @Published private(set) var models: [AIChatModel] = []

    /// Whether the user has an active paid subscription (plus or pro).
    private(set) var hasActiveSubscription = false

    /// Called after a successful submit so the container VC can cancel any in-flight image
    /// resize tasks (data is cleared via `persistAttachmentsToActiveTab([])`).
    var onAttachmentsClearRequested: (() -> Void)?

    /// Waits for all attachment resizing to complete before proceeding.
    var waitForAttachmentsReady: (() async -> Void)?

    /// Fires whenever the active tab's unified panel attachment list changes — either because
    /// the user switched tabs (new shared state with its own list) or because they added /
    /// removed an attachment in the current tab. The container VC subscribes to this single
    /// callback to drive the unified carousel; the publisher takes care of both
    /// "restore on tab switch" and "react to mutations" in one channel.
    var onActiveTabPanelAttachmentsChanged: (([AIChatPanelAttachment]) -> Void)?

    /// Cancellable for the active tab's `$aiChatPanelAttachments` subscription. Re-subscribed
    /// every time the selected tab changes.
    private var panelAttachmentsCancellable: AnyCancellable?

    /// View model for managing chat suggestions. Always initialized, but only populated when feature flag is enabled.
    let suggestionsViewModel: AIChatSuggestionsViewModel

    /// Whether the suggestions feature is enabled.
    /// Requires both the feature flag and the autocomplete setting to be on.
    var isSuggestionsEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatSuggestions) && searchPreferencesPersistor.showAutocompleteSuggestions
    }

    /// Whether the omnibar tools (customize, search toggle, image upload) are enabled.
    var isOmnibarToolsEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatOmnibarTools)
    }

    var isViewAllChatsEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatViewAllChatsNativeOmnibar)
    }

    /// Whether the image generation tool is available.
    var isImageGenerationEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatOmnibarImageGeneration)
    }

    /// Whether the web search tool is available.
    var isWebSearchEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatOmnibarWebSearch)
    }

    /// Whether the reasoning effort picker is available.
    var isReasoningEffortEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatOmnibarReasoningEffort)
    }

    /// Whether 1-click voice-chat access in the omnibar is available. When disabled, the submit
    /// button keeps its legacy "arrow / disabled when empty" behavior.
    var isVoiceChatAccessEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatOmnibarVoiceChatAccess)
    }

    /// Whether the omnibar's tab picker (Attach Page Content) is available.
    /// Requires both `aiChatPageContext` (the underlying extraction pipeline) and
    /// `aiChatOmnibarAttachMoreTabs` (the omnibar surface gate).
    var isOmnibarTabPickerEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatPageContext) && featureFlagger.isFeatureOn(.aiChatOmnibarAttachMoreTabs)
    }

    func toggleImageGenerationMode() {
        activeToolMode = isImageGenerationMode ? nil : .imageGeneration
    }

    func toggleWebSearchMode() {
        activeToolMode = isWebSearchMode ? nil : .webSearch
    }

    /// Publisher that emits when the omnibar tools enabled state changes.
    var isOmnibarToolsEnabledPublisher: AnyPublisher<Bool, Never> {
        featureFlagger.updatesPublisher
            .compactMap { [weak self] in
                self?.isOmnibarToolsEnabled
            }
            .prepend(isOmnibarToolsEnabled)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// The currently active tab's shared text state. Updated in the `$selectedTabViewModel` sink rather than
    /// computed on demand — `@Published` fires in willSet, so during the tab-switch emission chain the
    /// `selectedTabViewModel` stored property is still the *outgoing* tab. Delegate-chained callers such as
    /// `onOmnibarActivated` would otherwise read the stale outgoing tab's state (empty text / zero selection)
    /// and wipe the real saved cursor position for the incoming tab.
    private var sharedTextState: AddressBarSharedTextState?

    // MARK: - Initialization

    init(
        aiChatTabOpener: AIChatTabOpening,
        tabCollectionViewModel: TabCollectionViewModel,
        promptHandler: AIChatPromptHandler = .shared,
        featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
        searchPreferencesPersistor: SearchPreferencesPersistor = SearchPreferencesUserDefaultsPersistor(),
        suggestionsReader: AIChatSuggestionsReading? = nil,
        preferences: AIChatPreferencesPersisting = AIChatPreferencesPersistor(),
        modelsService: AIChatModelsProviding = AIChatModelsService(),
        subscriptionManager: any SubscriptionManager = Application.appDelegate.subscriptionManager
    ) {
        self.aiChatTabOpener = aiChatTabOpener
        self.tabCollectionViewModel = tabCollectionViewModel
        self.promptHandler = promptHandler
        self.featureFlagger = featureFlagger
        self.searchPreferencesPersistor = searchPreferencesPersistor
        self.suggestionsReader = suggestionsReader
        self.preferences = preferences
        self.modelsService = modelsService
        self.subscriptionManager = subscriptionManager
        self.suggestionsViewModel = AIChatSuggestionsViewModel(
            maxSuggestions: suggestionsReader?.maxHistoryCount ?? AIChatSuggestionsViewModel.defaultMaxSuggestions
        )

        subscribeToSelectedTabViewModel()
        subscribeToTextChangesForSuggestions()
        subscribeToToolModeChangesForSharedState()
    }

    /// Opens a new voice-chat tab from the AI chat omnibar. Focuses an existing voice session
    /// in the same window if one is active; otherwise opens a new selected Duck.ai tab and hands
    /// off `mode: voice-mode` via the prompt handler.
    func openNewVoiceChat() {
        // Defer the tab open: synchronously it tears the panel down mid-click, so the click falls through to the bookmarks bar behind.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.aiChatTabOpener.openVoiceSession(
                inSourceCollection: self.tabCollectionViewModel,
                behavior: .newTab(selected: true)
            )
        }
        PixelKit.fire(AIChatPixel.aiChatNewVoiceChatOmnibarNative, frequency: .dailyAndStandard, includeAppVersionParameter: true)
    }

    private func subscribeToTextChangesForSuggestions() {
        $currentText
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self, self.isSuggestionsEnabled else { return }
                self.fetchSuggestionsIfNeeded(query: text)
            }
            .store(in: &cancellables)
    }

    /// Persists the user's tool selection (image generation / web search) to the current tab's shared state
    /// so it survives tab switches. Skipped while we're mid-restore from shared state to avoid a feedback loop.
    private func subscribeToToolModeChangesForSharedState() {
        $activeToolMode
            .dropFirst()
            .sink { [weak self] mode in
                guard let self, !self.isUpdatingFromSharedState, !self.isCleaningUp else { return }
                self.sharedTextState?.setAIChatToolMode(mode)
            }
            .store(in: &cancellables)
    }

    // MARK: - Suggestions Fetching

    /// Called when the duck.ai omnibar becomes visible.
    /// Triggers a models fetch (on every activation) and suggestions fetch.
    /// - Parameter shouldFetchSuggestions: pass `false` when the activation should avoid triggering an async
    ///   suggestions fetch that would visibly expand the panel height after it appears (e.g. on tab-switch
    ///   presentation). User text input will still trigger suggestions via the debounced subscription once
    ///   `hasBeenActivated` is `true`.
    func onOmnibarActivated(shouldFetchSuggestions: Bool = true) {
        hasBeenActivated = true

        // Re-sync per-tab Duck.ai state from shared state in case a prior `cleanup()` cleared the controller-local copy.
        // Toggling Duck.ai → search runs `cleanup()` (zeroing `currentText`, `activeToolMode`, the attachments view),
        // but the tab's shared state still holds the draft; without re-sync, toggling back would show an empty panel.
        if let sharedTextState {
            if sharedTextState.hasUserInteractedWithText, currentText != sharedTextState.text {
                isUpdatingFromSharedState = true
                currentText = sharedTextState.text
                isUpdatingFromSharedState = false
            }
            if activeToolMode != sharedTextState.aiChatToolMode {
                isUpdatingFromSharedState = true
                activeToolMode = sharedTextState.aiChatToolMode
                isUpdatingFromSharedState = false
            }
            // Image, file, and tab restoration on activation now flows through the
            // `$aiChatPanelAttachments` publisher subscription set up in
            // `subscribeToSelectedTabViewModel()` — no separate restore callback needed.
        }

        fetchModels()

        // If feature is disabled, clear any existing suggestions and don't fetch
        if !isSuggestionsEnabled {
            suggestionsViewModel.clearAllChats()
            return
        }

        if shouldFetchSuggestions {
            fetchSuggestionsIfNeeded(query: currentText)
        }
    }

    private func fetchModels() {
        modelsFetchTask?.cancel()
        modelsFetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await modelsService.fetchModels()
                guard !Task.isCancelled else { return }
                let userTier = try await self.resolveUserTier()
                guard !Task.isCancelled else { return }
                self.hasActiveSubscription = userTier != .free
                self.models = response.models.map { AIChatModel(remoteModel: $0, userTier: userTier) }
                self.clearStaleModelSelectionIfNeeded()
                self.clearStaleReasoningEffortIfNeeded()
                self.deactivateWebSearchIfUnsupported()
            } catch is CancellationError {
                return
            } catch {
                Logger.aiChat.error("Failed to fetch models: \(error.localizedDescription)")
                PixelKit.fire(AIChatPixel.aiChatModelsFetchFailed, frequency: .dailyAndCount, includeAppVersionParameter: true)
            }
        }
    }

    private func resolveUserTier() async throws -> AIChatUserTier {
        do {
            guard let subscription = try await subscriptionManager.getSubscription(forceRefresh: false),
                  subscription.isActive else { return .free }
            switch subscription.tier {
            case .plus: return .plus
            case .pro: return .pro
            case .none: return .free
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .free
        }
    }

    private func fetchSuggestionsIfNeeded(query: String) {
        guard hasBeenActivated, isSuggestionsEnabled, let reader = suggestionsReader else { return }

        // Cancel any in-flight fetch
        currentFetchTask?.cancel()

        currentFetchTask = Task { [weak self] in
            guard let self else { return }

            let maxChats = isViewAllChatsEnabled ? reader.maxHistoryCount + 1 : reader.maxHistoryCount
            let suggestions = await reader.fetchSuggestions(query: query.isEmpty ? nil : query, maxChats: maxChats)

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            let totalFetched = suggestions.pinned.count + suggestions.recent.count
            let showViewAllChats = isViewAllChatsEnabled && totalFetched > reader.maxHistoryCount
            self.suggestionsViewModel.setChats(pinned: suggestions.pinned, recent: suggestions.recent, showViewAllChats: showViewAllChats)
        }
    }

    /// Re-fetches suggestions from the database using the current query text.
    func refreshSuggestions() {
        fetchSuggestionsIfNeeded(query: currentText)
    }

    // MARK: - Public Methods

    /// The persisted model ID. Falls back to the first accessible model if the
    /// persisted selection is no longer available or no longer accessible for the user's tier.
    var persistedModelId: String {
        if let selectedId = preferences.selectedModelId,
           models.contains(where: { $0.id == selectedId && $0.entityHasAccess }) {
            return selectedId
        }
        return models.first(where: { $0.entityHasAccess })?.id ?? ""
    }

    /// Clears the persisted model selection if it's no longer available or accessible.
    private func clearStaleModelSelectionIfNeeded() {
        guard let selectedId = preferences.selectedModelId else { return }
        if !models.contains(where: { $0.id == selectedId && $0.entityHasAccess }) {
            preferences.selectedModelId = nil
            preferences.selectedModelShortName = nil
        }
    }

    /// Clears the persisted reasoning effort if the current model no longer supports it, or if
    /// the persisted raw value doesn't map to a known `AIChatReasoningEffort` case. Runs after
    /// models are fetched, so a stale value persisted against an older model list doesn't linger
    /// and get attached to future prompts.
    private func clearStaleReasoningEffortIfNeeded() {
        guard let effort = selectedReasoningEffort else {
            // Wipe any unknown raw value we couldn't decode into the enum.
            if preferences.selectedReasoningEffort != nil {
                preferences.selectedReasoningEffort = nil
            }
            return
        }
        if !selectedModelReasoningEfforts.contains(effort) {
            preferences.selectedReasoningEffort = nil
        }
    }

    /// The model ID to include in the prompt. Returns nil if the user has never
    /// explicitly selected a model, so the backend uses its default.
    var currentModelId: String? {
        preferences.selectedModelId
    }

    /// The cached short name of the last selected model, available before models are fetched.
    var cachedModelShortName: String? {
        preferences.selectedModelShortName
    }

    /// Whether the currently selected model supports image upload.
    /// Returns true when models are unavailable (conservative default — image button remains visible).
    var selectedModelSupportsImageUpload: Bool {
        guard !models.isEmpty else { return true }
        return models.first(where: { $0.id == persistedModelId })?.supportsImageUpload ?? true
    }

    /// Whether the currently selected model supports the WebSearch tool.
    /// Returns true when models are unavailable (conservative default — Web Search menu item
    /// remains visible until the model list is known).
    var selectedModelSupportsWebSearch: Bool {
        guard !models.isEmpty else { return true }
        return models.first(where: { $0.id == persistedModelId })?.supportsTool(.webSearch) ?? true
    }

    /// Image formats supported by the currently selected model (e.g. ["png", "jpeg", "webp"]).
    /// Returns a default set when models are unavailable.
    var selectedModelImageFormats: [String] {
        guard !models.isEmpty else { return ["png", "jpeg", "webp"] }
        return models.first(where: { $0.id == persistedModelId })?.supportedImageFormats ?? ["png", "jpeg", "webp"]
    }

    /// Maximum image attachments the duck.ai backend accepts per conversation.
    static let maxImageAttachments: Int = 3
    /// One above the cap — the picker / `addImageAttachmentToActiveTab` allow exactly one over
    /// so the user gets a visible "you've gone over" cue and the error label has something to
    /// anchor against. Submit blocks while in that state.
    static let imageAttachmentsDisplayCap: Int = maxImageAttachments + 1

    /// Maximum file (PDF etc.) attachments the duck.ai backend accepts per conversation. Same
    /// cap as images; the carousel and submit path both gate on this so the user can't
    /// overshoot the server limit.
    static let maxFileAttachments: Int = 3
    static let fileAttachmentsDisplayCap: Int = maxFileAttachments + 1

    /// Whether the currently selected model supports file (PDF etc.) upload.
    /// Returns `false` conservatively when models are unavailable — file upload is opt-in per model
    /// and the file picker should stay hidden until we know the model can accept it.
    var selectedModelSupportsFileUpload: Bool {
        guard !models.isEmpty else { return false }
        return models.first(where: { $0.id == persistedModelId })?.supportsFileUpload ?? false
    }

    /// File types supported by the currently selected model (e.g. ["pdf"]). Empty when files
    /// aren't supported.
    var selectedModelSupportedFileTypes: [String] {
        guard !models.isEmpty else { return [] }
        return models.first(where: { $0.id == persistedModelId })?.supportedFileTypes ?? []
    }

    /// Supported reasoning effort levels for the currently selected model. Unknown raw values
    /// returned by the backend are silently filtered out. This is the server-truth list — used to
    /// validate persisted selections and to gate what we attach to submissions, so a value the
    /// user actually picked still flows through unchanged (e.g. a stored `medium` keeps submitting
    /// `medium` even after the model gains `high` support).
    var selectedModelReasoningEfforts: [AIChatReasoningEffort] {
        models.first(where: { $0.id == persistedModelId })?.supportedReasoningEffort ?? []
    }

    /// Display-only variant of `selectedModelReasoningEfforts` for the picker menu. Picker
    /// buckets collapse to a single menu item when the model advertises both efforts in a
    /// bucket:
    /// - Fast maps to the first supported effort from `none`, then `minimal` — `.minimal` is
    ///   hidden when `.none` is also supported.
    /// - Extended Reasoning maps to the first supported effort from `high`, then `medium` —
    ///   `.medium` is hidden when `.high` is also supported.
    /// Submission and validation paths must use the un-deduped list so a previously-picked value
    /// (e.g. stored `.medium` or `.minimal`) keeps flowing to the backend unchanged.
    var pickerReasoningEfforts: [AIChatReasoningEffort] {
        var efforts = selectedModelReasoningEfforts
        if efforts.contains(.none), efforts.contains(.minimal) {
            efforts.removeAll { $0 == .minimal }
        }
        if efforts.contains(.high), efforts.contains(.medium) {
            efforts.removeAll { $0 == .medium }
        }
        return efforts
    }

    /// The picker effort that visually represents the persisted selection. Returns the stored
    /// effort directly when it's in the picker list; otherwise maps to its bucket equivalent
    /// (`.medium` → `.high`, `.minimal` → `.none`) so the chip label/icon and the menu checkmark
    /// stay in sync with what's actually submitted. Submission still sends the persisted value
    /// unchanged via `effectiveReasoningEffort`.
    var displayedReasoningEffort: AIChatReasoningEffort? {
        guard let stored = selectedReasoningEffort else { return nil }
        let efforts = pickerReasoningEfforts
        if efforts.contains(stored) { return stored }
        switch stored {
        case .medium where efforts.contains(.high): return .high
        case .minimal where efforts.contains(AIChatReasoningEffort.none): return AIChatReasoningEffort.none
        default: return nil
        }
    }

    /// Updates the selected reasoning effort and persists it for future sessions.
    func updateSelectedReasoningEffort(_ effort: AIChatReasoningEffort?) {
        preferences.selectedReasoningEffort = effort?.rawValue
    }

    /// The model ID to use for the current submission.
    /// Returns nil when image generation mode is active — the mode field handles routing.
    var effectiveModelId: String? {
        isImageGenerationMode ? nil : currentModelId
    }

    /// The mode to include in the prompt payload (e.g., "image-generation").
    var effectiveMode: String? {
        isImageGenerationMode ? AIChatNativePrompt.imageGenerationMode : nil
    }

    /// The tool choice to include in the prompt payload (e.g., ["WebSearch"]).
    var effectiveToolChoice: [String]? {
        isWebSearchMode ? [AIChatRAGTool.webSearch.rawValue] : nil
    }

    /// The reasoning effort to include in the prompt payload.
    /// Returns nil when the feature flag is off, image generation mode is active, or the current
    /// model doesn't list the persisted effort as supported — so we never send a stale value that
    /// no longer applies to the active request.
    var effectiveReasoningEffort: AIChatReasoningEffort? {
        guard isReasoningEffortEnabled, !isImageGenerationMode else { return nil }
        guard let effort = selectedReasoningEffort,
              selectedModelReasoningEfforts.contains(effort) else { return nil }
        return effort
    }

    /// Updates the selected model ID and persists it (along with its short name) for future sessions.
    func updateSelectedModel(_ modelId: String) {
        preferences.selectedModelId = modelId
        preferences.selectedModelShortName = models.first(where: { $0.id == modelId })?.shortName
        // The newly selected model may not support the previously persisted reasoning effort.
        // Clearing here keeps stale-effort handling in one place (see `clearStaleReasoningEffortIfNeeded`).
        clearStaleReasoningEffortIfNeeded()
        deactivateWebSearchIfUnsupported()
    }

    /// Clears Web Search mode if the currently selected model doesn't support the WebSearch tool.
    /// Submitting a web-search prompt to an unsupported model fails on the duck.ai page, so the
    /// mode must not remain active across a switch into such a model.
    private func deactivateWebSearchIfUnsupported() {
        guard isWebSearchMode, !selectedModelSupportsWebSearch else { return }
        activeToolMode = nil
    }

    /// Updates the current text being typed by the user
    /// - Parameter text: The new text value
    func updateText(_ text: String) {
        currentText = text
        if !isUpdatingFromSharedState {
            sharedTextState?.updateText(text, markInteraction: true)
        }
    }

    /// Persists the prompt text view's cursor position / selection to the current tab's shared state so it
    /// can be restored when the panel is re-activated (tab switch, refocus).
    func updateSelection(_ range: NSRange) {
        sharedTextState?.updateSelection(range)
    }

    /// The cursor position / selection range currently persisted for this tab, or `nil` if none.
    var currentSelectionRange: NSRange? {
        sharedTextState?.selectionRange
    }

    /// Persists the Duck.ai image attachments for the current tab so they survive tab switches.
    /// Called by the container VC whenever the attachment list changes (add, remove, resize-complete replacement).
    func persistAttachmentsToActiveTab(_ attachments: [AIChatImageAttachment]) {
        sharedTextState?.setAIChatAttachments(attachments)
    }

    /// Persists the Duck.ai tab attachments (Attach Page Content) for the current tab so they survive tab switches.
    /// Called by the container VC whenever the tab attachment list changes (toggle from menu, removal from carousel).
    func persistTabAttachmentsToActiveTab(_ attachments: [AIChatTabAttachment]) {
        sharedTextState?.setAIChatTabAttachments(attachments)
    }

    /// The tab attachments persisted for the current tab, or an empty list if none / no shared state.
    var activeTabAttachments: [AIChatTabAttachment] {
        sharedTextState?.aiChatTabAttachments ?? []
    }

    /// The unified, insertion-ordered attachments list for the current tab — both image
    /// uploads and page-content tabs interleaved in the order the user attached them.
    var activePanelAttachments: [AIChatPanelAttachment] {
        sharedTextState?.aiChatPanelAttachments ?? []
    }

    /// Toggles whether a tab is attached to the current tab's prompt:
    /// adds the attachment if absent, removes it if already present (matched by `id`).
    /// Persists the resulting list to shared state — the unified-attachments publisher then
    /// fires `onActiveTabPanelAttachmentsChanged`, which drives the carousel.
    func toggleTabAttachment(_ attachment: AIChatTabAttachment) {
        var current = activeTabAttachments
        if let index = current.firstIndex(where: { $0.id == attachment.id }) {
            current.remove(at: index)
        } else {
            current.append(attachment)
            prewarmAttachedTab(id: attachment.id)
        }
        persistTabAttachmentsToActiveTab(current)
    }

    /// Wakes a just-attached tab if it's suspended so its content is loaded by the time the user
    /// submits, avoiding a submit-time wait. Fire-and-forget — `extractPageContextsForOmnibarSubmit`
    /// re-resolves and wakes regardless, so this is purely a latency optimization.
    private func prewarmAttachedTab(id: String) {
        guard let resolved = AIChatTabPickerSource.materializeAttachableTab(withId: id, forOrigin: tabCollectionViewModel, in: Application.appDelegate.windowControllersManager),
              resolved.wasMaterialized else {
            return
        }
        resolved.tab.reload()
    }

    /// Removes a tab attachment from the active tab's prompt, identified by `id`. No-op if not
    /// currently attached.
    func removeTabAttachmentFromActiveTab(id: String) {
        var current = activeTabAttachments
        guard current.contains(where: { $0.id == id }) else { return }
        current.removeAll { $0.id == id }
        persistTabAttachmentsToActiveTab(current)
    }

    /// Image attachments persisted on the current tab. Empty when no tab is active.
    var activeImageAttachments: [AIChatImageAttachment] {
        sharedTextState?.aiChatAttachments ?? []
    }

    /// At or above the per-conversation image cap.
    var isActiveTabImageAttachmentsFull: Bool {
        activeImageAttachments.count >= Self.maxImageAttachments
    }

    /// Strictly over the per-conversation image cap (one over, by `imageAttachmentsDisplayCap` design).
    var hasExcessActiveTabImageAttachments: Bool {
        activeImageAttachments.count > Self.maxImageAttachments
    }

    /// Adds an image attachment to the active tab. No-op if at displayCap or if an attachment
    /// with the same id is already present.
    func addImageAttachmentToActiveTab(_ attachment: AIChatImageAttachment) {
        var current = activeImageAttachments
        guard current.count < Self.imageAttachmentsDisplayCap else { return }
        guard !current.contains(where: { $0.id == attachment.id }) else { return }
        current.append(attachment)
        sharedTextState?.setAIChatAttachments(current)
    }

    /// Removes an image attachment from the active tab, identified by `id`. No-op if not
    /// currently attached.
    func removeImageAttachmentFromActiveTab(id: UUID) {
        guard let sharedTextState else { return }
        var current = sharedTextState.aiChatAttachments
        guard current.contains(where: { $0.id == id }) else { return }
        current.removeAll { $0.id == id }
        sharedTextState.setAIChatAttachments(current)
    }

    /// Replaces an image attachment in place — used when the resize task completes and swaps
    /// the placeholder for the resized `NSImage`. Just updates the data list; the carousel's
    /// `setAttachments` does the in-place thumbnail update by id.
    func replaceImageAttachmentInActiveTab(id: UUID, with newAttachment: AIChatImageAttachment) {
        guard let sharedTextState else { return }
        var current = sharedTextState.aiChatAttachments
        guard let index = current.firstIndex(where: { $0.id == id }) else { return }
        current[index] = newAttachment
        sharedTextState.setAIChatAttachments(current)
    }

    /// File attachments persisted on the current tab (PDFs etc.). Empty when no tab is active.
    var activeFileAttachments: [AIChatFileAttachment] {
        sharedTextState?.aiChatFileAttachments ?? []
    }

    /// Persists the supplied file-attachment list onto the active tab's shared state. The
    /// publisher fires; the carousel re-renders.
    func persistFileAttachmentsToActiveTab(_ attachments: [AIChatFileAttachment]) {
        sharedTextState?.setAIChatFileAttachments(attachments)
    }

    /// Adds a file attachment to the active tab. No-op if at displayCap or if an attachment
    /// with the same id is already present. Mirrors `addImageAttachmentToActiveTab`'s
    /// defense-in-depth posture — the picker is the only caller today and gates on the cap
    /// before this runs, but a second guard here keeps every future caller (drag-and-drop,
    /// paste, restore paths, tests) safe from overshooting `fileAttachmentsDisplayCap`.
    func addFileAttachmentToActiveTab(_ attachment: AIChatFileAttachment) {
        var current = activeFileAttachments
        guard current.count < Self.fileAttachmentsDisplayCap else { return }
        guard !current.contains(where: { $0.id == attachment.id }) else { return }
        current.append(attachment)
        persistFileAttachmentsToActiveTab(current)
    }

    /// Removes a file attachment from the active tab. No-op if not currently attached.
    func removeFileAttachmentFromActiveTab(id: UUID) {
        var current = activeFileAttachments
        guard current.contains(where: { $0.id == id }) else { return }
        current.removeAll { $0.id == id }
        persistFileAttachmentsToActiveTab(current)
    }

    /// UUID of the tab the omnibar is currently overlaid on, or `nil` when no tab is selected.
    /// Surfaced for tab pickers (both the "Attach Page Content" menu and the `@`-mention
    /// picker) so they can pin the current tab at the top and render its row with a
    /// "(Current Tab)" trailing badge.
    var currentTabUUID: String? {
        tabCollectionViewModel.selectedTabViewModel?.tab.uuid
    }

    /// Returns the open browser tabs (pinned + regular) as candidate attachments, with native
    /// `NSImage` favicons resolved from the favicon manager. Used by the omnibar attach menu and
    /// the `@`-mention picker to populate their tab lists.
    ///
    /// - Note: tabs are sourced across windows via the shared `AIChatTabPickerSource`, using this
    /// controller's `tabCollectionViewModel` as the origin: a regular window surfaces tabs from all
    /// regular windows, while a Fire Window surfaces only its own tabs (Fire Windows are never
    /// pulled into a regular picker, and vice versa). Non-URL tabs and URLs ruled out by
    /// `AIChatTabMetadata.shouldExcludeFromTabPicker(_:)` are already filtered by the source.
    /// Internal testers who set a custom AI Chat URL via Debug → AI Chat → Set custom URL also get
    /// tabs at that host filtered out here — the shared helper only knows the hardcoded `duck.ai`
    /// host, so the omnibar checks the debug override too.
    ///
    /// The current tab (if it survives the filters) is hoisted to the front of the returned list
    /// so menus that pin "Current Tab" at the top get the right ordering for free.
    func openTabsForOmnibarPicker() -> [AIChatTabAttachment] {
        let faviconManager = NSApp.delegateTyped.faviconManager
        // Resolve the custom-URL host once per pick — `keyedStoring` reads from UserDefaults
        // every access, so caching avoids hitting it per-tab.
        let debugURLSettings: any KeyedStoring<AIChatDebugURLSettings> = UserDefaults.standard.keyedStoring()
        let customAIChatURLHost = debugURLSettings.customURLHostname
        let candidates = AIChatTabPickerSource.attachableTabs(forOrigin: tabCollectionViewModel, in: Application.appDelegate.windowControllersManager).compactMap { tab -> AIChatTabAttachment? in
            guard case .url(let url, _, _) = tab.content else { return nil }
            if let customHost = customAIChatURLHost, !customHost.isEmpty, url.host == customHost {
                return nil
            }
            let title = tab.title ?? url.host ?? ""
            let favicon = faviconManager.getCachedFavicon(for: url, sizeCategory: .small)?.image
            return AIChatTabAttachment(id: tab.uuid, title: title, url: url, favicon: favicon)
        }
        // Move the current tab to the front so the picker pins it on top.
        guard let currentTabUUID,
              let currentIndex = candidates.firstIndex(where: { $0.id == currentTabUUID }),
              currentIndex != 0 else {
            return candidates
        }
        var reordered = candidates
        let current = reordered.remove(at: currentIndex)
        reordered.insert(current, at: 0)
        return reordered
    }

    func cleanup() {
        isCleaningUp = true
        defer { isCleaningUp = false }
        currentText = ""
        activeToolMode = nil
        hasImageAttachments = false
        hasBeenActivated = false
        suggestionsViewModel.clearAllChats()
        currentFetchTask?.cancel()
        currentFetchTask = nil
        modelsFetchTask?.cancel()
        modelsFetchTask = nil
        suggestionsReader?.tearDown()
    }

    // MARK: - Suggestion Navigation

    /// Moves selection to the next suggestion.
    /// - Returns: `true` if a suggestion was selected, `false` if navigation should continue to other UI elements.
    func selectNextSuggestion() -> Bool {
        guard isSuggestionsEnabled else { return false }
        return suggestionsViewModel.selectNext()
    }

    /// Moves selection to the previous suggestion.
    /// - Returns: `true` if selection changed, `false` if at the beginning (should return focus to text field).
    func selectPreviousSuggestion() -> Bool {
        guard isSuggestionsEnabled else { return false }
        return suggestionsViewModel.selectPrevious()
    }

    /// Submits the currently selected suggestion, if any.
    /// - Returns: `true` if a suggestion was submitted, `false` if no suggestion was selected.
    func submitSelectedSuggestion() -> Bool {
        guard isSuggestionsEnabled else { return false }

        if suggestionsViewModel.isViewAllChatsSelected {
            viewAllChats()
            currentText = ""
            return true
        }

        guard let selectedSuggestion = suggestionsViewModel.selectedSuggestion else {
            return false
        }
        delegate?.aiChatOmnibarController(self, didSelectSuggestion: selectedSuggestion)
        currentText = ""
        return true
    }

    /// Clears the current suggestion selection.
    func clearSuggestionSelection() {
        suggestionsViewModel.clearSelection()
    }

    /// Whether a suggestion is currently selected.
    var hasSuggestionSelected: Bool {
        suggestionsViewModel.selectedIndex != nil
    }

    // MARK: - Private Methods

    private func subscribeToSelectedTabViewModel() {
        tabCollectionViewModel.$selectedTabViewModel
            .sink { [weak self] tabViewModel in
                guard let self else { return }
                let sharedState = tabViewModel?.addressBarSharedTextState
                /// Cache the incoming tab's shared state now so synchronous delegate chains driven off the same
                /// tab-switch emission (e.g. AddressBarVC → MainVC → onOmnibarActivated) read the new state
                /// rather than the stale outgoing tab via `selectedTabViewModel`'s not-yet-updated storage.
                self.sharedTextState = sharedState
                self.subscribeToSharedTextState(sharedState)

                /// Restore Duck.ai per-tab state when switching. The `isUpdatingFromSharedState` guard prevents the
                /// `$activeToolMode` sink from writing the restored value back to the (now-incoming) shared state.
                self.isUpdatingFromSharedState = true
                if let text = sharedState?.text {
                    self.currentText = text
                }
                self.activeToolMode = sharedState?.aiChatToolMode
                self.isUpdatingFromSharedState = false

                // Re-subscribe to the new tab's unified attachments publisher. `@Published`
                // emits the current value on subscription, so this also fires the initial
                // "restore" with the incoming tab's saved list — no separate restore call needed.
                self.panelAttachmentsCancellable = sharedState?.$aiChatPanelAttachments
                    .sink { [weak self] panelAttachments in
                        self?.onActiveTabPanelAttachmentsChanged?(panelAttachments)
                    }
                if sharedState == nil {
                    // No active tab → empty carousel. (`@Published` on a nil source can't deliver
                    // the empty initial value for us, so synthesize it.)
                    self.onActiveTabPanelAttachmentsChanged?([])
                }
            }
            .store(in: &cancellables)
    }

    private func subscribeToSharedTextState(_ sharedTextState: AddressBarSharedTextState?) {
        sharedTextStateCancellable?.cancel()
        sharedTextStateCancellable = nil

        guard let sharedTextState else { return }

        sharedTextStateCancellable = sharedTextState.$text
            .sink { [weak self] newText in
                guard let self = self else { return }
                if self.currentText != newText && sharedTextState.hasUserInteractedWithText {
                    self.isUpdatingFromSharedState = true
                    self.currentText = newText
                    self.isUpdatingFromSharedState = false
                }
            }
    }

    func viewAllChats() {
        PixelKit.fire(AIChatPixel.aiChatViewAllChatsClicked, frequency: .dailyAndCount, includeAppVersionParameter: true)
        aiChatTabOpener.openNewAIChat(in: .newTab(selected: true))
    }

    func submit() {
        guard !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        // Block submission if too many images are attached and would be sent
        let canSendImages = isImageGenerationMode || selectedModelSupportsImageUpload
        if canSendImages && activeImageAttachments.count > Self.maxImageAttachments {
            return
        }

        // Block submission if too many files are attached. The picker caps picks at one over the
        // limit (`+1`) so the user gets a visible "you've gone over" cue; if they actually try to
        // submit while in that state, hold the submit until they remove the excess.
        if selectedModelSupportsFileUpload && activeFileAttachments.count > Self.maxFileAttachments {
            return
        }

        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let navigableURL = classifyAsNavigableURL(trimmedText) {
            PixelKit.fire(AIChatPixel.aiChatAddressBarAIChatSubmitURL, frequency: .dailyAndCount, includeAppVersionParameter: true)
            currentText = ""
            delegate?.aiChatOmnibarController(self, didRequestNavigationToURL: navigableURL)
            return
        }

        PixelKit.fire(AIChatPixel.aiChatAddressBarAIChatSubmitPrompt, frequency: .dailyAndCount, includeAppVersionParameter: true)

        if isImageGenerationMode {
            PixelKit.fire(AIChatPixel.aiChatAddressBarImageGenerationSubmitted, frequency: .dailyAndCount, includeAppVersionParameter: true)
        } else if isWebSearchMode {
            PixelKit.fire(AIChatPixel.aiChatAddressBarWebSearchSubmitted, frequency: .dailyAndCount, includeAppVersionParameter: true)
        }

        // Snapshot everything that could change between now and when the async submit Task
        // resumes. `await waitForAttachmentsReady?()` can take seconds for large images, and
        // `sharedTextState` is rebound on tab change — without the snapshot, every post-await
        // read would reflect whichever tab is active when the await resumes, not the tab the
        // user pressed submit on. That meant attachments from tab B could ship in the payload
        // for the prompt typed on tab A, and the `tabId`-stripping discriminator would be
        // computed against the wrong active tab.
        //
        // Snapshotting before the Task closure is the cheap fix: each capture is a value-type
        // copy (or a closure capture of the model state at submit time), so the task body
        // operates on a frozen view of "what the user actually clicked submit on".
        //
        // We intentionally do NOT re-check `isOmnibarTabPickerEnabled` inside the task. If the
        // privacy config remotely disables the omnibar tab picker between submit-click and
        // task resume, the in-flight `pageContext` payload still ships — the user expressed
        // clear intent before the flag flipped, and silently dropping attachments mid-submit
        // would be worse UX than the corner-case rollback. Surface gating still kicks in the
        // *next* time the user opens the omnibar.
        let modelId = effectiveModelId
        let mode = effectiveMode
        let toolChoice = effectiveToolChoice
        let reasoningEffort = effectiveReasoningEffort
        let snapshotImageAttachments: [AIChatImageAttachment] = canSendImages ? activeImageAttachments : []
        let snapshotTabAttachments: [AIChatTabAttachment] = activeTabAttachments
        let snapshotFileAttachments: [AIChatFileAttachment] = selectedModelSupportsFileUpload ? activeFileAttachments : []
        let snapshotActiveTabUUID: String? = tabCollectionViewModel.selectedTabViewModel?.tab.uuid
        // Capture the *per-tab* shared text state reference itself, not just a copy of its
        // current attachments. The resize task writes the finalized image back into the same
        // tab's `aiChatAttachments` storage via this object; `self.sharedTextState` would
        // otherwise rebind to a different tab if the user tab-switches during the await, and
        // the post-resize lookup below would read from the wrong tab — losing the resized
        // bytes for the submission the user actually triggered.
        let snapshotSharedTextState = sharedTextState
        let supportedImageFormats = selectedModelImageFormats

        Task { @MainActor in
            // Wait for any pending image resizes to complete. NOTE: the read of the *image
            // bytes* is deferred past this await because resize-replacement updates the same
            // `AIChatImageAttachment.id` in place — the snapshot captured the identity, the
            // resize finalizes the pixels.
            await waitForAttachmentsReady?()

            let postResizeImages: [AIChatImageAttachment] = snapshotImageAttachments.compactMap { attachment in
                // Re-read by id from the *submit-time* tab's shared state — the resize task
                // swapped the image instance on the same id, but possibly while the user
                // tab-switched away. Reading via `snapshotSharedTextState` keeps us pinned
                // to the tab the user actually pressed submit on. If the attachment has been
                // removed in the meantime (shouldn't normally happen, but defend), fall back
                // to the pre-resize snapshot.
                snapshotSharedTextState?.aiChatAttachments.first(where: { $0.id == attachment.id }) ?? attachment
            }
            let images = Self.nativePromptImages(from: postResizeImages, supportedFormats: supportedImageFormats)

            if !postResizeImages.isEmpty {
                PixelKit.fire(AIChatPixel.aiChatAddressBarSubmitWithImage(imageCount: postResizeImages.count), frequency: .dailyAndCount, includeAppVersionParameter: true)
            }

            // Extract each picked tab's current `AIChatPageContextData` in parallel — same
            // per-tab extractor the sidebar's JS-bridge (`getAIChatTabContent`) uses, so the
            // page-content + favicon enrichment is byte-identical across both flows. Each
            // entry carries `tabId` so the duck.ai web app sees the discriminator (presence =
            // tab-picker context), except for the entry whose tab UUID matches the snapshot's
            // active tab: that one becomes the no-`tabId` form, i.e. "the page you're chatting
            // about", per the tech design.
            //
            // When there are no attached tabs we skip the `await` entirely — keeping the
            // submit Task linear in the common case.
            let pageContextPayload: AIChatPageContextPayload?
            if snapshotTabAttachments.isEmpty {
                pageContextPayload = nil
            } else {
                pageContextPayload = await self.extractPageContextsForOmnibarSubmit(
                    tabAttachments: snapshotTabAttachments,
                    activeTabUUID: snapshotActiveTabUUID
                )
                PixelKit.fire(
                    AIChatPixel.aiChatAddressBarSubmitWithTabs(tabCount: snapshotTabAttachments.count),
                    frequency: .dailyAndCount,
                    includeAppVersionParameter: true
                )
            }

            // Encode each `AIChatFileAttachment.data` as base64 for the JSON bridge.
            let files: [AIChatNativePrompt.NativePromptFile]? = snapshotFileAttachments.isEmpty ? nil : snapshotFileAttachments.map { attachment in
                AIChatNativePrompt.NativePromptFile(
                    data: attachment.data.base64EncodedString(),
                    fileName: attachment.fileName,
                    mimeType: attachment.mimeType
                )
            }
            if !snapshotFileAttachments.isEmpty {
                PixelKit.fire(
                    AIChatPixel.aiChatAddressBarSubmitWithFiles(fileCount: snapshotFileAttachments.count),
                    frequency: .dailyAndCount,
                    includeAppVersionParameter: true
                )
            }

            aiChatTabOpener.openAIChatTab(
                with: .query(trimmedText, shouldAutoSubmit: true),
                behavior: .currentTab
            )
            // Re-set prompt after tab opener to include images, files, tab attachments, model
            // selection, and mode (tab opener overwrites with a plain query).
            let prompt = AIChatNativePrompt.queryPrompt(
                trimmedText,
                autoSubmit: true,
                toolChoice: toolChoice,
                images: images,
                files: files,
                modelId: modelId,
                pageContext: pageContextPayload,
                mode: mode,
                reasoningEffort: reasoningEffort
            )
            promptHandler.setData(prompt)

            self.activeToolMode = nil
            // Cancel any in-flight image-resize tasks; the container VC owns those.
            onAttachmentsClearRequested?()
            // All three attachment kinds live on shared state — clear each so the
            // `$aiChatPanelAttachments` publisher drives the carousel back to empty.
            self.persistAttachmentsToActiveTab([])
            self.persistTabAttachmentsToActiveTab([])
            self.persistFileAttachmentsToActiveTab([])
            delegate?.aiChatOmnibarControllerDidSubmit(self)
        }

        currentText = ""
    }

    /// Eagerly extracts the page context for each omnibar-attached tab, returning a
    /// `AIChatPageContextPayload?` ready to attach to the prompt's top-level `pageContext`
    /// field. Empty list → `nil` (the field is omitted on the wire). Otherwise a
    /// `.multiple([...])` array preserving the carousel's insertion order, where each entry
    /// has `tabId` stamped EXCEPT the one whose tab matches the active tab (that one is
    /// stripped to the no-`tabId` form, marking it as "the page you're chatting about" per
    /// the tech design discriminator).
    ///
    /// Per-tab extraction runs in parallel (`withTaskGroup`). Each task resolves the tab by id via
    /// the shared cross-window source (scoped to this controller's window as origin) and **wakes a
    /// suspended tab** if needed so its content is extracted rather than dropped. Tabs that genuinely
    /// can't be loaded return `nil` and are dropped from the payload — same as the JS-bridge.
    @MainActor
    private func extractPageContextsForOmnibarSubmit(
        tabAttachments: [AIChatTabAttachment],
        activeTabUUID: String?
    ) async -> AIChatPageContextPayload? {
        guard !tabAttachments.isEmpty else { return nil }

        let origin = tabCollectionViewModel
        let windowControllersManager = Application.appDelegate.windowControllersManager
        let extracted: [(String, AIChatPageContextData?)] = await withTaskGroup(of: (String, AIChatPageContextData?).self) { group in
            for attachment in tabAttachments {
                let tabId: String = attachment.id
                group.addTask { @MainActor in
                    let ctx = await AIChatUserScriptHandler.extractPageContext(forTabId: tabId, origin: origin, in: windowControllersManager)
                    return (tabId, ctx)
                }
            }
            var results: [(String, AIChatPageContextData?)] = []
            for await pair in group {
                results.append(pair)
            }
            return results
        }

        // Stamp `tabId` on each successful extraction (or strip it if the entry matches the
        // active tab), then re-order to match the carousel's insertion order.
        var byId: [String: AIChatPageContextData] = [:]
        for (tabId, maybeContext) in extracted {
            guard let ctx = maybeContext else { continue }
            let stampedTabId: String? = (tabId == activeTabUUID) ? nil : tabId
            byId[tabId] = ctx.withTabId(stampedTabId)
        }
        let ordered: [AIChatPageContextData] = tabAttachments.compactMap { byId[$0.id] }
        return ordered.isEmpty ? nil : .multiple(ordered)
    }

    /// Converts image attachments to base64-encoded `NativePromptImage` values for the JS bridge.
    /// Encodes each image in a format the model supports. Prefers the source format when supported;
    /// otherwise falls back to the first supported format (typically PNG).
    private static func nativePromptImages(from attachments: [AIChatImageAttachment], supportedFormats: [String]) -> [AIChatNativePrompt.NativePromptImage]? {
        guard !attachments.isEmpty else { return nil }
        let lowercasedFormats = Set(supportedFormats.map { $0.lowercased() })

        let images = attachments.compactMap { attachment -> AIChatNativePrompt.NativePromptImage? in
            guard let tiffData = attachment.image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData) else {
                return nil
            }

            let ext = (attachment.fileName as NSString).pathExtension.lowercased()
            let resolvedFormat = resolveImageFormat(sourceExtension: ext, supportedFormats: lowercasedFormats)

            guard let data = bitmap.representation(using: resolvedFormat.fileType, properties: [:]) else {
                return nil
            }

            return AIChatNativePrompt.NativePromptImage(data: data.base64EncodedString(), format: resolvedFormat.formatString)
        }
        return images.isEmpty ? nil : images
    }

    private static func resolveImageFormat(sourceExtension: String, supportedFormats: Set<String>) -> (fileType: NSBitmapImageRep.FileType, formatString: String) {
        // Normalize extension aliases (e.g. "jpg" → "jpeg")
        let sourceFormat = canonicalFormatName(for: sourceExtension)

        // Use source format if the model supports it and we can encode it
        if supportedFormats.contains(sourceFormat), let fileType = bitmapFileType(for: sourceFormat) {
            return (fileType, sourceFormat)
        }

        // Fall back to the first supported format we can encode, in preference order
        let preferred = ["png", "jpeg", "gif", "bmp", "tiff"]
        for format in preferred where supportedFormats.contains(format) {
            if let fileType = bitmapFileType(for: format) {
                return (fileType, format)
            }
        }

        // Ultimate fallback
        return (.png, "png")
    }

    /// Normalizes file extensions to canonical format names used by the API.
    private static func canonicalFormatName(for extension: String) -> String {
        switch `extension` {
        case "jpg": return "jpeg"
        case "tif": return "tiff"
        default: return `extension`
        }
    }

    /// Maps a format name to NSBitmapImageRep.FileType, returning nil for formats
    /// that NSBitmapImageRep cannot encode (e.g. WebP).
    private static func bitmapFileType(for format: String) -> NSBitmapImageRep.FileType? {
        switch format {
        case "png": return .png
        case "jpeg": return .jpeg
        case "gif": return .gif
        case "bmp": return .bmp
        case "tiff": return .tiff
        default: return nil
        }
    }

    /// Checks if the input text is a navigable URL (not a search query).
    /// Returns the URL if it should be navigated to, nil if it should be treated as an AI chat query.
    /// Pre-filter: a URL cannot contain internal whitespace, so any multi-word prompt that happens to start
    /// with a URL (e.g. "https://example.com\nexplain this") is treated as a chat query. Without this the
    /// classifier (after URL construction strips the whitespace) would navigate to the concatenated string.
    private func classifyAsNavigableURL(_ text: String) -> URL? {
        guard text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        do {
            switch try Classifier.classify(input: text) {
            case .navigate(let url):
                return url
            case .search:
                return nil
            }
        } catch {
            return nil
        }
    }
}
