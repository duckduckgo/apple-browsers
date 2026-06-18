//
//  UnifiedSuggestionsViewModelTests.swift
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
    func start(textPublisher: AnyPublisher<String, Never>) {}
    func tearDown() {}
}
