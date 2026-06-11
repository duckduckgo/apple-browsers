//
//  DuckAISuggestionsCoordinatorTests.swift
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
import AIChatTestingUtilities
import Combine
import Core
import Suggestions
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class DuckAISuggestionsCoordinatorTests: XCTestCase {

    private struct Harness {
        let coordinator: DuckAISuggestionsCoordinator
        let chatViewModel: AIChatSuggestionsViewModel
        let urlLoader: DuckAIURLSuggestionsLoader
        let historyManager: SpyHistoryManager
        let textSubject = PassthroughSubject<String, Never>()
        let containerView = UIView()
        let parentViewController = UIViewController()
        let queryBox: QueryBox
    }

    private final class QueryBox {
        var value: String

        init(_ value: String) {
            self.value = value
        }
    }

    private func makeHarness(query: String = "",
                             syncPromoManager: SyncPromoManaging? = nil) -> Harness {
        let queryBox = QueryBox(query)
        let viewModel = AIChatSuggestionsViewModel()
        let urlLoader = DuckAIURLSuggestionsLoader(dataSource: EmptySuggestionLoadingDataSource())
        let historyManager = SpyHistoryManager()
        let chatManager = AIChatHistoryManager(
            suggestionsReader: MockAIChatSuggestionsReader(),
            aiChatSettings: MockAIChatSettingsProvider(),
            aiChatDeleter: AIChatDeleter(
                historyCleanerProvider: { _, _ in MockHistoryCleaner() },
                aiChatSyncCleaner: MockAIChatSyncCleaning()
            ),
            viewModel: viewModel,
            isFireTab: false
        )
        let coordinator = DuckAISuggestionsCoordinator(
            chatManager: chatManager,
            urlLoader: urlLoader,
            chatViewModel: viewModel,
            historyManager: historyManager,
            queryProvider: { queryBox.value },
            syncPromoManager: syncPromoManager,
            syncService: nil
        )
        return Harness(coordinator: coordinator, chatViewModel: viewModel, urlLoader: urlLoader, historyManager: historyManager, queryBox: queryBox)
    }

    private func makeCoordinator() -> DuckAISuggestionsCoordinator {
        makeHarness().coordinator
    }

    private func start(_ harness: Harness) {
        harness.coordinator.start(
            in: harness.containerView,
            parentViewController: harness.parentViewController,
            textPublisher: harness.textSubject
        )
    }

    private func makeChat(id: String = "1") -> AIChatSuggestion {
        AIChatSuggestion(id: id, title: "Chat \(id)", isPinned: false, chatId: "chat-\(id)")
    }

    private func tableView(in harness: Harness) throws -> UITableView {
        try XCTUnwrap(findTableView(in: harness.containerView))
    }

    func test_hasSettled_returnsFalseWhenOnlyChatHasSettled() {
        XCTAssertFalse(DuckAISuggestionsCoordinator.hasSettled(
            forQuery: "wp", chatLastQuery: "wp", urlLastQuery: nil
        ))
    }

    func test_hasSettled_returnsFalseWhenOnlyURLHasSettled() {
        XCTAssertFalse(DuckAISuggestionsCoordinator.hasSettled(
            forQuery: "wp", chatLastQuery: nil, urlLastQuery: "wp"
        ))
    }

    func test_hasSettled_returnsTrueWhenBothSettledForCurrentQuery() {
        XCTAssertTrue(DuckAISuggestionsCoordinator.hasSettled(
            forQuery: "wp", chatLastQuery: "wp", urlLastQuery: "wp"
        ))
    }

    func test_hasSettled_returnsFalseWhenBothSettledForStaleQuery() {
        XCTAssertFalse(DuckAISuggestionsCoordinator.hasSettled(
            forQuery: "wp", chatLastQuery: "w", urlLastQuery: "w"
        ))
    }

    func test_hasContent_whenEverythingIsEmpty_returnsFalse() {
        let harness = makeHarness()

        XCTAssertFalse(harness.coordinator.hasContent)
    }

    func test_hasContent_whenQueryIsNotEmpty_returnsTrue() {
        let harness = makeHarness(query: "ducks")

        XCTAssertTrue(harness.coordinator.hasContent)
    }

    func test_hasContent_whenChatsExist_returnsTrue() {
        let harness = makeHarness()
        harness.chatViewModel.setChats(pinned: [], recent: [makeChat()])

        XCTAssertTrue(harness.coordinator.hasContent)
    }

    func test_hasContent_whenURLSuggestionsExist_returnsTrue() throws {
        let harness = makeHarness()
        harness.urlLoader.publishURLsForTesting([
            .website(url: try XCTUnwrap(URL(string: "https://example.com/")))
        ])

        XCTAssertTrue(harness.coordinator.hasContent)
    }

    func test_start_installsSuggestionsViewController() {
        let harness = makeHarness()

        start(harness)

        XCTAssertEqual(harness.parentViewController.children.count, 1)
        XCTAssertTrue(harness.parentViewController.children.first is DuckAISuggestionsViewController)
        XCTAssertEqual(harness.containerView.subviews.count, 1)
    }

    func test_start_whenCalledTwice_installsOnlyOnce() {
        let harness = makeHarness()

        start(harness)
        start(harness)

        XCTAssertEqual(harness.parentViewController.children.count, 1)
        XCTAssertEqual(harness.containerView.subviews.count, 1)
    }

    func test_setEscapeHatch_afterStart_forwardsToInstalledViewController() throws {
        let harness = makeHarness()
        start(harness)

        harness.coordinator.setEscapeHatch(.testFixture)

        XCTAssertNotNil(try tableView(in: harness).tableHeaderView)
    }

    func test_setAdditionalTopInset_afterStart_forwardsToInstalledViewController() throws {
        let harness = makeHarness()
        start(harness)

        harness.coordinator.setAdditionalTopInset(8)

        XCTAssertEqual(try tableView(in: harness).contentInset.top, 20, accuracy: 0.5)
    }

    func test_setIsVisibleContent_afterStart_forwardsToInstalledViewController() {
        let syncPromoManager = MockSyncPromoManager()
        syncPromoManager.shouldPresentForTouchpoint[.aiChat] = true
        let harness = makeHarness(syncPromoManager: syncPromoManager)
        start(harness)

        harness.coordinator.setIsVisibleContent(true)

        XCTAssertEqual(syncPromoManager.recordedImpressions, [.aiChat])
    }

    func test_tearDown_removesInstalledViewControllerAndClearsContent() throws {
        let harness = makeHarness()
        harness.chatViewModel.setChats(pinned: [], recent: [makeChat()])
        harness.urlLoader.publishURLsForTesting([
            .website(url: try XCTUnwrap(URL(string: "https://example.com/")))
        ])
        start(harness)
        XCTAssertTrue(harness.coordinator.hasContent)

        harness.coordinator.tearDown()

        XCTAssertTrue(harness.parentViewController.children.isEmpty)
        XCTAssertTrue(harness.containerView.subviews.isEmpty)
        XCTAssertFalse(harness.coordinator.hasContent)
    }

    func test_duckAISuggestionsDidSelectChat_forwardsToDelegate() {
        let coordinator = makeCoordinator()
        let delegate = MockDuckAISuggestionsCoordinatorDelegate()
        coordinator.delegate = delegate
        let chat = AIChatSuggestion(id: "1", title: "Chat 1", isPinned: false, chatId: "chat-1")

        coordinator.duckAISuggestionsDidSelectChat(chat)

        XCTAssertEqual(delegate.selectedChat?.chatId, "chat-1")
    }

    func test_duckAISuggestionsDidSelectURL_forwardsToDelegate() throws {
        let coordinator = makeCoordinator()
        let delegate = MockDuckAISuggestionsCoordinatorDelegate()
        coordinator.delegate = delegate
        let suggestion = Suggestion.website(url: try XCTUnwrap(URL(string: "https://example.com/")))

        coordinator.duckAISuggestionsDidSelectURL(suggestion)

        XCTAssertEqual(delegate.selectedURLSuggestion?.url?.host, "example.com")
    }

    func test_duckAISuggestionsDidSelectSearchDuckDuckGo_forwardsToDelegate() {
        let coordinator = makeCoordinator()
        let delegate = MockDuckAISuggestionsCoordinatorDelegate()
        coordinator.delegate = delegate

        coordinator.duckAISuggestionsDidSelectSearchDuckDuckGo(query: "ducks")

        XCTAssertEqual(delegate.selectedSearchQuery, "ducks")
    }

    func test_duckAISuggestionsDidRequestSyncSetup_forwardsToDelegate() {
        let coordinator = makeCoordinator()
        let delegate = MockDuckAISuggestionsCoordinatorDelegate()
        coordinator.delegate = delegate

        coordinator.duckAISuggestionsDidRequestSyncSetup()

        XCTAssertEqual(delegate.syncSetupRequestCount, 1)
    }

    func test_duckAISuggestionsDidRequestURLDeletion_deletesHistoryForURL() async throws {
        let harness = makeHarness()
        let url = try XCTUnwrap(URL(string: "https://example.com/page"))
        harness.historyManager.deleteExpectation = expectation(description: "deleteHistoryForURL called")

        harness.coordinator.duckAISuggestionsDidRequestURLDeletion(.historyEntry(title: "Example", url: url, score: 1))

        await fulfillment(of: [harness.historyManager.deleteExpectation!], timeout: 1)
        XCTAssertEqual(harness.historyManager.deletedURLs, [url])
    }
}

