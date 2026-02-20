//
//  HistoryViewActionsHandlerTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AppKit
import Clocks
import History
import HistoryView
import PixelKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

private struct FirePixelCall: Equatable {
    static func == (lhs: FirePixelCall, rhs: FirePixelCall) -> Bool {
        guard lhs.pixel.name == rhs.pixel.name, lhs.pixel.parameters == rhs.pixel.parameters else {
            return false
        }

        switch (lhs.frequency, rhs.frequency) {
        case (.standard, .standard),
            (.legacyInitial, .legacyInitial),
            (.uniqueByName, .uniqueByName),
            (.uniqueByNameAndParameters, .uniqueByNameAndParameters),
            (.legacyDaily, .legacyDaily),
            (.daily, .daily),
            (.legacyDailyAndCount, .legacyDailyAndCount),
            (.dailyAndCount, .dailyAndCount),
            (.dailyAndStandard, .dailyAndStandard):
            return true
        default:
            return false
        }
    }

    let pixel: HistoryViewPixel
    let frequency: PixelKit.Frequency

    init(_ pixel: HistoryViewPixel, _ frequency: PixelKit.Frequency) {
        self.pixel = pixel
        self.frequency = frequency
    }
}

final class HistoryViewActionsHandlerTests: XCTestCase {

    var actionsHandler: HistoryViewActionsHandler!
    var dataProvider: CapturingHistoryViewDataProvider!
    var dialogPresenter: CapturingHistoryViewDeleteDialogPresenter!
    var contextMenuPresenter: CapturingContextMenuPresenter!
    var tabOpener: CapturingHistoryViewTabOpener!
    var bookmarksHandler: CapturingHistoryViewBookmarksHandler!
    var pasteboard: NSPasteboard!
    fileprivate var firePixelCalls: [FirePixelCall] = []

    override func setUp() async throws {
        dataProvider = CapturingHistoryViewDataProvider()
        dialogPresenter = CapturingHistoryViewDeleteDialogPresenter()
        contextMenuPresenter = CapturingContextMenuPresenter()
        tabOpener = CapturingHistoryViewTabOpener()
        bookmarksHandler = CapturingHistoryViewBookmarksHandler()
        pasteboard = NSPasteboard.test()
        firePixelCalls = []
        actionsHandler = HistoryViewActionsHandler(
            dataProvider: dataProvider,
            dialogPresenter: dialogPresenter,
            tabOpener: tabOpener,
            bookmarksHandler: bookmarksHandler,
            firePixel: { self.firePixelCalls.append(.init($0, $1)) },
            pasteboard: pasteboard
        )
    }

    override func tearDown() {
        actionsHandler = nil
        bookmarksHandler = nil
        contextMenuPresenter = nil
        dataProvider = nil
        dialogPresenter = nil
        tabOpener = nil
        pasteboard = nil
        firePixelCalls = []
    }

    // MARK: - showDeleteDialogForQuery

