//
//  DuckAISuggestionsViewControllerTests.swift
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
import Suggestions
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class DuckAISuggestionsViewControllerTests: XCTestCase {

    private struct Harness {
        let viewController: DuckAISuggestionsViewController
        let chatViewModel: AIChatSuggestionsViewModel
        let urlLoader: DuckAIURLSuggestionsLoader
    }

    private func makeHarness(query: String = "") -> Harness {
        let viewModel = AIChatSuggestionsViewModel()
        let loader = DuckAIURLSuggestionsLoader(dataSource: EmptySuggestionLoadingDataSource())
        let vc = DuckAISuggestionsViewController(
            chatViewModel: viewModel,
            urlLoader: loader,
            queryProvider: { query }
        )
        vc.loadViewIfNeeded()
        return Harness(viewController: vc, chatViewModel: viewModel, urlLoader: loader)
    }

    private func makeViewController(query: String = "") -> DuckAISuggestionsViewController {
        makeHarness(query: query).viewController
    }

    private func makeChat(id: String) -> AIChatSuggestion {
        AIChatSuggestion(id: id, title: "Chat \(id)", isPinned: false, chatId: "chat-\(id)")
    }

    private func tableView(in vc: DuckAISuggestionsViewController) throws -> UITableView {
        try XCTUnwrap(vc.view.subviews.compactMap { $0 as? UITableView }.first,
                      "Expected a UITableView in the view hierarchy")
    }

    // MARK: - Hatch install / remove

    func test_setEscapeHatch_withModel_installsTableHeaderView() throws {
        let vc = makeViewController()
        let table = try tableView(in: vc)
        XCTAssertNil(table.tableHeaderView)

        vc.setEscapeHatch(.testFixture, onTapped: {})

        XCTAssertNotNil(table.tableHeaderView)
        XCTAssertGreaterThan(table.tableHeaderView?.bounds.height ?? 0, 0)
        XCTAssertEqual(vc.children.count, 1, "hatch hosting controller should be added as a child view controller")
    }

    func test_setEscapeHatch_withNil_removesTableHeaderView() throws {
        let vc = makeViewController()
        vc.setEscapeHatch(.testFixture, onTapped: {})
        XCTAssertNotNil(try tableView(in: vc).tableHeaderView)

        vc.setEscapeHatch(nil, onTapped: nil)

        XCTAssertNil(try tableView(in: vc).tableHeaderView)
        XCTAssertTrue(vc.children.isEmpty, "hatch hosting controller should be removed from children")
    }

    func test_setEscapeHatch_calledTwiceWithModel_replacesExistingHostingController() {
        let vc = makeViewController()
        vc.setEscapeHatch(.testFixture, onTapped: {})
        let firstChild = vc.children.first

        vc.setEscapeHatch(.testFixture, onTapped: {})

        XCTAssertEqual(vc.children.count, 1)
        XCTAssertFalse(vc.children.first === firstChild, "second call should replace the previous hosting controller")
    }

    // MARK: - contentInset switching

    func test_setEscapeHatch_withModel_appliesWithHatchInset() throws {
        let vc = makeViewController()
        let table = try tableView(in: vc)
        XCTAssertEqual(table.contentInset.top, -20, "without-hatch inset is the lazy initializer default")

        vc.setEscapeHatch(.testFixture, onTapped: {})

        XCTAssertEqual(table.contentInset.top, 0,
                       "with hatch present, inset switches so the header sits ~16pt below UTI")
    }

    func test_setEscapeHatch_withNil_restoresWithoutHatchInset() throws {
        let vc = makeViewController()
        vc.setEscapeHatch(.testFixture, onTapped: {})
        XCTAssertEqual(try tableView(in: vc).contentInset.top, 0)

        vc.setEscapeHatch(nil, onTapped: nil)

        XCTAssertEqual(try tableView(in: vc).contentInset.top, -20)
    }

    // MARK: - Live sections
    // Earlier stale-section caching caused relayout crashes — guard against regression by asserting numberOfSections directly.

    func test_liveSections_emptyEverything_returnsZero() throws {
        let harness = makeHarness(query: "")

        XCTAssertEqual(try tableView(in: harness.viewController).numberOfSections, 0)
    }

    func test_liveSections_queryOnly_returnsSearchRowOnly() throws {
        let harness = makeHarness(query: "x")

        XCTAssertEqual(try tableView(in: harness.viewController).numberOfSections, 1,
                       "non-empty query → always-visible Search-DuckDuckGo row")
    }

    func test_liveSections_chatsOnly_returnsChatsAndSearch() throws {
        let harness = makeHarness(query: "x")
        harness.chatViewModel.setChats(pinned: [], recent: [makeChat(id: "1")])

        XCTAssertEqual(try tableView(in: harness.viewController).numberOfSections, 2)
    }

    func test_liveSections_allThree_returnsThree() throws {
        let harness = makeHarness(query: "x")
        harness.chatViewModel.setChats(pinned: [], recent: [makeChat(id: "1")])
        harness.urlLoader.publishURLsForTesting([
            .website(url: try XCTUnwrap(URL(string: "https://example.com/")))
        ])

        XCTAssertEqual(try tableView(in: harness.viewController).numberOfSections, 3)
    }
}

// MARK: - Test doubles

private extension EscapeHatchModel {
    static var testFixture: EscapeHatchModel {
        EscapeHatchModel(
            title: "Test tab",
            subtitle: "example.com",
            tabType: .regular,
            domain: "example.com",
            targetTab: Tab(fireTab: false)
        )
    }
}
