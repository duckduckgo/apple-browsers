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
import Core
import Suggestions
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class DuckAISuggestionsViewControllerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        PixelFiringMock.tearDown()
    }

    override func tearDown() {
        PixelFiringMock.tearDown()
        super.tearDown()
    }

    private struct Harness {
        let viewController: DuckAISuggestionsViewController
        let chatViewModel: AIChatSuggestionsViewModel
        let urlLoader: DuckAIURLSuggestionsLoader
    }

    private func makeHarness(query: String = "",
                             layoutConfiguration: DuckAISuggestionsViewController.LayoutConfiguration = .standard,
                             syncPromoManager: SyncPromoManaging? = nil) -> Harness {
        let viewModel = AIChatSuggestionsViewModel()
        let loader = DuckAIURLSuggestionsLoader(dataSource: EmptySuggestionLoadingDataSource())
        let syncPromoViewModel = syncPromoManager.map {
            AIChatSyncPromoViewModel(syncPromoManager: $0, pixelFiring: PixelFiringMock.self)
        }
        let vc = DuckAISuggestionsViewController(
            chatViewModel: viewModel,
            urlLoader: loader,
            queryProvider: { query },
            layoutConfiguration: layoutConfiguration,
            syncService: nil,
            syncPromoViewModel: syncPromoViewModel
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

        vc.setEscapeHatch(.testFixture)

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

    func test_unifiedToggleInputLayout_matchesSearchHorizontalInset() throws {
        let vc = makeViewController(layoutConfiguration: .unifiedToggleInput)
        vc.view.frame = CGRect(x: 0, y: 0, width: 430, height: 800)
        vc.view.layoutIfNeeded()

        let table = try tableView(in: vc)
        vc.setEscapeHatch(.testFixture)
        vc.view.layoutIfNeeded()

        let header = try XCTUnwrap(table.tableHeaderView)
        let hatchView = try XCTUnwrap(header.subviews.first)
        let hatchFrame = hatchView.convert(hatchView.bounds, to: vc.view)
        let expectedTableInset: CGFloat = 0
        let expectedHatchInset: CGFloat = 16

        XCTAssertEqual(table.frame.minX, expectedTableInset, accuracy: 0.5)
        XCTAssertEqual(vc.view.bounds.width - table.frame.maxX, expectedTableInset, accuracy: 0.5)
        XCTAssertEqual(header.bounds.width, table.bounds.width, accuracy: 0.5)
        XCTAssertEqual(hatchFrame.minX, expectedHatchInset, accuracy: 0.5)
        XCTAssertEqual(vc.view.bounds.width - hatchFrame.maxX, expectedHatchInset, accuracy: 0.5)
    }

    func test_setEscapeHatch_withNil_removesTableHeaderView() throws {
        let vc = makeViewController()
        vc.setEscapeHatch(.testFixture)
        XCTAssertNotNil(try tableView(in: vc).tableHeaderView)

        vc.setEscapeHatch(nil)

        XCTAssertNil(try tableView(in: vc).tableHeaderView)
        XCTAssertTrue(vc.children.isEmpty, "hatch hosting controller should be removed from children")
    }

    func test_setEscapeHatch_calledTwiceWithDifferentModels_replacesExistingHostingController() {
        // `EscapeHatchModel` is a reference type — each `.testFixture` is a distinct instance.
        let vc = makeViewController()
        vc.setEscapeHatch(.testFixture)
        let firstChild = vc.children.first

        vc.setEscapeHatch(.testFixture)

        XCTAssertEqual(vc.children.count, 1)
        XCTAssertFalse(vc.children.first === firstChild, "different model → hosting controller is replaced")
    }

    func test_setEscapeHatch_calledTwiceWithIdenticalModel_isNoOp() {
        let vc = makeViewController()
        let model: EscapeHatchModel = .testFixture
        vc.setEscapeHatch(model)
        let firstChild = vc.children.first

        vc.setEscapeHatch(model)

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

    // MARK: - Sync promo header

    func test_syncPromo_whenManagerShouldPresent_installsTableHeaderViewWithPromo() throws {
        let mockManager = MockSyncPromoManager()
        mockManager.shouldPresentForTouchpoint[.aiChat] = true
        let harness = makeHarness(syncPromoManager: mockManager)
        harness.viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        harness.viewController.view.layoutIfNeeded()

        let table = try tableView(in: harness.viewController)

        let header = try XCTUnwrap(table.tableHeaderView, "promo eligibility → table header is installed")
        XCTAssertGreaterThan(header.bounds.height, 0)
        XCTAssertEqual(harness.viewController.children.count, 1, "promo hosting controller is added as a child")
    }

    func test_syncPromo_withEscapeHatch_usesExpectedInterCardSpacing() throws {
        let mockManager = MockSyncPromoManager()
        mockManager.shouldPresentForTouchpoint[.aiChat] = true
        let harness = makeHarness(syncPromoManager: mockManager)
        harness.viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        harness.viewController.view.layoutIfNeeded()

        harness.viewController.setEscapeHatch(.testFixture)
        harness.viewController.view.layoutIfNeeded()

        let table = try tableView(in: harness.viewController)
        let header = try XCTUnwrap(table.tableHeaderView)
        XCTAssertEqual(header.subviews.count, 2)

        let hatchFrame = header.subviews[0].frame
        let promoFrame = header.subviews[1].frame

        XCTAssertEqual(promoFrame.minY - hatchFrame.maxY, 20, accuracy: 0.5)
    }

    func test_syncPromo_whenManagerDeclinesToPresent_doesNotInstallHeader() throws {
        let mockManager = MockSyncPromoManager()
        mockManager.shouldPresentForTouchpoint[.aiChat] = false
        let harness = makeHarness(syncPromoManager: mockManager)
        harness.viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        harness.viewController.view.layoutIfNeeded()

        let table = try tableView(in: harness.viewController)

        XCTAssertNil(table.tableHeaderView)
        XCTAssertTrue(harness.viewController.children.isEmpty)
    }

    func test_syncPromo_whenQueryActive_promoIsRemovedFromHeader() throws {
        let mockManager = MockSyncPromoManager()
        mockManager.shouldPresentForTouchpoint[.aiChat] = true
        let harness = makeHarness(syncPromoManager: mockManager)
        harness.viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        harness.viewController.view.layoutIfNeeded()

        XCTAssertNotNil(try tableView(in: harness.viewController).tableHeaderView,
                        "precondition: promo is initially visible")

        harness.viewController.setQueryActive(true)

        XCTAssertNil(try tableView(in: harness.viewController).tableHeaderView,
                     "typing hides the entire promo header")
        XCTAssertTrue(harness.viewController.children.isEmpty,
                      "promo hosting controller is removed when typing starts")
    }

    func test_syncPromo_recordsExactlyOneImpressionPerVCLifetime() throws {
        let mockManager = MockSyncPromoManager()
        mockManager.shouldPresentForTouchpoint[.aiChat] = true
        let harness = makeHarness(syncPromoManager: mockManager)
        harness.viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        harness.viewController.view.layoutIfNeeded()
        harness.viewController.setIsVisibleContent(true)

        XCTAssertEqual(mockManager.recordedImpressions, [.aiChat])

        harness.viewController.setQueryActive(true)
        harness.viewController.setQueryActive(false)
        harness.viewController.view.layoutIfNeeded()

        XCTAssertEqual(mockManager.recordedImpressions, [.aiChat])
    }

    func test_syncPromo_doesNotRecordImpressionWhilePageIsInactive() throws {
        let mockManager = MockSyncPromoManager()
        mockManager.shouldPresentForTouchpoint[.aiChat] = true
        let harness = makeHarness(syncPromoManager: mockManager)
        harness.viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        harness.viewController.view.layoutIfNeeded()

        XCTAssertNotNil(try tableView(in: harness.viewController).tableHeaderView)
        XCTAssertEqual(mockManager.recordedImpressions, [])
    }

    func test_syncPromo_recordsImpressionWhenPageBecomesActiveAfterInstall() throws {
        let mockManager = MockSyncPromoManager()
        mockManager.shouldPresentForTouchpoint[.aiChat] = true
        let harness = makeHarness(syncPromoManager: mockManager)
        harness.viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        harness.viewController.view.layoutIfNeeded()
        XCTAssertEqual(mockManager.recordedImpressions, [])

        harness.viewController.setIsVisibleContent(true)

        XCTAssertEqual(mockManager.recordedImpressions, [.aiChat])
    }

    func test_syncPromo_doesNotRecordWhenPromoReappearsAfterPageBecomesInactive() throws {
        let mockManager = MockSyncPromoManager()
        mockManager.shouldPresentForTouchpoint[.aiChat] = true
        let harness = makeHarness(syncPromoManager: mockManager)
        harness.viewController.view.frame = CGRect(x: 0, y: 0, width: 390, height: 600)
        harness.viewController.view.layoutIfNeeded()

        harness.viewController.setQueryActive(true)
        harness.viewController.setIsVisibleContent(true)
        harness.viewController.setIsVisibleContent(false)
        harness.viewController.setQueryActive(false)
        harness.viewController.view.layoutIfNeeded()

        XCTAssertNotNil(try tableView(in: harness.viewController).tableHeaderView)
        XCTAssertEqual(mockManager.recordedImpressions, [])
    }
}

// MARK: - Test doubles

private extension EscapeHatchModel {
    static var testFixture: EscapeHatchModel {
        .preview(title: "Test tab",
                 subtitle: "example.com",
                 tabType: .regular,
                 domain: "example.com",
                 targetTab: Tab(fireTab: false),
                 tabCount: 1)
    }
}

private final class MockSyncPromoManager: SyncPromoManaging {
    var shouldPresentForTouchpoint: [SyncPromoManager.Touchpoint: Bool] = [:]
    var handledTouchpoints: [SyncPromoManager.Touchpoint] = []
    var recordedImpressions: [SyncPromoManager.Touchpoint] = []
    var dismissedTouchpoints: [(SyncPromoManager.Touchpoint, SyncPromoManager.DismissalReason)] = []

    func shouldPresentPromoFor(_ touchpoint: SyncPromoManager.Touchpoint, count: Int) -> Bool {
        shouldPresentForTouchpoint[touchpoint] ?? false
    }

    func markPromoHandledFor(_ touchpoint: SyncPromoManager.Touchpoint) {
        handledTouchpoints.append(touchpoint)
        shouldPresentForTouchpoint[touchpoint] = false
    }

    func recordImpressionFor(_ touchpoint: SyncPromoManager.Touchpoint) {
        recordedImpressions.append(touchpoint)
    }

    func dismissPromoFor(_ touchpoint: SyncPromoManager.Touchpoint, reason: SyncPromoManager.DismissalReason) {
        dismissedTouchpoints.append((touchpoint, reason))
        markPromoHandledFor(touchpoint)
    }

    func resetPromos() {
        shouldPresentForTouchpoint.removeAll()
        handledTouchpoints.removeAll()
        recordedImpressions.removeAll()
        dismissedTouchpoints.removeAll()
    }
}
