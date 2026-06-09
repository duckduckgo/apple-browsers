//
//  SearchSuggestionsLoader.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import BrowserServicesKit
import Combine
import Common
import Foundation
import Suggestions

/// Drives `SuggestionLoader` for the Search surface and publishes the latest result.
/// Mirrors `DuckAIURLSuggestionsLoader` but keeps all suggestion categories.
@MainActor
final class SearchSuggestionsLoader {

    @Published private(set) var result: SuggestionResult = .appEmpty
    private(set) var lastCompletedFetchQuery: String?

    private let dataSource: SuggestionLoadingDataSource
    private let useUnifiedURLPrediction: Bool
    private var loader: SuggestionLoader?
    private var latestDispatchedQuery: String?
    private var cancellables = Set<AnyCancellable>()

    private static let debounceMilliseconds = 100

    init(dataSource: SuggestionLoadingDataSource, useUnifiedURLPrediction: Bool) {
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

    func subscribeToTextChanges<P: Publisher>(_ textPublisher: P)
        where P.Output == String, P.Failure == Never {
        textPublisher
            .debounce(for: .milliseconds(Self.debounceMilliseconds), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] text in self?.fetch(query: text) }
            .store(in: &cancellables)
    }

    func fetch(query: String) {
        latestDispatchedQuery = query
        guard !query.isEmpty else {
            if result != .appEmpty { result = .appEmpty }
            lastCompletedFetchQuery = query
            return
        }
        loader = SuggestionLoader(shouldLoadSuggestionsForUserInput: { [weak self] phrase in
            self?.shouldLoadSuggestions(for: phrase) ?? true
        }, isUrlIgnored: { _ in false })
        loader?.getSuggestions(query: query, usingDataSource: dataSource) { [weak self] result, _ in
            guard let self, self.latestDispatchedQuery == query else { return }
            self.lastCompletedFetchQuery = query
            self.result = result ?? .appEmpty
        }
    }

    func tearDown() { cancellables.removeAll() }
}

extension SuggestionResult {
    /// App-side convenience; the package's `.empty` is `internal` to `Suggestions`.
    static let appEmpty = SuggestionResult(topHits: [], duckduckgoSuggestions: [], localSuggestions: [])
}
