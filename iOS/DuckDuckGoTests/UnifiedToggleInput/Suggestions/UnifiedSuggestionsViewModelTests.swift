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

    // MARK: - Duck.ai suggestions shown

    private func makeDuckAISUT(mode: TextEntryMode, sections: [SuggestionSection])
        -> (UnifiedSuggestionsViewModel, CurrentValueSubject<UnifiedSuggestionsInputs, Never>, StubSuggestionsSource, () -> Int) {
        let inputs = CurrentValueSubject<UnifiedSuggestionsInputs, Never>(
            .init(mode: mode, isTyping: true, hasFavorites: false, hasMessages: false, hasRecents: false, resultsPending: false))
        let duckAISource = StubSuggestionsSource(sections: sections)
        let sut = UnifiedSuggestionsViewModel(inputsPublisher: inputs.eraseToAnyPublisher(),
                                              listViewModel: SuggestionsListViewModel(source: EmptySuggestionsSource()))
        var shownCount = 0
        sut.onDuckAISuggestionsShown = { shownCount += 1 }
        sut.setDuckAIListViewModel(SuggestionsListViewModel(source: duckAISource))
        inputs.send(inputs.value)
        return (sut, inputs, duckAISource, { shownCount })
    }

    func test_duckAIListWithRows_reportsShownOncePerFocus() {
        let (sut, inputs, duckAISource, shownCount) = makeDuckAISUT(mode: .aiChat, sections: [Self.section])
        duckAISource.subject.send([Self.section, Self.section])
        XCTAssertEqual(shownCount(), 1)

        sut.prepareForActivation()
        inputs.send(inputs.value)
        XCTAssertEqual(shownCount(), 2)
    }

    func test_duckAIRowsArrivingAfterTheListShows_reportShown() {
        let (sut, _, duckAISource, shownCount) = makeDuckAISUT(mode: .aiChat, sections: [])
        XCTAssertEqual(shownCount(), 0)

        duckAISource.subject.send([Self.section])
        XCTAssertEqual(shownCount(), 1)
        withExtendedLifetime(sut) {}
    }

    func test_searchList_neverReportsDuckAIShown() {
        let (sut, _, duckAISource, shownCount) = makeDuckAISUT(mode: .search, sections: [Self.section])
        duckAISource.subject.send([Self.section])
        XCTAssertEqual(shownCount(), 0)
        withExtendedLifetime(sut) {}
    }

    private static let section = SuggestionSection(id: "chats", rows: [])
}

private final class StubSuggestionsSource: SuggestionsSource {
    let subject: CurrentValueSubject<[SuggestionSection], Never>
    var sectionsPublisher: AnyPublisher<[SuggestionSection], Never> { subject.eraseToAnyPublisher() }
    init(sections: [SuggestionSection]) { subject = CurrentValueSubject(sections) }
    func start(textPublisher: AnyPublisher<String, Never>) {}
    func tearDown() {}
}

private final class EmptySuggestionsSource: SuggestionsSource {
    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never> = Just([]).eraseToAnyPublisher()
    func start(textPublisher: AnyPublisher<String, Never>) {}
    func tearDown() {}
}