    func testWhenDataProviderIsNilThenShowDeleteDialogForQueryReturnsNoAction() async {
        dataProvider = nil
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .rangeFilter(.all))
        XCTAssertEqual(dialogResponse, .noAction)
    }

    func testWhenDataProviderHasNoVisitsForRangeThenShowDeleteDialogForQueryReturnsNoAction() async {
        dataProvider.visitsMatchingQuery = { _ in return [] }
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .rangeFilter(.all))
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dataProvider.burnVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dialogResponse, .noAction)
    }

    @MainActor
    func testWhenDeleteDialogIsCancelledThenShowDeleteDialogForQueryReturnsNoAction() async {
        let data = dataProvider.configureWithGeneratedTestData(domainsCount: 5, visitsPerDomain: 20)
        dataProvider.visitsMatchingQuery = { _ in data.visits }
        dialogPresenter.deleteDialogResponse = .noAction
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .rangeFilter(.all))
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dataProvider.burnVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dialogResponse, .noAction)
    }

    @MainActor
    func testWhenDeleteDialogIsAcceptedWithBurningThenShowDeleteDialogForQueryPerformsBurningAndReturnsDeleteAction() async {
        let data = dataProvider.configureWithGeneratedTestData(domainsCount: 5, visitsPerDomain: 20)
        dataProvider.visitsMatchingQuery = { _ in data.visits }
        dialogPresenter.deleteDialogResponse = .burn
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .rangeFilter(.all))
        // With Fire Dialog always on, it handles the burning and we just refresh data
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dataProvider.burnVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dataProvider.resetCacheCallCount, 1)
        XCTAssertEqual(dataProvider.clearChatHistoryCallCount, 0)
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 1)
        XCTAssertEqual(dialogResponse, .delete)

        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.multipleItemsDeleted(.all, burn: true), .dailyAndStandard)
        ])
    }

    @MainActor
    func testWhenDeleteDialogIsAcceptedWithChatHistoryBurningThenShowDeleteDialogForQueryClearsChatHistory() async {
        let data = dataProvider.configureWithGeneratedTestData(domainsCount: 5, visitsPerDomain: 20)
        dataProvider.visitsMatchingQuery = { _ in data.visits }
        dialogPresenter.deleteDialogResponse = .burn
        _ = await actionsHandler.showDeleteDialog(for: .rangeFilter(.all))
        // With Fire Dialog always on, it handles chat history clearing internally
        XCTAssertEqual(dataProvider.clearChatHistoryCallCount, 0)
        XCTAssertEqual(dataProvider.resetCacheCallCount, 1)
    }

    @MainActor
    func testWhenDeleteDialogIsAcceptedWithoutBurningThenShowDeleteDialogForQueryPerformsDeletionAndReturnsDeleteAction() async {
        let data = dataProvider.configureWithGeneratedTestData(domainsCount: 5, visitsPerDomain: 20)
        dataProvider.visitsMatchingQuery = { _ in data.visits }
        dialogPresenter.deleteDialogResponse = .delete
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .rangeFilter(.all))
        // With Fire Dialog always on, it handles the deletion and we just refresh data
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dataProvider.burnVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dataProvider.resetCacheCallCount, 1)
        XCTAssertEqual(dataProvider.clearChatHistoryCallCount, 0)
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 1)
        XCTAssertEqual(dialogResponse, .delete)

        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.multipleItemsDeleted(.all, burn: false), .dailyAndStandard)
        ])
    }

    @MainActor
    func testWhenDeleteDialogIsAcceptedWithChatHistoryDeletionThenShowDeleteDialogForQueryClearsChatHistory() async {
        let data = dataProvider.configureWithGeneratedTestData(domainsCount: 5, visitsPerDomain: 20)
        dataProvider.visitsMatchingQuery = { _ in data.visits }
        dialogPresenter.deleteDialogResponse = .delete
        _ = await actionsHandler.showDeleteDialog(for: .rangeFilter(.all))
        // With Fire Dialog always on, it handles chat history clearing internally
        XCTAssertEqual(dataProvider.clearChatHistoryCallCount, 0)
        XCTAssertEqual(dataProvider.resetCacheCallCount, 1)
    }

    @MainActor
    func testThatShowDeleteDialogForNonRangeQueryNotMatchingAllVisitsDoesNotAdjustQueryToAllRange() async throws {
        let data = dataProvider.configureWithGeneratedTestData(domainsCount: 5, visitsPerDomain: 20)
        dataProvider.visitsMatchingQuery = { query in
            switch query {
            case .searchTerm("hello"):
                return Array(data.visits.prefix(upTo: 10))
            case .rangeFilter(.all):
                return data.visits
            default:
                XCTFail("Unexpected query: \(query)")
                return []
            }
        }
        dialogPresenter.deleteDialogResponse = .delete
        _ = await actionsHandler.showDeleteDialog(for: .searchTerm("hello"))
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 1)
        let call = try XCTUnwrap(dialogPresenter.showDeleteDialogCalls.first)
        // For non-all queries that don't match all items, deleteMode should not be `.all`
        XCTAssertNotEqual(call.query, .rangeFilter(.all))

        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.multipleItemsDeleted(.searchTerm, burn: false), .dailyAndStandard)
        ])
    }

    @MainActor
    func testThatShowDeleteDialogForNonRangeQueryMatchingAllVisitsAdjustsQueryToAllRange() async throws {
        let data = dataProvider.configureWithGeneratedTestData(domainsCount: 5, visitsPerDomain: 20)
        dataProvider.visitsMatchingQuery = { _ in data.visits }
        dialogPresenter.deleteDialogResponse = .delete
        _ = await actionsHandler.showDeleteDialog(for: .searchTerm("hello"))
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 1)
        let call = try XCTUnwrap(dialogPresenter.showDeleteDialogCalls.first)
        XCTAssertEqual(call.query, .rangeFilter(.all))

        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.multipleItemsDeleted(.all, burn: false), .dailyAndStandard)
        ])
    }

    // MARK: - showDeleteDialogForEntries

    func testWhenDataProviderIsNilThenShowDeleteDialogForEntriesReturnsNoAction() async throws {
        dataProvider = nil
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
            .init(uuid: "efgh", url: try XCTUnwrap("https://domain.com".url), date: Date())
        ]
        let dialogResponse = await actionsHandler.showDeleteDialog(for: identifiers.map(\.description))
        XCTAssertEqual(dialogResponse, .noAction)

        XCTAssertEqual(firePixelCalls, [])
    }

    func testWhenIdentifiersArrayIsEmptyNilThenShowDeleteDialogForEntriesReturnsNoAction() async {
        dataProvider = nil
        let dialogResponse = await actionsHandler.showDeleteDialog(for: [])
        XCTAssertEqual(dialogResponse, .noAction)

        XCTAssertEqual(firePixelCalls, [])
    }

    func testWhenSingleIdentifierIsPassedThenShowDeleteDialogForQueryPerformsDeletionWithoutShowingDialogAndReturnsDeleteAction() async throws {
        let identifier = VisitIdentifier(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date())
        let dialogResponse = await actionsHandler.showDeleteDialog(for: [identifier.description])
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 0)
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls, [.visits([identifier])])
        XCTAssertEqual(dataProvider.burnVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dataProvider.clearChatHistoryCallCount, 0)
        XCTAssertEqual(dialogResponse, .delete)

        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.singleItemDeleted, .dailyAndStandard)
        ])
    }

    @MainActor
    func testWhenMultipleIdentifiersArePassedAndDeleteDialogIsCancelledThenShowDeleteDialogForQueryReturnsNoAction() async throws {
        let data = dataProvider.configureWithGeneratedTestData(domainsCount: 2, visitsPerDomain: 1)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
            .init(uuid: "efgh", url: try XCTUnwrap("https://domain.com".url), date: Date())
        ]
        dataProvider.visitsMatchingQuery = { _ in data.visits }
        dialogPresenter.deleteDialogResponse = .noAction
        let dialogResponse = await actionsHandler.showDeleteDialog(for: identifiers.map(\.description))
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 1)
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dataProvider.burnVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dataProvider.clearChatHistoryCallCount, 0)
        XCTAssertEqual(dialogResponse, .noAction)

        XCTAssertEqual(firePixelCalls, [])
    }

    @MainActor
    func testWhenMultipleIdentifiersArePassedAndDeleteDialogIsAcceptedWithBurningThenShowDeleteDialogForQueryReturnsDeleteAction() async throws {
        let data = dataProvider.configureWithGeneratedTestData(domainsCount: 2, visitsPerDomain: 1)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
            .init(uuid: "efgh", url: try XCTUnwrap("https://domain.com".url), date: Date())
        ]
        dataProvider.visitsMatchingQuery = { _ in data.visits }
        dialogPresenter.deleteDialogResponse = .burn
        let dialogResponse = await actionsHandler.showDeleteDialog(for: identifiers.map(\.description))
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 1)
        // With Fire Dialog always on, it handles the burning and we just refresh data
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dataProvider.burnVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dataProvider.resetCacheCallCount, 1)
        XCTAssertEqual(dataProvider.clearChatHistoryCallCount, 0)
        XCTAssertEqual(dialogResponse, .delete)

        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.multipleItemsDeleted(.multiSelect, burn: true), .dailyAndStandard)
        ])
    }

    @MainActor
    func testWhenMultipleIdentifiersArePassedAndDeleteDialogIsAcceptedWithoutBurningThenShowDeleteDialogForQueryReturnsDeleteAction() async throws {
        let data = dataProvider.configureWithGeneratedTestData(domainsCount: 2, visitsPerDomain: 1)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
            .init(uuid: "efgh", url: try XCTUnwrap("https://domain.com".url), date: Date())
        ]
        dataProvider.visitsMatchingQuery = { _ in data.visits }
        dialogPresenter.deleteDialogResponse = .delete
        let dialogResponse = await actionsHandler.showDeleteDialog(for: identifiers.map(\.description))
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 1)
        // With Fire Dialog always on, it handles the deletion and we just refresh data
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dataProvider.burnVisitsMatchingQueryCalls, [])
        XCTAssertEqual(dataProvider.resetCacheCallCount, 1)
        XCTAssertEqual(dataProvider.clearChatHistoryCallCount, 0)
        XCTAssertEqual(dialogResponse, .delete)

        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.multipleItemsDeleted(.multiSelect, burn: false), .dailyAndStandard)
        ])
    }

    // MARK: - showContextMenu

    func testWhenShowContextMenuIsCalledWithNoValidIdentifiersThenItDoesNotShowMenuAndReturnsNoAction() async {
        let response1 = await actionsHandler.showContextMenu(for: [], using: contextMenuPresenter)
        let response2 = await actionsHandler.showContextMenu(for: ["invalid-identifier"], using: contextMenuPresenter)
        XCTAssertEqual(response1, .noAction)
        XCTAssertEqual(response2, .noAction)
        XCTAssertEqual(contextMenuPresenter.showContextMenuCalls.count, 0)
    }

    // MARK: - copy action via injected pasteboard

    @MainActor
    func testCopyActionUsesInjectedPasteboard() async throws {
        let url = try XCTUnwrap("https://copy.me".url)
        let identifiers: [VisitIdentifier] = [ .init(uuid: "id", url: url, date: Date()) ]

        let expectation = expectation(description: "Copy action completed")
        contextMenuPresenter.onShowContextMenu = { menu in
            // copy item index is 6 for single selection
            menu.performActionForItem(at: 6)
            expectation.fulfill()
        }

        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(pasteboard.url, url)
    }

    func testWhenShowContextMenuIsCalledForSingleItemThenItShowsMenuForSingleItem() async throws {
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
        ]
        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        XCTAssertEqual(contextMenuPresenter.showContextMenuCalls.count, 1)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)

        XCTAssertEqual(menu.items.count, 11)

        XCTAssertEqual(menu.items[0].title, UserText.openInNewTab)
        XCTAssertEqual(menu.items[0].accessibilityIdentifier(), "HistoryView.openInNewTab")
        XCTAssertEqual(menu.items[1].title, UserText.openInNewWindow)
        XCTAssertEqual(menu.items[1].accessibilityIdentifier(), "HistoryView.openInNewWindow")
        XCTAssertEqual(menu.items[2].title, UserText.openInNewFireWindow)
        XCTAssertEqual(menu.items[2].accessibilityIdentifier(), "HistoryView.openInNewFireWindow")
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        XCTAssertEqual(menu.items[4].title, UserText.showAllHistoryFromThisSite)
        XCTAssertEqual(menu.items[4].accessibilityIdentifier(), "HistoryView.showAllHistoryFromThisSite")
        XCTAssertTrue(menu.items[5].isSeparatorItem)
        XCTAssertEqual(menu.items[6].title, UserText.copyLink)
        XCTAssertEqual(menu.items[6].accessibilityIdentifier(), "HistoryView.copyLink")
        XCTAssertEqual(menu.items[7].title, UserText.addToBookmarks)
        XCTAssertEqual(menu.items[7].accessibilityIdentifier(), "HistoryView.addBookmark")
        XCTAssertEqual(menu.items[8].title, UserText.addToFavorites)
        XCTAssertEqual(menu.items[8].accessibilityIdentifier(), "HistoryView.addFavorite")
        XCTAssertTrue(menu.items[9].isSeparatorItem)
        XCTAssertEqual(menu.items[10].title, UserText.delete)
        XCTAssertEqual(menu.items[10].accessibilityIdentifier(), "HistoryView.delete")
    }

    func testWhenURLIsBookmaredThenShowContextMenuPresentsContextMenuWithoutBookmarkItem() async throws {
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
        ]
        bookmarksHandler.isUrlBookmarked = { _ in true }
        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        XCTAssertEqual(contextMenuPresenter.showContextMenuCalls.count, 1)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)

        XCTAssertEqual(menu.items.count, 10)
        XCTAssertFalse(menu.items.compactMap({ $0.accessibilityIdentifier() }).contains("HistoryView.addBookmark"))
        XCTAssertFalse(menu.items.map(\.title).contains(UserText.addToBookmarks))
    }

    func testWhenURLIsFavoritedThenShowContextMenuPresentsContextMenuWithoutBookmarkAndFavoriteItem() async throws {
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
        ]
        bookmarksHandler.isUrlBookmarked = { _ in true }
        bookmarksHandler.isUrlFavorited = { _ in true }
        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        XCTAssertEqual(contextMenuPresenter.showContextMenuCalls.count, 1)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)

        XCTAssertEqual(menu.items.count, 9)
        let ids = menu.items.compactMap({ $0.accessibilityIdentifier() })
        XCTAssertFalse(ids.contains("HistoryView.addBookmark"))
        XCTAssertFalse(ids.contains("HistoryView.addFavorite"))
        XCTAssertFalse(menu.items.map(\.title).contains(UserText.addToBookmarks))
        XCTAssertFalse(menu.items.map(\.title).contains(UserText.addToFavorites))
    }

    func testWhenShowContextMenuIsCalledForMultipleItemsThenItShowsMenuForMultipleItems() async throws {
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
            .init(uuid: "efgh", url: try XCTUnwrap("https://example2.com".url), date: Date()),
            .init(uuid: "ijkl", url: try XCTUnwrap("https://example3.com".url), date: Date()),
        ]
        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        XCTAssertEqual(contextMenuPresenter.showContextMenuCalls.count, 1)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)

        XCTAssertEqual(menu.items.count, 7)

        XCTAssertEqual(menu.items[0].title, UserText.openAllInNewTabs)
        XCTAssertEqual(menu.items[0].accessibilityIdentifier(), "HistoryView.openInNewTab")
        XCTAssertEqual(menu.items[1].title, UserText.openAllTabsInNewWindow)
        XCTAssertEqual(menu.items[1].accessibilityIdentifier(), "HistoryView.openInNewWindow")
        XCTAssertEqual(menu.items[2].title, UserText.openAllInNewFireWindow)
        XCTAssertEqual(menu.items[2].accessibilityIdentifier(), "HistoryView.openInNewFireWindow")
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        XCTAssertEqual(menu.items[4].title, UserText.addAllToBookmarks)
        XCTAssertEqual(menu.items[4].accessibilityIdentifier(), "HistoryView.addBookmark")
        XCTAssertTrue(menu.items[5].isSeparatorItem)
        XCTAssertEqual(menu.items[6].title, UserText.delete)
        XCTAssertEqual(menu.items[6].accessibilityIdentifier(), "HistoryView.delete")
    }

    func testWhenSomeURLsAreBookmaredThenShowContextMenuForMultipleItemsPresentsContextMenuWithBookmarksItem() async throws {
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
            .init(uuid: "efgh", url: try XCTUnwrap("https://example2.com".url), date: Date()),
            .init(uuid: "ijkl", url: try XCTUnwrap("https://example3.com".url), date: Date()),
        ]
        bookmarksHandler.isUrlBookmarked = { url in
            return url == "https://example.com".url
        }
        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        XCTAssertEqual(contextMenuPresenter.showContextMenuCalls.count, 1)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)

        XCTAssertEqual(menu.items.count, 7)
        XCTAssertTrue(menu.items.compactMap({ $0.accessibilityIdentifier() }).contains("HistoryView.addBookmark"))
        XCTAssertTrue(menu.items.map(\.title).contains(UserText.addAllToBookmarks))
    }

    func testWhenAllURLsAreBookmaredThenShowContextMenuForMultipleItemsPresentsContextMenuWithoutBookmarksItem() async throws {
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
            .init(uuid: "efgh", url: try XCTUnwrap("https://example2.com".url), date: Date()),
            .init(uuid: "ijkl", url: try XCTUnwrap("https://example3.com".url), date: Date()),
        ]
        bookmarksHandler.isUrlBookmarked = { _ in true }
        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        XCTAssertEqual(contextMenuPresenter.showContextMenuCalls.count, 1)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)

        XCTAssertEqual(menu.items.count, 6)
        XCTAssertFalse(menu.items.compactMap({ $0.accessibilityIdentifier() }).contains("HistoryView.addBookmark"))
        XCTAssertFalse(menu.items.map(\.title).contains(UserText.addAllToBookmarks))
    }

    // MARK: - open

    func testThatOpenCallsTabOpener() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        await actionsHandler.open(url)
        XCTAssertEqual(tabOpener.openCalls, [url])
        XCTAssertEqual(firePixelCalls, [.init(.itemOpened(.single), .dailyAndStandard)])
    }

    @MainActor
    func testThatOpenInNewTabCallsTabOpener() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: url, date: Date())
        ]

        let expectation = expectation(description: "Open in new tab completed")
        contextMenuPresenter.onShowContextMenu = { menu in
            menu.performActionForItem(at: 0) // items[0] is openInNewTab
            expectation.fulfill()
        }

        let response = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertEqual(response, .noAction)
        XCTAssertEqual(tabOpener.openInNewTabCalls, [[url]])
        XCTAssertEqual(firePixelCalls, [.init(.itemOpened(.single), .dailyAndStandard)])
    }

    @MainActor
    func testThatOpenInNewWindowCallsTabOpener() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: url, date: Date())
        ]

        let expectation = expectation(description: "Open in new window completed")
        contextMenuPresenter.onShowContextMenu = { menu in
            menu.performActionForItem(at: 1) // items[1] is openInNewWindow
            expectation.fulfill()
        }

        let response = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertEqual(response, .noAction)
        XCTAssertEqual(tabOpener.openInNewWindowCalls, [[url]])
        XCTAssertEqual(firePixelCalls, [.init(.itemOpened(.single), .dailyAndStandard)])
    }

    @MainActor
    func testThatOpenInNewFireWindowCallsTabOpener() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: url, date: Date())
        ]

        let expectation = expectation(description: "Open in new fire window completed")
        contextMenuPresenter.onShowContextMenu = { menu in
            menu.performActionForItem(at: 2) // items[2] is openInNewFireWindow
            expectation.fulfill()
        }

        let response = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertEqual(response, .noAction)
        XCTAssertEqual(tabOpener.openInNewFireWindowCalls, [[url]])
        XCTAssertEqual(firePixelCalls, [.init(.itemOpened(.single), .dailyAndStandard)])
    }

    @MainActor
    func testThatOpenActionsForMultipleItemsFirePixelForMultipleItems() async throws {
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example1.com".url), date: Date()),
            .init(uuid: "efgh", url: try XCTUnwrap("https://example2.com".url), date: Date())
        ]

        let response = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        XCTAssertEqual(response, .noAction)

        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)

        menu.performActionForItem(at: 0) // items[0] is openInNewTab
        // Wait for a short time to allow the async task to complete
        await Task.megaYield(count: 100)

        menu.performActionForItem(at: 1) // items[1] is openInNewWindow
        // Wait for a short time to allow the async task to complete
        await Task.megaYield(count: 100)

        menu.performActionForItem(at: 2) // items[2] is openInNewFireWindow
        // Wait for a short time to allow the async task to complete
        await Task.megaYield(count: 100)

        XCTAssertEqual(firePixelCalls, [
            .init(.itemOpened(.multiple), .dailyAndStandard),
            .init(.itemOpened(.multiple), .dailyAndStandard),
            .init(.itemOpened(.multiple), .dailyAndStandard)
        ])
    }

    // MARK: - addBookmarks

    @MainActor
    func testThatAddBookmarksForSingleItemCallsBookmarksHandler() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: url, date: Date())
        ]
        dataProvider.titlesForURLs = { _ in [url: "a bookmark title"] }
        bookmarksHandler.isUrlBookmarked = { _ in false }

        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        menu.performActionForItem(at: 7) // items[7] is addToBookmarks

        XCTAssertEqual(bookmarksHandler.addNewBookmarksCalls, [[.init(url: url, title: "a bookmark title")]])
    }

    @MainActor
    func testThatAddBookmarksForMultipleItemsCallsBookmarksHandler() async throws {
        let url1 = try XCTUnwrap("https://example.com".url)
        let url2 = try XCTUnwrap("https://example2.com".url)
        let url3 = try XCTUnwrap("https://example3.com".url)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: url1, date: Date()),
            .init(uuid: "efgh", url: url2, date: Date()),
            .init(uuid: "ijkl", url: url3, date: Date())
        ]
        dataProvider.titlesForURLs = { _ in
            [
                url1: "Example",
                url2: "Example 2",
                url3: "Example 3"
            ]
        }
        bookmarksHandler.isUrlBookmarked = { _ in false }

        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        menu.performActionForItem(at: 4) // items[4] is addToBookmarks

        XCTAssertEqual(bookmarksHandler.addNewBookmarksCalls, [[
            .init(url: url1, title: "Example"),
            .init(url: url2, title: "Example 2"),
            .init(url: url3, title: "Example 3")
        ]])
    }

    // MARK: - addFavorite

    @MainActor
    func testThatAddFavoriteForBookmarkedItemCallsMarkAsFavorite() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: url, date: Date())
        ]
        let bookmark = Bookmark(id: "abcd", url: url.absoluteString, title: "a bookmark title", isFavorite: false)
        bookmarksHandler.getBookmark = { _ in bookmark }

        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        menu.performActionForItem(at: 8) // items[7] is addToFavorites

        XCTAssertEqual(bookmarksHandler.markAsFavoriteCalls, [bookmark])
    }

    @MainActor
    func testThatAddFavoriteForNonBookmarkedItemCallsAddNewFavorite() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: url, date: Date())
        ]
        dataProvider.titlesForURLs = { _ in [url: "a bookmark title"] }
        bookmarksHandler.getBookmark = { _ in nil }

        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        menu.performActionForItem(at: 8) // items[7] is addToFavorites

        XCTAssertEqual(bookmarksHandler.addNewFavoriteCalls, [.init(url, "a bookmark title")])
    }

    // MARK: - delete

    @MainActor
    func testThatDeleteForSingleItemDoesNotShowDeleteDialog() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: url, date: Date())
        ]

        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        menu.performActionForItem(at: 10) // items[10] is delete

        // Wait for a short time to allow the async task to complete
        await Task.megaYield(count: 100)

        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 0)
    }

    @MainActor
    func testThatDeleteForMultipleItemsShowsDeleteDialog() async throws {
        let url1 = try XCTUnwrap("https://example1.com".url)
        let url2 = try XCTUnwrap("https://example2.com".url)

        let data = dataProvider.configureWithGeneratedTestData(domainsCount: 2, visitsPerDomain: 1)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: url1, date: Date()),
            .init(uuid: "efgh", url: url2, date: Date())
        ]
        dataProvider.visitsMatchingQuery = { _ in data.visits }

        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        menu.performActionForItem(at: 6) // items[6] is delete

        // Wait for a short time to allow the async task to complete
        await Task.megaYield(count: 100)

        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls, [.init(.visits(identifiers), data.visits)])
    }

    // MARK: - site: record actions

    @MainActor
    func testShowDeleteDialogForSiteEntriesRoutesToDomainFilterAndMapsResponse() async throws {
        // Given: site entries with visits in data provider
        // Generate 3 domains, but only request deletion of 2 to test filtering
        let data = dataProvider.configureWithGeneratedTestData(domainsCount: 3, visitsPerDomain: 5)
        // Generated domains are: site1.com, site2.com, site3.com
        // Only request deletion for site1.com and site2.com
        let domainsToDelete = ["site1.com", "site2.com"]
        dataProvider.visitsMatchingQuery = { query in
            // Filter visits to only those matching the domain filter
            if case .domainFilter(let requestedDomains) = query {
                return data.visits.filter { visit in
                    guard let host = visit.historyEntry?.url.host else { return false }
                    return requestedDomains.contains(host)
                }
            }
            return data.visits
        }
        dialogPresenter.deleteDialogResponse = .delete

        // When
        let response = await actionsHandler.showDeleteDialog(for: domainsToDelete.map { "site:\($0)" })

        // Then
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 1)
        let call = try XCTUnwrap(dialogPresenter.showDeleteDialogCalls.first)
        XCTAssertEqual(call.query, .domainFilter(Set(domainsToDelete)))
        XCTAssertEqual(response, .delete)

        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.multipleItemsDeleted(.domain, burn: false), .dailyAndStandard)
        ])
    }

    @MainActor
    func testShowContextMenuForSingleSiteDiffersOnlyInDeleteLabel() async throws {
        // Given a site selection entry
        let domain = "example.com"
        let siteEntry = "site:\(domain)"
        _ = await actionsHandler.showContextMenu(for: [siteEntry], using: contextMenuPresenter)
        XCTAssertEqual(contextMenuPresenter.showContextMenuCalls.count, 1)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)

        // Then: same structure as single identifier, but delete item label differs
        XCTAssertEqual(menu.items[0].title, UserText.openInNewTab)
        XCTAssertEqual(menu.items[0].accessibilityIdentifier(), "HistoryView.openInNewTab")
        XCTAssertEqual(menu.items[1].title, UserText.openInNewWindow)
        XCTAssertEqual(menu.items[1].accessibilityIdentifier(), "HistoryView.openInNewWindow")
        XCTAssertEqual(menu.items[2].title, UserText.openInNewFireWindow)
        XCTAssertEqual(menu.items[2].accessibilityIdentifier(), "HistoryView.openInNewFireWindow")
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        XCTAssertEqual(menu.items[4].title, UserText.showAllHistoryFromThisSite)
        XCTAssertEqual(menu.items[4].accessibilityIdentifier(), "HistoryView.showAllHistoryFromThisSite")
        XCTAssertTrue(menu.items[5].isSeparatorItem)
        XCTAssertEqual(menu.items[6].title, UserText.copyLink)
        XCTAssertEqual(menu.items[6].accessibilityIdentifier(), "HistoryView.copyLink")
        // bookmark/favorite may be present based on mocked handlers; assert last item
        XCTAssertEqual(menu.items.last?.title, UserText.deleteHistoryAndBrowsingDataMenuItem)
        XCTAssertEqual(menu.items.last?.accessibilityIdentifier(), "HistoryView.delete")
    }

    @MainActor
    func testShowAllHistoryFromThisSiteSetsDomainSearchResponse() async throws {
        let domain = "example.com"
        let siteEntry = "site:\(domain)"

        let expectation = expectation(description: "Menu action completed")
        contextMenuPresenter.onShowContextMenu = { menu in
            // item[4] is Show All History From This Site
            menu.performActionForItem(at: 4)
            expectation.fulfill()
        }

        let response = await actionsHandler.showContextMenu(for: [siteEntry], using: contextMenuPresenter)
        await fulfillment(of: [expectation], timeout: 1.0)

        // The handler sets contextMenuResponse internally; ensure returned value is domainSearch
        XCTAssertEqual(response, .domainSearch)
    }

    @MainActor
    func testCopyActionForSiteRecordUsesInjectedPasteboard() async throws {
        let domain = "example.com"
        let siteEntry = "site:\(domain)"

        let expectation = expectation(description: "Copy action completed")
        contextMenuPresenter.onShowContextMenu = { menu in
            // copy item index is 6 for site selection
            menu.performActionForItem(at: 6)
            expectation.fulfill()
        }

        let response = await actionsHandler.showContextMenu(for: [siteEntry], using: contextMenuPresenter)
        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertEqual(response, .noAction)
        XCTAssertEqual(pasteboard.string(forType: .string), "https://\(domain)")
    }

    @MainActor
    func testDeleteActionForSiteRecordShowsFireDialogAndMapsResponse() async throws {
        let domain = "site2.com"
        let data = dataProvider.configureWithGeneratedTestData(domainsCount: 3, visitsPerDomain: 1)
        dataProvider.visitsMatchingQuery = { query in
            // Filter visits to only those matching the domain filter
            if case .domainFilter(let requestedDomains) = query {
                return data.visits.filter { visit in
                    guard let host = visit.historyEntry?.url.host else { return false }
                    return requestedDomains.contains(host)
                }
            }
            return data.visits
        }
        dialogPresenter.deleteDialogResponse = .delete

        let expectation = expectation(description: "Delete action completed")
        contextMenuPresenter.onShowContextMenu = { menu in
            // Delete item is the last one
            menu.performActionForItem(at: menu.items.count - 1)
            expectation.fulfill()
        }

        let response = await actionsHandler.showContextMenu(for: ["site:\(domain)"], using: contextMenuPresenter)
        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertEqual(response, .delete)
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 1)
        let call = try XCTUnwrap(dialogPresenter.showDeleteDialogCalls.first)
        XCTAssertEqual(call.query, .domainFilter(Set([domain])))
        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.multipleItemsDeleted(.domain, burn: false), .dailyAndStandard)
        ])
    }
}

private extension HistoryViewActionsHandler {
    @MainActor func open(_ url: URL) async {
        await open(url, window: nil)
    }
    @MainActor func showDeleteDialog(for query: DataModel.HistoryQueryKind) async -> DataModel.DeleteDialogResponse {
        await showDeleteDialog(for: query, in: nil)
    }
    @MainActor func showDeleteDialog(for entries: [String]) async -> DataModel.DeleteDialogResponse {
        await showDeleteDialog(for: entries, in: nil)
    }
}
