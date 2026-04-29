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

/// Fetches the same top-ranked URL hits as the Search-side autocomplete and
/// caps them at `maxResults`, used by the Duck.ai suggestions list to render
/// its "Top URLs" section. Reuses `SuggestionLoader` + `AutocompleteSuggestionsDataSource`
/// so ranking is identical to the Search side.
@MainActor
final class DuckAIURLSuggestionsLoader {

    static let defaultMaxResults = 3
    private static let debounceMilliseconds = 100

    @Published private(set) var topURLs: [Suggestion] = []

    private let dataSource: AutocompleteSuggestionsDataSource
    private let maxResults: Int
    private var loader: SuggestionLoader?
    private var cancellables = Set<AnyCancellable>()

    init(dataSource: AutocompleteSuggestionsDataSource, maxResults: Int = defaultMaxResults) {
        self.dataSource = dataSource
        self.maxResults = maxResults
    }

    /// Pure function so the URL filtering + cap behavior is unit-testable
    /// without spinning up a real loader or data source.
    static func urlOnlyTopHits(from result: SuggestionResult, max: Int) -> [Suggestion] {
        let urlOnly = result.filteringToURLsOnly()
        let combined = urlOnly.topHits + urlOnly.duckduckgoSuggestions + urlOnly.localSuggestions
        return Array(combined.prefix(max))
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

    func fetch(query: String) {
        guard !query.isEmpty else {
            // Avoid re-publishing an already-empty list — `@Published` emits even when value
            // doesn't change, which would trigger an unnecessary downstream reload.
            if !topURLs.isEmpty { topURLs = [] }
            return
        }

        loader = SuggestionLoader(
            shouldLoadSuggestionsForUserInput: { _ in true },
            isUrlIgnored: { _ in false }
        )
        loader?.getSuggestions(query: query, usingDataSource: dataSource) { [weak self] result, error in
            guard let self else { return }
            guard error == nil, let result else { return }
            self.topURLs = Self.urlOnlyTopHits(from: result, max: self.maxResults)
        }
    }

    func tearDown() {
        loader = nil
        cancellables.removeAll()
        topURLs = []
    }
}
