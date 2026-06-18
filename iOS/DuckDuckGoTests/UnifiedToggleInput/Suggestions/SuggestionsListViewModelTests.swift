//
//  SuggestionsListViewModelTests.swift
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

    // MARK: - Keyboard/pointer selection

    /// Builds a list view model backed by `count` recent chats and returns it with its row ids in order.
    private func makeSelectionViewModel(count: Int) -> (SuggestionsListViewModel, [String]) {
        let chats = (0..<count).map { AIChatSuggestion(id: "\($0)", title: "R\($0)", isPinned: false, chatId: "c\($0)") }
        let vm = AIChatSuggestionsViewModel()
        vm.setChats(pinned: [], recent: chats)
        let listVM = SuggestionsListViewModel(source: RecentsSuggestionsSource(viewModel: vm))
        let ids = listVM.sections.flatMap { $0.rows.map(\.id) }
        return (listVM, ids)
    }

    func test_moveSelectionDown_fromNoSelection_selectsFirstRow() {
        let (vm, ids) = makeSelectionViewModel(count: 3)
        vm.moveSelectionDown()
        XCTAssertEqual(vm.selectedRowID, ids.first)
    }

    func test_moveSelectionDown_atLastRow_staysOnLastRow() {
        let (vm, ids) = makeSelectionViewModel(count: 3)
        vm.selectedRowID = ids.last
        vm.moveSelectionDown()
        XCTAssertEqual(vm.selectedRowID, ids.last)
    }

    func test_moveSelectionUp_fromNoSelection_isNoOp() {
        let (vm, _) = makeSelectionViewModel(count: 3)
        vm.moveSelectionUp()
        XCTAssertNil(vm.selectedRowID)
    }

    func test_moveSelectionUp_fromFirstRow_clearsSelection() {
        let (vm, ids) = makeSelectionViewModel(count: 3)
        vm.selectedRowID = ids.first
        vm.moveSelectionUp()
        XCTAssertNil(vm.selectedRowID, "Up from the first row should clear the highlight (focus returns to input)")
    }

    func test_moveSelectionUp_fromMiddle_movesUp() {
        let (vm, ids) = makeSelectionViewModel(count: 3)
        vm.selectedRowID = ids[1]
        vm.moveSelectionUp()
        XCTAssertEqual(vm.selectedRowID, ids[0])
    }

    func test_duckAISource_viewAllChatsRowShownOnlyForEmptyQuery() {
        let snapshot = DuckAISuggestionsPipeline.Snapshot(
            chats: [AIChatSuggestion(id: "1", title: "Recent", isPinned: false, chatId: "c")],
            urls: [],
            isPending: false
        )

        let withRecents = DuckAISuggestionsSource.sections(from: snapshot, query: "", viewAllChatsEnabled: true)
        XCTAssertTrue(withRecents.first?.rows.contains { $0.id == "view-all-chats" } == true)

        let whileSearching = DuckAISuggestionsSource.sections(from: snapshot, query: "rec", viewAllChatsEnabled: true)
        XCTAssertFalse(whileSearching.first?.rows.contains { $0.id == "view-all-chats" } == true)
    }
}
