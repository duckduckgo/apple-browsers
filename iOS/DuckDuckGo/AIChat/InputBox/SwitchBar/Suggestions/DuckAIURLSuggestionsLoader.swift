//
//  DuckAIURLSuggestionsLoader.swift
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
import Foundation
import Suggestions

/// Reuses Search-side `SuggestionLoader` ranking; produces top-N URL-typed suggestions for the Duck.ai list.
@MainActor
final class DuckAIURLSuggestionsLoader {

    static let defaultMaxResults = 3
    private static let debounceMilliseconds = 100

    @Published private(set) var topURLs: [Suggestion] = []

    private let dataSource: SuggestionLoadingDataSource
    private let maxResults: Int
    private lazy var loader = SuggestionLoader(
        shouldLoadSuggestionsForUserInput: { _ in true },
        isUrlIgnored: { _ in false }
    )
    /// Out-of-order guard: `SuggestionLoader` has no cancellation, so a slow callback for a stale query would otherwise win.
    private var latestDispatchedQuery: String?
    /// Settle marker: callers compare against current text to detect "fetcher hasn't caught up yet" and gate Dax visibility.
    private(set) var lastCompletedFetchQuery: String?
    private var cancellables = Set<AnyCancellable>()

    init(dataSource: SuggestionLoadingDataSource, maxResults: Int = defaultMaxResults) {
        self.dataSource = dataSource
        self.maxResults = maxResults
    }

    /// Pure function so the URL filtering + cap behavior is unit-testable without a real loader.
    static func urlOnlyTopHits(from result: SuggestionResult, max: Int) -> [Suggestion] {
        Array(result.filteringToURLsOnly().all.prefix(max))
    }

    func subscribeToTextChanges<P: Publisher>(_ textPublisher: P)
        where P.Output == String, P.Failure == Never {
        textPublisher
            .debounce(for: .milliseconds(Self.debounceMilliseconds), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] text in
                self?.fetch(query: text)
            }
            .store(in: &cancellables)
    }

    func refreshSuggestions() {
        fetch(query: latestDispatchedQuery ?? "")
    }

    func fetch(query: String) {
        latestDispatchedQuery = query
        guard !query.isEmpty else {
            // Skip re-emitting an already-empty list — @Published emits unconditionally and would trigger a needless reload.
            if !topURLs.isEmpty { topURLs = [] }
            lastCompletedFetchQuery = query
            return
        }

        loader.getSuggestions(query: query, usingDataSource: dataSource) { [weak self] result, _ in
            guard let self else { return }
            guard self.latestDispatchedQuery == query else { return }
            // Always settle, even on error — otherwise `hasSettled` stays false forever and Dax suppression never clears.
            self.lastCompletedFetchQuery = query
            // Local matches (bookmarks/history/open tabs) come back even when the remote API errors — keep them.
            if let result {
                self.topURLs = Self.urlOnlyTopHits(from: result, max: self.maxResults)
            } else if !self.topURLs.isEmpty {
                self.topURLs = []
            }
        }
    }

    func tearDown() {
        cancellables.removeAll()
        latestDispatchedQuery = nil
        lastCompletedFetchQuery = nil
        topURLs = []
    }

#if DEBUG
    /// Test-only setter; production writes go through the fetcher closure.
    func publishURLsForTesting(_ urls: [Suggestion]) {
        topURLs = urls
    }
#endif
}
