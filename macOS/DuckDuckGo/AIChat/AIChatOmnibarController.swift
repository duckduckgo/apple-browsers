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

    /// Provides the current image attachments from the container VC.
    var attachmentsProvider: (() -> [AIChatImageAttachment])?

    /// Called after a successful submit so the container VC can clear its attachment UI.
    var onAttachmentsClearRequested: (() -> Void)?

    /// Called on tab switch so the container VC can reinstall the attachments persisted for the incoming tab.
    /// Owned by the container VC (where the attachments view and its resize tasks live); the controller just
    /// delivers the list pulled from the incoming tab's `AddressBarSharedTextState`.
    var onActiveTabAttachmentsRestoreRequested: (([AIChatImageAttachment]) -> Void)?

    /// Waits for all attachment resizing to complete before proceeding.
    var waitForAttachmentsReady: (() async -> Void)?

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
        aiChatTabOpener.openVoiceSession(
            inSourceCollection: tabCollectionViewModel,
            behavior: .newTab(selected: true)
        )
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
            onActiveTabAttachmentsRestoreRequested?(sharedTextState.aiChatAttachments)
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
                let remoteModels = try await modelsService.fetchModels()
                guard !Task.isCancelled else { return }
                let userTier = try await self.resolveUserTier()
                guard !Task.isCancelled else { return }
                self.hasActiveSubscription = userTier != .free
                self.models = remoteModels.map { AIChatModel(remoteModel: $0, userTier: userTier) }
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
            let subscription = try await subscriptionManager.getSubscription(cachePolicy: .cacheFirst)
            guard subscription.isActive else { return .free }
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
        case .minimal where efforts.contains(.none): return .none
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

                /// Tell the container VC to reinstall this tab's attachments. The container owns the actual views
                /// and resize tasks, so restoration has to happen there; shared state is just the storage.
                self.onActiveTabAttachmentsRestoreRequested?(sharedState?.aiChatAttachments ?? [])
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
        if canSendImages, let attachments = attachmentsProvider?(), attachments.count > AIChatImageAttachmentsContainerView.maxAttachments {
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

        // Capture mode/model/toolChoice/reasoning before async work — cleanup() may reset state
        let modelId = effectiveModelId
        let mode = effectiveMode
        let toolChoice = effectiveToolChoice
        let reasoningEffort = effectiveReasoningEffort

        Task { @MainActor in
            // Wait for any pending image resizes to complete
            await waitForAttachmentsReady?()

            // Get attachments after resizes are complete — only include if model supports images or in image gen mode
            let attachments = canSendImages ? (attachmentsProvider?() ?? []) : []
            let images = Self.nativePromptImages(from: attachments, supportedFormats: self.selectedModelImageFormats)

            if !attachments.isEmpty {
                PixelKit.fire(AIChatPixel.aiChatAddressBarSubmitWithImage(imageCount: attachments.count), frequency: .dailyAndCount, includeAppVersionParameter: true)
            }

            aiChatTabOpener.openAIChatTab(
                with: .query(trimmedText, shouldAutoSubmit: true),
                behavior: .currentTab
            )
            // Re-set prompt after tab opener to include images, model selection, and mode (tab opener overwrites with a plain query)
            let prompt = AIChatNativePrompt.queryPrompt(trimmedText, autoSubmit: true, toolChoice: toolChoice, images: images, modelId: modelId, mode: mode, reasoningEffort: reasoningEffort)
            promptHandler.setData(prompt)

            self.activeToolMode = nil
            onAttachmentsClearRequested?()
            delegate?.aiChatOmnibarControllerDidSubmit(self)
        }

        currentText = ""
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
