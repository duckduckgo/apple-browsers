//
//  SuggestionsListViewModelTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import AIChat
import Combine
import Suggestions
import XCTest
@testable import DuckDuckGo

@MainActor
final class SuggestionsListViewModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func test_duckAISource_composesChatsUrlsSearch_inOrder_skippingEmpty() {
        let snapshots = CurrentValueSubject<DuckAISuggestionsPipeline.Snapshot, Never>(
            .init(chats: [AIChatSuggestion(id: "1", title: "Recent", isPinned: false, chatId: "c")],
                  urls: [.website(url: URL(string: "https://swift.org")!)],
                  isPending: false))
        let source = DuckAISuggestionsSource(snapshotPublisher: snapshots.eraseToAnyPublisher(),
                                             query: { "swift" })

        var sections: [SuggestionSection] = []
        source.sectionsPublisher.sink { sections = $0 }.store(in: &cancellables)

        XCTAssertEqual(sections.map(\.id), ["chats", "urls", "search"])
        XCTAssertEqual(sections[0].rows.first?.title, "Recent")
        XCTAssertEqual(sections[2].rows.first?.title, "swift")
    }

    func test_duckAISource_emptyQuery_hasNoSearchSection() {
        let snapshots = CurrentValueSubject<DuckAISuggestionsPipeline.Snapshot, Never>(
            .init(chats: [], urls: [], isPending: false))
        let source = DuckAISuggestionsSource(snapshotPublisher: snapshots.eraseToAnyPublisher(),
                                             query: { "" })

        var sections: [SuggestionSection] = []
        source.sectionsPublisher.sink { sections = $0 }.store(in: &cancellables)

        XCTAssertTrue(sections.isEmpty)
    }

    func test_recentsSource_singleSection_fromChats() {
        let vm = AIChatSuggestionsViewModel()
        vm.setChats(pinned: [], recent: [AIChatSuggestion(id: "1", title: "R", isPinned: false, chatId: "c")])
        let source = RecentsSuggestionsSource(viewModel: vm)

        var sections: [SuggestionSection] = []
        source.sectionsPublisher.sink { sections = $0 }.store(in: &cancellables)

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.rows.first?.title, "R")
    }

    func test_listViewModel_publishesSectionsFromSource() {
        let snapshots = CurrentValueSubject<DuckAISuggestionsPipeline.Snapshot, Never>(
            .init(chats: [], urls: [.website(url: URL(string: "https://x.com")!)], isPending: false))
        let source = DuckAISuggestionsSource(snapshotPublisher: snapshots.eraseToAnyPublisher(),
                                             query: { "" })
        let sut = SuggestionsListViewModel(source: source)

        XCTAssertEqual(sut.sections.map(\.id), ["urls"])
    }
}
