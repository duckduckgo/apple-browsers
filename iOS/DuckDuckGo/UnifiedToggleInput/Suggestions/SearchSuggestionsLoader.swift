//
//  SearchSuggestionsLoader.swift
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

import BrowserServicesKit
import Combine
import Common
import Foundation
import PrivacyConfig
import Suggestions

/// Drives `SuggestionLoader` for the Search surface and publishes the latest result.
/// Mirrors `DuckAIURLSuggestionsLoader` but keeps all suggestion categories.
@MainActor
final class SearchSuggestionsLoader {

    @Published private(set) var result: SuggestionResult = .appEmpty
    private(set) var lastCompletedFetchQuery: String?

    private let featureFlagger: FeatureFlagger
    private let dataSource: SuggestionLoadingDataSource
    private let useUnifiedURLPrediction: Bool
    private var loader: SuggestionLoader?
    private var latestQuery: String?
    private var fetchID = UUID()
    private var cancellables = Set<AnyCancellable>()

    init(dataSource: SuggestionLoadingDataSource, useUnifiedURLPrediction: Bool, featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
        self.dataSource = dataSource
        self.useUnifiedURLPrediction = useUnifiedURLPrediction
    }

    /// Mirrors legacy `AutocompleteViewController`: always load suggestions, except when the user has
    /// typed a "complete" root URL (http[s], no path, trailing "/") — then keep the typed URL as-is.
    private func shouldLoadSuggestions(for phrase: String) -> Bool {
        guard let url = URL(trimmedAddressBarString: phrase, useUnifiedLogic: useUnifiedURLPrediction),
              url.isValid(usingUnifiedLogic: useUnifiedURLPrediction) else {
            return true
        }
        if let scheme = url.scheme, scheme.description.hasPrefix("http"), url.isRoot, phrase.last == "/" {
            return false
        }
        return true
    }

    func subscribeToTextChanges<P: Publisher, S: Scheduler>(_ textPublisher: P, scheduler: S = DispatchQueue.main)
        where P.Output == String, P.Failure == Never {
        textPublisher
            .removeDuplicates(by: { [featureFlagger] previous, current in
                featureFlagger.isFeatureOn(.suggestionDebounce200ms) && previous == current
            })
            .handleEvents(receiveOutput: { [weak self] text in
                guard let self, self.featureFlagger.isFeatureOn(.suggestionDebounce200ms) else { return }
                self.latestQuery = text
            })
            .debounceSuggestions(using: featureFlagger, scheduler: scheduler)
            .removeDuplicates(by: { [featureFlagger] previous, current in
                !featureFlagger.isFeatureOn(.suggestionDebounce200ms) && previous == current
            })
            .sink { [weak self] request in
                self?.fetch(query: request.query, includeRemoteSuggestions: request.includeRemoteSuggestions)
            }
            .store(in: &cancellables)
    }

    func fetch(query: String, includeRemoteSuggestions: Bool = true) {
        let usesSeparateDebounce = featureFlagger.isFeatureOn(.suggestionDebounce200ms)
        latestQuery = query
        let fetchID = UUID()
        self.fetchID = fetchID
        guard !query.isEmpty else {
            if result != .appEmpty { result = .appEmpty }
            lastCompletedFetchQuery = query
            return
        }
        loader = SuggestionLoader(shouldLoadSuggestionsForUserInput: { [weak self] phrase in
            includeRemoteSuggestions && (self?.shouldLoadSuggestions(for: phrase) ?? true)
        }, isUrlIgnored: { _ in false })
        loader?.getSuggestions(query: query, usingDataSource: dataSource) { [weak self] result, _ in
            guard let self else { return }
            guard !usesSeparateDebounce || self.fetchID == fetchID,
                  self.latestQuery == query || (usesSeparateDebounce && self.result.all.isEmpty && self.latestQuery?.hasPrefix(query) == true) else { return }
            if includeRemoteSuggestions { self.lastCompletedFetchQuery = query }
            self.result = result ?? .appEmpty
        }
    }

    /// Clears state for a fresh editing session so the long-lived loader never renders a previous
    /// session's suggestions for the new query.
    func reset() {
        loader = nil
        fetchID = UUID()
        latestQuery = nil
        lastCompletedFetchQuery = nil
        // Unconditional (no `!= .appEmpty` guard) to force `sectionsPublisher` to recompute
        result = .appEmpty
    }

    func tearDown() { cancellables.removeAll() }
}

extension SuggestionResult {
    /// App-side convenience; the package's `.empty` is `internal` to `Suggestions`.
    static let appEmpty = SuggestionResult(topHits: [], duckduckgoSuggestions: [], localSuggestions: [])
}
