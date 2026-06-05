//
//  SearchSuggestionsLoader.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import BrowserServicesKit
import Combine
import Suggestions

/// Drives `SuggestionLoader` for the Search surface and publishes the latest result.
/// Mirrors `DuckAIURLSuggestionsLoader` but keeps all suggestion categories.
@MainActor
final class SearchSuggestionsLoader {

    @Published private(set) var result: SuggestionResult = .appEmpty
    private(set) var lastCompletedFetchQuery: String?

    private let dataSource: SuggestionLoadingDataSource
    private var loader: SuggestionLoader?
    private var latestDispatchedQuery: String?
    private var cancellables = Set<AnyCancellable>()

    private static let debounceMilliseconds = 100

    init(dataSource: SuggestionLoadingDataSource) {
        self.dataSource = dataSource
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
        loader = SuggestionLoader(shouldLoadSuggestionsForUserInput: { _ in true }, isUrlIgnored: { _ in false })
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
