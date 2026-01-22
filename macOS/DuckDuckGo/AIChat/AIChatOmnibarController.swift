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
import PixelKit
import PrivacyConfig
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
    private var cancellables = Set<AnyCancellable>()
    private var sharedTextStateCancellable: AnyCancellable?
    private var isUpdatingFromSharedState = false
    private var currentFetchTask: Task<Void, Never>?
    private var hasBeenActivated = false

    /// View model for managing chat suggestions. Always initialized, but only populated when feature flag is enabled.
    let suggestionsViewModel = AIChatSuggestionsViewModel()

    /// Whether the suggestions feature is enabled.
    /// Requires both the feature flag and the autocomplete setting to be on.
    var isSuggestionsEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatSuggestions) && searchPreferencesPersistor.showAutocompleteSuggestions
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
        suggestionsReader: AIChatSuggestionsReading? = nil
    ) {
        self.aiChatTabOpener = aiChatTabOpener
        self.tabCollectionViewModel = tabCollectionViewModel
        self.promptHandler = promptHandler
        self.featureFlagger = featureFlagger
        self.searchPreferencesPersistor = searchPreferencesPersistor
        self.suggestionsReader = suggestionsReader

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

    /// Called when the duck.ai omnibar becomes visible. Triggers initial suggestions fetch.
    func onOmnibarActivated() {
        hasBeenActivated = true

        // If feature is disabled, clear any existing suggestions and don't fetch
        if !isSuggestionsEnabled {
            suggestionsViewModel.clearAllChats()
            return
        }

        fetchSuggestionsIfNeeded(query: currentText)
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

        let nativePrompt = AIChatNativePrompt.queryPrompt(trimmedText, autoSubmit: true)
        promptHandler.setData(nativePrompt)

        Task { @MainActor in
            aiChatTabOpener.openAIChatTab(
                with: .query(trimmedText, shouldAutoSubmit: true),
                behavior: .currentTab
            )
        }

        currentText = ""
        delegate?.aiChatOmnibarControllerDidSubmit(self)
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
