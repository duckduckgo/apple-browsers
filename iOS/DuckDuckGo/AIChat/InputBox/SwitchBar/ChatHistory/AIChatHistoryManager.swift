//
//  AIChatHistoryManager.swift
//  DuckDuckGo
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

import AIChat
import Combine

/// Manages the AI Chat history list installation and interaction
@MainActor
final class AIChatHistoryManager {

    // MARK: - Constants

    private enum Constants {
        static let debounceMilliseconds = 150
    }

    // MARK: - Properties

    var onFetchCompleted: (@MainActor (String, Bool) -> Void)?

    var hasSuggestions: Bool {
        viewModel.hasSuggestions
    }

    var hasSuggestionsPublisher: AnyPublisher<Bool, Never> {
        viewModel.$filteredSuggestions
            .map { !$0.isEmpty }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    func hasSettled(forQuery query: String) -> Bool {
        lastCompletedFetchQuery.map { $0 == query } ?? false
    }

    private let suggestionsReader: AIChatSuggestionsReading
    private let aiChatDeleter: AIChatDeleting
    private let viewModel: AIChatSuggestionsViewModel
    private let isFireTab: Bool
    private(set) var hasCompletedInitialFetch = false
    /// Query string of the most recently completed (non-cancelled) fetch. Callers compare
    /// this against the current text to detect "fetcher hasn't caught up yet" and treat
    /// derived state (e.g. `hasSuggestions`) as still-pending.
    private(set) var lastCompletedFetchQuery: String?
    private var cancellables = Set<AnyCancellable>()
    private var currentFetchTask: Task<Void, Never>?

    // MARK: - Initialization

    init(suggestionsReader: AIChatSuggestionsReading,
         aiChatDeleter: AIChatDeleting,
         viewModel: AIChatSuggestionsViewModel,
         isFireTab: Bool) {
        self.suggestionsReader = suggestionsReader
        self.aiChatDeleter = aiChatDeleter
        self.viewModel = viewModel
        self.isFireTab = isFireTab
    }

    // MARK: - Public Methods

    /// Subscribes to text changes from a publisher with debounce and fetches filtered suggestions
    /// - Parameter textPublisher: A publisher that emits text changes
    func subscribeToTextChanges<P: Publisher>(_ textPublisher: P) where P.Output == String, P.Failure == Never {
        textPublisher
            .debounce(for: .milliseconds(Constants.debounceMilliseconds), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self else { return }
                self.fetchSuggestionsIfNeeded(query: text)
            }
            .store(in: &cancellables)
    }

    /// Removes an AIChatSuggestion and refreshes the Suggestions List
    ///
    func deleteChatSuggestion(suggestion: AIChatSuggestion) {
        viewModel.removeSuggestion(suggestion)

        Task { @MainActor in
            await self.deleteChatSuggestionFromHistory(suggestion: suggestion)
            self.refreshSuggestions()
        }
    }

    private func deleteChatSuggestionFromHistory(suggestion: AIChatSuggestion) async {
        let result = await aiChatDeleter.deleteChat(chatID: suggestion.chatId, isFireMode: isFireTab)
        if case .failure = result {
            viewModel.cancelPendingRemoval(suggestion)
            return
        }

        aiChatDeleter.scheduleSync()
    }

    private func refreshSuggestions() {
        let query = lastCompletedFetchQuery ?? ""
        fetchSuggestionsIfNeeded(query: query)
    }

    func refreshSuggestions(query: String) {
        fetchSuggestionsIfNeeded(query: query)
    }

    /// Fetches suggestions from the API with cancellation support
    /// - Parameter query: The search query to filter results
    private func fetchSuggestionsIfNeeded(query: String) {
        currentFetchTask?.cancel()

        let reader = suggestionsReader
        let viewModel = viewModel
        let effectiveQuery = query.isEmpty ? nil : query
        let maxChats = viewModel.maxSuggestions

        currentFetchTask = Task {
            let suggestions = await reader.fetchSuggestions(query: effectiveQuery, maxChats: maxChats)
            guard !Task.isCancelled else { return }
            let hasSuggestions = !(suggestions.pinned.isEmpty && suggestions.recent.isEmpty)
            viewModel.setChats(pinned: suggestions.pinned, recent: suggestions.recent)
            hasCompletedInitialFetch = true
            lastCompletedFetchQuery = query
            onFetchCompleted?(query, hasSuggestions)
        }
    }

    /// Tears down the suggestions reader and releases resources
    func tearDown() {
        currentFetchTask?.cancel()
        currentFetchTask = nil
        lastCompletedFetchQuery = nil
        cancellables.removeAll()

        suggestionsReader.tearDown()
        viewModel.clearAllChats()
        onFetchCompleted = nil
    }
}
