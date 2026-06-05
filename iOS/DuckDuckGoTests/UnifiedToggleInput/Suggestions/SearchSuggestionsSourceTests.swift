//
//  SearchSuggestionsSourceTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Combine
import Suggestions
import XCTest
@testable import DuckDuckGo

@MainActor
final class SearchSuggestionsSourceTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()
    override func tearDown() { cancellables.removeAll(); super.tearDown() }

    private func source(result: SuggestionResult, query: String, showAskAIChat: Bool = false) -> SearchSuggestionsSource {
        let subject = CurrentValueSubject<SuggestionResult, Never>(result)
        let src = SearchSuggestionsSource(resultPublisher: subject.eraseToAnyPublisher(),
                                          query: { query },
                                          showAskAIChat: showAskAIChat)
        src.sectionsPublisher.sink { _ in }.store(in: &cancellables)
        return src
    }

    func test_categoriesBecomeSectionsInOrder() {
        let r = SuggestionResult(topHits: [.website(url: URL(string: "https://a.com")!)],
                                 duckduckgoSuggestions: [.phrase(phrase: "cats")],
                                 localSuggestions: [.bookmark(title: "B", url: URL(string: "https://b.com")!, isFavorite: false, score: 0)])
        var sections: [SuggestionSection] = []
        source(result: r, query: "ca").sectionsPublisher.sink { sections = $0 }.store(in: &cancellables)
        XCTAssertEqual(sections.map(\.id), ["topHits", "ddg", "local"])
    }

    func test_askAIChatSection_whenEnabled_withQuery() {
        var sections: [SuggestionSection] = []
        source(result: .appEmpty, query: "weather", showAskAIChat: true).sectionsPublisher.sink { sections = $0 }.store(in: &cancellables)
        XCTAssertTrue(sections.contains { $0.id == "askAIChat" })
    }

    func test_historyRow_hasDeleteAccessory() {
        let url = URL(string: "https://h.com")!
        let r = SuggestionResult(topHits: [.historyEntry(title: "H", url: url, score: 0)],
                                 duckduckgoSuggestions: [], localSuggestions: [])
        var sections: [SuggestionSection] = []
        source(result: r, query: "h").sectionsPublisher.sink { sections = $0 }.store(in: &cancellables)
        XCTAssertEqual(sections.first?.rows.first?.accessory, .delete)
    }

    func test_resolvesRowIDToSuggestion() {
        let url = URL(string: "https://a.com")!
        let s = Suggestion.website(url: url)
        let src = source(result: SuggestionResult(topHits: [s], duckduckgoSuggestions: [], localSuggestions: []), query: "a")
        XCTAssertEqual(src.suggestion(forRowID: "topHits-website-\(url.absoluteString)"), s)
    }
}
