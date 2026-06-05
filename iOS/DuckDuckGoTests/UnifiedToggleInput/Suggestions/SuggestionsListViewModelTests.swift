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

// MARK: - Stub

private final class StubSuggestionsSource: SuggestionsSource {

    let sectionsPublisher: AnyPublisher<[SuggestionSection], Never>

    init(sections: [SuggestionSection]) {
        sectionsPublisher = Just(sections).eraseToAnyPublisher()
    }

    func start(textPublisher: AnyPublisher<String, Never>) {}
    func tearDown() {}

    static func makeRow(id: String) -> SuggestionRow {
        SuggestionRow(id: id, icon: .search, title: id, accessibilityID: id)
    }

    static func twoRowSource() -> StubSuggestionsSource {
        StubSuggestionsSource(sections: [
            SuggestionSection(id: "s", rows: [makeRow(id: "r1"), makeRow(id: "r2")])
        ])
    }

    static func threeRowSource() -> StubSuggestionsSource {
        StubSuggestionsSource(sections: [
            SuggestionSection(id: "s", rows: [makeRow(id: "r1"), makeRow(id: "r2"), makeRow(id: "r3")])
        ])
    }
}

// MARK: - Tests

@MainActor
final class SuggestionsListViewModelTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    func test_duckAISource_composesChatsUrlsSearch_inOrder_skippingEmpty() {
        let snapshot = DuckAISuggestionsPipeline.Snapshot(
            chats: [AIChatSuggestion(id: "1", title: "Recent", isPinned: false, chatId: "c")],
            urls: [.website(url: URL(string: "https://swift.org")!)],
            isPending: false
        )
        let sections = DuckAISuggestionsSource.sections(from: snapshot, query: "swift")
        XCTAssertEqual(sections.map(\.id), ["chats", "urls", "search"])
        XCTAssertEqual(sections[0].rows.first?.title, "Recent")
        XCTAssertEqual(sections[2].rows.first?.title, "swift")
    }

    func test_duckAISource_emptyQuery_hasNoSearchSection() {
        let snapshot = DuckAISuggestionsPipeline.Snapshot(chats: [], urls: [], isPending: false)
        let sections = DuckAISuggestionsSource.sections(from: snapshot, query: "")
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
        let snapshot = DuckAISuggestionsPipeline.Snapshot(
            chats: [],
            urls: [.website(url: URL(string: "https://x.com")!)],
            isPending: false
        )
        let sections = DuckAISuggestionsSource.sections(from: snapshot, query: "")
        XCTAssertEqual(sections.map(\.id), ["urls"])
    }

    // MARK: - Keyboard navigation

    func test_moveDown_fromNil_selectsFirst() {
        let vm = SuggestionsListViewModel(source: StubSuggestionsSource.twoRowSource())
        vm.moveSelectionDown()
        XCTAssertEqual(vm.selectedRowID, "r1")
    }

    func test_moveUp_fromNil_selectsLast() {
        let vm = SuggestionsListViewModel(source: StubSuggestionsSource.twoRowSource())
        vm.moveSelectionUp()
        XCTAssertEqual(vm.selectedRowID, "r2")
    }

    func test_moveDown_atLast_staysAtLast() {
        let vm = SuggestionsListViewModel(source: StubSuggestionsSource.twoRowSource())
        vm.moveSelectionDown()
        vm.moveSelectionDown()
        vm.moveSelectionDown()
        XCTAssertEqual(vm.selectedRowID, "r2")
    }

    func test_moveUp_atFirst_staysAtFirst() {
        let vm = SuggestionsListViewModel(source: StubSuggestionsSource.twoRowSource())
        vm.moveSelectionDown()
        vm.moveSelectionUp()
        vm.moveSelectionUp()
        XCTAssertEqual(vm.selectedRowID, "r1")
    }

    func test_commit_callsOnSelectWithSelectedID() {
        let vm = SuggestionsListViewModel(source: StubSuggestionsSource.twoRowSource())
        var selected: String?
        vm.onSelect = { selected = $0 }
        vm.moveSelectionDown()
        vm.commitSelection()
        XCTAssertEqual(selected, "r1")
    }

    func test_commit_withNoSelection_doesNotCallOnSelect() {
        let vm = SuggestionsListViewModel(source: StubSuggestionsSource.twoRowSource())
        var called = false
        vm.onSelect = { _ in called = true }
        vm.commitSelection()
        XCTAssertFalse(called)
    }

    func test_moveDown_advances_through_rows() {
        let vm = SuggestionsListViewModel(source: StubSuggestionsSource.threeRowSource())
        vm.moveSelectionDown()
        XCTAssertEqual(vm.selectedRowID, "r1")
        vm.moveSelectionDown()
        XCTAssertEqual(vm.selectedRowID, "r2")
        vm.moveSelectionDown()
        XCTAssertEqual(vm.selectedRowID, "r3")
    }
}
