//
//  UnifiedSuggestionsViewModelTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import Combine
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedSuggestionsViewModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()
    override func tearDown() { cancellables.removeAll(); super.tearDown() }

    func test_searchEmptyWithFavorites_publishesFavorites() {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .search, isTyping: false, hasFavorites: true, hasMessages: false, hasRecents: false, resultsPending: false))
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        XCTAssertEqual(sut.content, .favorites)
    }

    func test_searchTyping_publishesList() {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: .search, isTyping: true, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        XCTAssertEqual(sut.content, .list(.search))
    }
}

private final class EmptySuggestionsSource: SuggestionsSource {
    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never> = Just([]).eraseToAnyPublisher()
}
