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
    fileprivate var firePixelCalls: [FirePixelCall] = []

    override func setUp() async throws {
        dataProvider = CapturingHistoryViewDataProvider()
        dialogPresenter = CapturingHistoryViewDeleteDialogPresenter()
        contextMenuPresenter = CapturingContextMenuPresenter()
        tabOpener = CapturingHistoryViewTabOpener()
        bookmarksHandler = CapturingHistoryViewBookmarksHandler()
        firePixelCalls = []
        actionsHandler = HistoryViewActionsHandler(
            dataProvider: dataProvider,
            dialogPresenter: dialogPresenter,
            tabOpener: tabOpener,
            bookmarksHandler: bookmarksHandler,
            firePixel: { self.firePixelCalls.append(.init($0, $1)) }
        )
    }

    override func tearDown() {
        actionsHandler = nil
        bookmarksHandler = nil
        contextMenuPresenter = nil
        dataProvider = nil
        dialogPresenter = nil
        tabOpener = nil
        firePixelCalls = []
    }

    // MARK: - showDeleteDialogForQuery

    func testWhenDataProviderIsNilThenShowDeleteDialogForQueryReturnsNoAction() async {
        dataProvider = nil
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .rangeFilter(.all))
        XCTAssertEqual(dialogResponse, .noAction)
    }

    func testWhenDataProviderHasNoVisitsForRangeThenShowDeleteDialogForQueryReturnsNoAction() async {
        dataProvider.countVisibleVisits = { _ in return 0 }
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .rangeFilter(.all))
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls.count, 0)
        XCTAssertEqual(dataProvider.burnVisitsMatchingQueryCalls.count, 0)
        XCTAssertEqual(dialogResponse, .noAction)
    }

    func testWhenDeleteDialogIsCancelledThenShowDeleteDialogForQueryReturnsNoAction() async {
        dataProvider.countVisibleVisits = { _ in return 100 }
        dialogPresenter.deleteDialogResponse = .noAction
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .rangeFilter(.all))
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls.count, 0)
        XCTAssertEqual(dataProvider.burnVisitsMatchingQueryCalls.count, 0)
        XCTAssertEqual(dialogResponse, .noAction)
    }

    func testWhenDeleteDialogReturnsUnknownResponseThenShowDeleteDialogForQueryReturnsNoAction() async {
        // this scenario shouldn't happen in real life anyway but is included for completeness
        dataProvider.countVisibleVisits = { _ in return 100 }
        dialogPresenter.deleteDialogResponse = .unknown
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .rangeFilter(.all))
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls.count, 0)
        XCTAssertEqual(dataProvider.burnVisitsMatchingQueryCalls.count, 0)
        XCTAssertEqual(dialogResponse, .noAction)
    }

    func testWhenDeleteDialogIsAcceptedWithBurningThenShowDeleteDialogForQueryPerformsBurningAndReturnsDeleteAction() async {
        dataProvider.countVisibleVisits = { _ in return 100 }
        dialogPresenter.deleteDialogResponse = .burn
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .rangeFilter(.all))
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls.count, 0)
        XCTAssertEqual(dataProvider.burnVisitsMatchingQueryCalls.count, 1)
        XCTAssertEqual(dialogResponse, .delete)

        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.multipleItemsDeleted(.all, burn: true), .dailyAndStandard)
        ])
    }

    func testWhenDeleteDialogIsAcceptedWithoutBurningThenShowDeleteDialogForQueryPerformsDeletionAndReturnsDeleteAction() async {
        dataProvider.countVisibleVisits = { _ in return 100 }
        dialogPresenter.deleteDialogResponse = .delete
        let dialogResponse = await actionsHandler.showDeleteDialog(for: .rangeFilter(.all))
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls.count, 1)
        XCTAssertEqual(dataProvider.burnVisitsMatchingQueryCalls.count, 0)
        XCTAssertEqual(dialogResponse, .delete)

        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.multipleItemsDeleted(.all, burn: false), .dailyAndStandard)
        ])
    }

    func testThatShowDeleteDialogForNonRangeQueryNotMatchingAllVisitsDoesNotAdjustQueryToAllRange() async throws {
        dataProvider.countVisibleVisits = { query in
            switch query {
            case .rangeFilter(.all):
                return 100
            default:
                return 10
            }
        }
        dialogPresenter.deleteDialogResponse = .delete
        _ = await actionsHandler.showDeleteDialog(for: .searchTerm("hello"))
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls.count, 1)
        let deleteVisitsCall = try XCTUnwrap(dataProvider.deleteVisitsMatchingQueryCalls.first)
        XCTAssertEqual(deleteVisitsCall, .searchTerm("hello"))

        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.multipleItemsDeleted(.searchTerm, burn: false), .dailyAndStandard)
        ])
    }

    func testThatShowDeleteDialogForNonRangeQueryMatchingAllVisitsAdjustsQueryToAllRange() async throws {
        dataProvider.countVisibleVisits = { _ in return 100 } // this ensures that all queries are treated as "all range"
        dialogPresenter.deleteDialogResponse = .delete
        _ = await actionsHandler.showDeleteDialog(for: .searchTerm("hello"))
        XCTAssertEqual(dataProvider.deleteVisitsMatchingQueryCalls.count, 1)
        let deleteVisitsCall = try XCTUnwrap(dataProvider.deleteVisitsMatchingQueryCalls.first)
        XCTAssertEqual(deleteVisitsCall, .rangeFilter(.all))

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
        XCTAssertEqual(dataProvider.deleteVisitsForIdentifierCalls.count, 1)
        XCTAssertEqual(dataProvider.burnVisitsForIdentifiersCalls.count, 0)
        XCTAssertEqual(dialogResponse, .delete)

        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.singleItemDeleted, .dailyAndStandard)
        ])
    }

    func testWhenMultipleIdentifiersArePassedAndDeleteDialogReturnsUnknownResponseThenShowDeleteDialogForQueryReturnsNoAction() async throws {
        // this scenario shouldn't happen in real life anyway but is included for completeness
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
            .init(uuid: "efgh", url: try XCTUnwrap("https://domain.com".url), date: Date())
        ]
        dialogPresenter.deleteDialogResponse = .unknown
        let dialogResponse = await actionsHandler.showDeleteDialog(for: identifiers.map(\.description))
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 1)
        XCTAssertEqual(dataProvider.deleteVisitsForIdentifierCalls.count, 0)
        XCTAssertEqual(dataProvider.burnVisitsForIdentifiersCalls.count, 0)
        XCTAssertEqual(dialogResponse, .noAction)

        XCTAssertEqual(firePixelCalls, [])
    }

    func testWhenMultipleIdentifiersArePassedAndDeleteDialogIsCancelledThenShowDeleteDialogForQueryReturnsNoAction() async throws {
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
            .init(uuid: "efgh", url: try XCTUnwrap("https://domain.com".url), date: Date())
        ]
        dialogPresenter.deleteDialogResponse = .noAction
        let dialogResponse = await actionsHandler.showDeleteDialog(for: identifiers.map(\.description))
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 1)
        XCTAssertEqual(dataProvider.deleteVisitsForIdentifierCalls.count, 0)
        XCTAssertEqual(dataProvider.burnVisitsForIdentifiersCalls.count, 0)
        XCTAssertEqual(dialogResponse, .noAction)

        XCTAssertEqual(firePixelCalls, [])
    }

    func testWhenMultipleIdentifiersArePassedAndDeleteDialogIsAcceptedWithBurningThenShowDeleteDialogForQueryReturnsDeleteAction() async throws {
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
            .init(uuid: "efgh", url: try XCTUnwrap("https://domain.com".url), date: Date())
        ]
        dialogPresenter.deleteDialogResponse = .burn
        let dialogResponse = await actionsHandler.showDeleteDialog(for: identifiers.map(\.description))
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 1)
        XCTAssertEqual(dataProvider.deleteVisitsForIdentifierCalls.count, 0)
        XCTAssertEqual(dataProvider.burnVisitsForIdentifiersCalls.count, 1)
        XCTAssertEqual(dialogResponse, .delete)

        XCTAssertEqual(firePixelCalls, [
            .init(.delete, .daily),
            .init(.multipleItemsDeleted(.multiSelect, burn: true), .dailyAndStandard)
        ])
    }

    func testWhenMultipleIdentifiersArePassedAndDeleteDialogIsAcceptedWithoutBurningThenShowDeleteDialogForQueryReturnsDeleteAction() async throws {
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
            .init(uuid: "efgh", url: try XCTUnwrap("https://domain.com".url), date: Date())
        ]
        dialogPresenter.deleteDialogResponse = .delete
        let dialogResponse = await actionsHandler.showDeleteDialog(for: identifiers.map(\.description))
        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 1)
        XCTAssertEqual(dataProvider.deleteVisitsForIdentifierCalls.count, 1)
        XCTAssertEqual(dataProvider.burnVisitsForIdentifiersCalls.count, 0)
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

    func testWhenShowContextMenuIsCalledForSingleItemThenItShowsMenuForSingleItem() async throws {
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example.com".url), date: Date()),
        ]
        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        XCTAssertEqual(contextMenuPresenter.showContextMenuCalls.count, 1)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)

        XCTAssertEqual(menu.items.count, 11)

        XCTAssertEqual(menu.items[0].title, UserText.openInNewTab)
        XCTAssertEqual(menu.items[1].title, UserText.openInNewWindow)
        XCTAssertEqual(menu.items[2].title, UserText.openInNewFireWindow)
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        XCTAssertEqual(menu.items[4].title, UserText.showAllHistoryFromThisSite)
        XCTAssertTrue(menu.items[5].isSeparatorItem)
        XCTAssertEqual(menu.items[6].title, UserText.copyLink)
        XCTAssertEqual(menu.items[7].title, UserText.addToBookmarks)
        XCTAssertEqual(menu.items[8].title, UserText.addToFavorites)
        XCTAssertTrue(menu.items[9].isSeparatorItem)
        XCTAssertEqual(menu.items[10].title, UserText.delete)
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
        XCTAssertEqual(menu.items[1].title, UserText.openAllTabsInNewWindow)
        XCTAssertEqual(menu.items[2].title, UserText.openAllInNewFireWindow)
        XCTAssertTrue(menu.items[3].isSeparatorItem)
        XCTAssertEqual(menu.items[4].title, UserText.addAllToBookmarks)
        XCTAssertTrue(menu.items[5].isSeparatorItem)
        XCTAssertEqual(menu.items[6].title, UserText.delete)
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
        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        menu.performActionForItem(at: 0) // items[0] is openInNewTab

        // Wait for a short time to allow the async task to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(tabOpener.openInNewTabCalls, [[url]])
        XCTAssertEqual(firePixelCalls, [.init(.itemOpened(.single), .dailyAndStandard)])
    }

    @MainActor
    func testThatOpenInNewWindowCallsTabOpener() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: url, date: Date())
        ]
        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        menu.performActionForItem(at: 1) // items[1] is openInNewWindow

        // Wait for a short time to allow the async task to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(tabOpener.openInNewWindowCalls, [[url]])
        XCTAssertEqual(firePixelCalls, [.init(.itemOpened(.single), .dailyAndStandard)])
    }

    @MainActor
    func testThatOpenInNewFireWindowCallsTabOpener() async throws {
        let url = try XCTUnwrap("https://example.com".url)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: url, date: Date())
        ]
        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        menu.performActionForItem(at: 2) // items[2] is openInNewFireWindow

        // Wait for a short time to allow the async task to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(tabOpener.openInNewFireWindowCalls, [[url]])
        XCTAssertEqual(firePixelCalls, [.init(.itemOpened(.single), .dailyAndStandard)])
    }

    @MainActor
    func testThatOpenActionsForMultipleItemsFirePixelForMultipleItems() async throws {
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: try XCTUnwrap("https://example1.com".url), date: Date()),
            .init(uuid: "efgh", url: try XCTUnwrap("https://example2.com".url), date: Date())
        ]
        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        menu.performActionForItem(at: 0) // items[0] is openInNewTab
        // Wait for a short time to allow the async task to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        menu.performActionForItem(at: 1) // items[1] is openInNewWindow
        // Wait for a short time to allow the async task to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        menu.performActionForItem(at: 2) // items[2] is openInNewFireWindow
        // Wait for a short time to allow the async task to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

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
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls.count, 0)
    }

    @MainActor
    func testThatDeleteForMultipleItemsShowsDeleteDialog() async throws {
        let url1 = try XCTUnwrap("https://example1.com".url)
        let url2 = try XCTUnwrap("https://example2.com".url)
        let identifiers: [VisitIdentifier] = [
            .init(uuid: "abcd", url: url1, date: Date()),
            .init(uuid: "efgh", url: url2, date: Date())
        ]

        _ = await actionsHandler.showContextMenu(for: identifiers.map(\.description), using: contextMenuPresenter)
        let menu = try XCTUnwrap(contextMenuPresenter.showContextMenuCalls.first)
        menu.performActionForItem(at: 6) // items[6] is delete

        // Wait for a short time to allow the async task to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(dialogPresenter.showDeleteDialogCalls, [.init(2, .unspecified)])
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