@MainActor
private final class MockDuckAISuggestionsCoordinatorDelegate: DuckAISuggestionsCoordinatorDelegate {
    var selectedChat: AIChatSuggestion?
    var selectedURLSuggestion: Suggestion?
    var selectedSearchQuery: String?
    var syncSetupRequestCount = 0

    func duckAISuggestionsDidSelectChat(_ chat: AIChatSuggestion) {
        selectedChat = chat
    }

    func duckAISuggestionsDidSelectURL(_ suggestion: Suggestion) {
        selectedURLSuggestion = suggestion
    }

    func duckAISuggestionsDidSelectSearchDuckDuckGo(query: String) {
        selectedSearchQuery = query
    }

    func duckAISuggestionsDidDeleteURL(_ suggestion: Suggestion) {}

    func duckAISuggestionsDidRequestSyncSetup() {
        syncSetupRequestCount += 1
    }
}

@MainActor
private final class MockAIChatSuggestionsReader: AIChatSuggestionsReading {
    var maxHistoryCount: Int = 10

    func fetchSuggestions(query: String?, maxChats: Int) async -> (pinned: [AIChatSuggestion], recent: [AIChatSuggestion]) {
        ([], [])
    }

    func tearDown() {}
}

private final class MockHistoryCleaner: HistoryCleaning {
    func cleanAIChatHistory() async -> Result<Void, Error> { .success(()) }
    func deleteAIChat(chatID: String) async -> Result<Void, Error> { .success(()) }
}

