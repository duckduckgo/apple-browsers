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

/// Controller that manages the state and actions for the AI Chat omnibar.
/// This controller is shared between AIChatOmnibarContainerViewController and AIChatOmnibarTextContainerViewController
/// to coordinate text input and submission.
@MainActor
final class AIChatOmnibarController {
    @Published private(set) var currentText: String = ""
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

    /// Gets the shared text state from the current tab's view model
    private var sharedTextState: AddressBarSharedTextState? {
        tabCollectionViewModel.selectedTabViewModel?.addressBarSharedTextState
    }

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

    // MARK: - Suggestions Fetching

    /// Called when the duck.ai omnibar becomes visible.
    /// Triggers a models fetch (on every activation) and suggestions fetch.
    func onOmnibarActivated() {
        hasBeenActivated = true

        fetchModels()

        // If feature is disabled, clear any existing suggestions and don't fetch
        if !isSuggestionsEnabled {
            suggestionsViewModel.clearAllChats()
            return
        }

        fetchSuggestionsIfNeeded(query: currentText)
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

            let suggestions = await reader.fetchSuggestions(query: query.isEmpty ? nil : query)

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            self.suggestionsViewModel.setChats(pinned: suggestions.pinned, recent: suggestions.recent)
        }
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

    /// Image formats supported by the currently selected model (e.g. ["png", "jpeg", "webp"]).
    /// Returns a default set when models are unavailable.
    var selectedModelImageFormats: [String] {
        guard !models.isEmpty else { return ["png", "jpeg", "webp"] }
        return models.first(where: { $0.id == persistedModelId })?.supportedImageFormats ?? ["png", "jpeg", "webp"]
    }

    /// Updates the selected model ID and persists it (along with its short name) for future sessions.
    func updateSelectedModel(_ modelId: String) {
        preferences.selectedModelId = modelId
        preferences.selectedModelShortName = models.first(where: { $0.id == modelId })?.shortName
    }

    /// Updates the current text being typed by the user
    /// - Parameter text: The new text value
    func updateText(_ text: String) {
        currentText = text
        if !isUpdatingFromSharedState {
            sharedTextState?.updateText(text, markInteraction: true)
        }
    }

    func cleanup() {
        currentText = ""
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
        guard isSuggestionsEnabled,
              let selectedSuggestion = suggestionsViewModel.selectedSuggestion else {
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
                self.subscribeToSharedTextState(tabViewModel?.addressBarSharedTextState)

                /// Restore text on duck.ai panel when changing tabs
                if let text = tabViewModel?.addressBarSharedTextState.text {
                    self.currentText = text
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

    func submit() {
        guard !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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

        Task { @MainActor in
            // Wait for any pending image resizes to complete
            await waitForAttachmentsReady?()

            // Get attachments after resizes are complete
            let attachments = attachmentsProvider?() ?? []
            let images = Self.nativePromptImages(from: attachments, supportedFormats: self.selectedModelImageFormats)

            if !attachments.isEmpty {
                PixelKit.fire(AIChatPixel.aiChatAddressBarSubmitWithImage(imageCount: attachments.count), frequency: .dailyAndCount, includeAppVersionParameter: true)
            }

            aiChatTabOpener.openAIChatTab(
                with: .query(trimmedText, shouldAutoSubmit: true),
                behavior: .currentTab
            )
            // Re-set prompt after tab opener to include images and model selection (tab opener overwrites with a plain query)
            let modelId = self.currentModelId
            let prompt = AIChatNativePrompt.queryPrompt(trimmedText, autoSubmit: true, images: images, modelId: modelId)
            promptHandler.setData(prompt)

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
    private func classifyAsNavigableURL(_ text: String) -> URL? {
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
