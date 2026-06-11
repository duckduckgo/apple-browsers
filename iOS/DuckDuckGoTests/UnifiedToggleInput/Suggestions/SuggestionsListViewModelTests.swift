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
}