private final class SpyHistoryManager: MockHistoryManager {
    var deletedURLs: [URL] = []
    var deleteExpectation: XCTestExpectation?

    override func deleteHistoryForURL(_ url: URL) async {
        deletedURLs.append(url)
        deleteExpectation?.fulfill()
    }
}

@MainActor
private final class MockSyncPromoManager: SyncPromoManaging {
    var shouldPresentForTouchpoint: [SyncPromoManager.Touchpoint: Bool] = [:]
    var recordedImpressions: [SyncPromoManager.Touchpoint] = []

    func shouldPresentPromoFor(_ touchpoint: SyncPromoManager.Touchpoint, count: Int) -> Bool {
        shouldPresentForTouchpoint[touchpoint] ?? false
    }

    func markPromoHandledFor(_ touchpoint: SyncPromoManager.Touchpoint) {}

    func recordImpressionFor(_ touchpoint: SyncPromoManager.Touchpoint) {
        recordedImpressions.append(touchpoint)
    }

    func dismissPromoFor(_ touchpoint: SyncPromoManager.Touchpoint, reason: SyncPromoManager.DismissalReason) {}

    func resetPromos() {}
}

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

private func findTableView(in view: UIView?) -> UITableView? {
    guard let view else { return nil }
    if let tableView = view as? UITableView {
        return tableView
    }
    for subview in view.subviews {
        if let tableView = findTableView(in: subview) {
            return tableView
        }
    }
    return nil
}
