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

    private func makeHarness(query: String = "",
                             layoutConfiguration: DuckAISuggestionsViewController.LayoutConfiguration = .standard) -> Harness {
        let viewModel = AIChatSuggestionsViewModel()
        let loader = DuckAIURLSuggestionsLoader(dataSource: EmptySuggestionLoadingDataSource())
        let vc = DuckAISuggestionsViewController(
            chatViewModel: viewModel,
            urlLoader: loader,
            queryProvider: { query },
            layoutConfiguration: layoutConfiguration
        )
        vc.loadViewIfNeeded()
        return Harness(viewController: vc, chatViewModel: viewModel, urlLoader: loader)
    }

    private func makeViewController(query: String = "",
                                    layoutConfiguration: DuckAISuggestionsViewController.LayoutConfiguration = .standard) -> DuckAISuggestionsViewController {
        makeHarness(query: query, layoutConfiguration: layoutConfiguration).viewController
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

        vc.setEscapeHatch(.testFixture, openTabCount: 0, onTapped: {}, onTabSwitcherTapped: {})

        XCTAssertNotNil(table.tableHeaderView)
        XCTAssertGreaterThan(table.tableHeaderView?.bounds.height ?? 0, 0)
        XCTAssertEqual(vc.children.count, 1, "hatch hosting controller should be added as a child view controller")
    }

    func test_defaultLayout_preservesFullWidthTableView() throws {
        let vc = makeViewController()
        vc.view.frame = CGRect(x: 0, y: 0, width: 430, height: 800)
        vc.view.layoutIfNeeded()

        let table = try tableView(in: vc)

        XCTAssertEqual(table.frame.minX, 0, accuracy: 0.5)
        XCTAssertEqual(vc.view.bounds.width - table.frame.maxX, 0, accuracy: 0.5)
    }

    func test_unifiedToggleInputLayout_matchesRecentChatsHorizontalInset() throws {
        let vc = makeViewController(layoutConfiguration: .unifiedToggleInput)
        vc.view.frame = CGRect(x: 0, y: 0, width: 430, height: 800)
        vc.view.layoutIfNeeded()

        let table = try tableView(in: vc)
        vc.setEscapeHatch(.testFixture, openTabCount: 0, onTapped: {}, onTabSwitcherTapped: {})
        vc.view.layoutIfNeeded()

        let header = try XCTUnwrap(table.tableHeaderView)
        let hatchView = try XCTUnwrap(header.subviews.first)
        let hatchFrame = hatchView.convert(hatchView.bounds, to: vc.view)
        let expectedTableInset: CGFloat = 10
        let expectedHatchInset: CGFloat = 26

        XCTAssertEqual(table.frame.minX, expectedTableInset, accuracy: 0.5)
        XCTAssertEqual(vc.view.bounds.width - table.frame.maxX, expectedTableInset, accuracy: 0.5)
        XCTAssertEqual(header.bounds.width, table.bounds.width, accuracy: 0.5)
        XCTAssertEqual(hatchFrame.minX, expectedHatchInset, accuracy: 0.5)
        XCTAssertEqual(vc.view.bounds.width - hatchFrame.maxX, expectedHatchInset, accuracy: 0.5)
    }

    func test_setEscapeHatch_withNil_removesTableHeaderView() throws {
        let vc = makeViewController()
        vc.setEscapeHatch(.testFixture, openTabCount: 0, onTapped: {}, onTabSwitcherTapped: {})
        XCTAssertNotNil(try tableView(in: vc).tableHeaderView)

        vc.setEscapeHatch(nil, openTabCount: 0, onTapped: nil, onTabSwitcherTapped: nil)

        XCTAssertNil(try tableView(in: vc).tableHeaderView)
        XCTAssertTrue(vc.children.isEmpty, "hatch hosting controller should be removed from children")
    }

    func test_setEscapeHatch_calledTwiceWithDifferentModels_replacesExistingHostingController() {
        // Each `.testFixture` build a new Tab with a fresh uid, so the two models compare unequal.
        let vc = makeViewController()
        vc.setEscapeHatch(.testFixture, openTabCount: 0, onTapped: {}, onTabSwitcherTapped: {})
        let firstChild = vc.children.first

        vc.setEscapeHatch(.testFixture, openTabCount: 0, onTapped: {}, onTabSwitcherTapped: {})

        XCTAssertEqual(vc.children.count, 1)
        XCTAssertFalse(vc.children.first === firstChild, "different model → hosting controller is replaced")
    }

    func test_setEscapeHatch_calledTwiceWithIdenticalModel_isNoOp() {
        let vc = makeViewController()
        let model: EscapeHatchModel = .testFixture
        vc.setEscapeHatch(model, openTabCount: 0, onTapped: {}, onTabSwitcherTapped: {})
        let firstChild = vc.children.first

        vc.setEscapeHatch(model, openTabCount: 0, onTapped: {}, onTabSwitcherTapped: {})

        XCTAssertEqual(vc.children.count, 1)
        XCTAssertTrue(vc.children.first === firstChild, "identical model → short-circuit; existing hosting controller is preserved")
    }

    // MARK: - Live sections
    // Earlier stale-section caching caused relayout crashes — guard against regression by asserting numberOfSections directly.

    func test_liveSections_emptyEverything_returnsZero() throws {
        let harness = makeHarness(query: "")
        let table = try tableView(in: harness.viewController)
        table.reloadData()

        XCTAssertEqual(table.numberOfSections, 0)
    }

    func test_liveSections_queryOnly_returnsSearchRowOnly() throws {
        let harness = makeHarness(query: "x")
        let table = try tableView(in: harness.viewController)
        table.reloadData()

        XCTAssertEqual(table.numberOfSections, 1,
                       "non-empty query → always-visible Search-DuckDuckGo row")
    }

    func test_liveSections_chatsOnly_returnsChatsAndSearch() throws {
        let harness = makeHarness(query: "x")
        harness.chatViewModel.setChats(pinned: [], recent: [makeChat(id: "1")])
        let table = try tableView(in: harness.viewController)
        table.reloadData()

        XCTAssertEqual(table.numberOfSections, 2)
    }

    func test_liveSections_allThree_returnsThree() throws {
        let harness = makeHarness(query: "x")
        harness.chatViewModel.setChats(pinned: [], recent: [makeChat(id: "1")])
        harness.urlLoader.publishURLsForTesting([
            .website(url: try XCTUnwrap(URL(string: "https://example.com/")))
        ])
        let table = try tableView(in: harness.viewController)
        table.reloadData()

        XCTAssertEqual(table.numberOfSections, 3)
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
