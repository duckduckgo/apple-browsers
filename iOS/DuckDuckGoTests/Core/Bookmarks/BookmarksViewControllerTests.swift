//
//  BookmarksViewControllerTests.swift
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

import Bookmarks
import Common
import CoreData
import FoundationExtensions
@_spi(Testing) import Persistence
import UIKit
import XCTest
@testable import Core
@testable import DuckDuckGo

final class BookmarksViewControllerTests: XCTestCase {

    private var database: CoreDataDatabase!
    private var context: NSManagedObjectContext!
    private var root: BookmarkEntity!
    private var controller: BookmarksViewController!

    @MainActor
    override func setUpWithError() throws {
        try super.setUpWithError()
        database = .bookmarksMock
        context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        BookmarkUtils.prepareFoldersStructure(in: context)
        root = try XCTUnwrap(BookmarkUtils.fetchRootFolder(context))
        try context.save()
    }

    @MainActor
    override func tearDownWithError() throws {
        UIView.performWithoutAnimation {
            ActionMessageView.dismissAllMessages()
        }
        controller = nil
        root = nil
        context.reset()
        context = nil
        try database.tearDown(deleteStores: true)
        database = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testDeletingOnlySearchResultShowsNoResultsWithUnmatchedBookmarkRemaining() throws {
        let match = makeBookmark(title: "Match")
        let other = makeBookmark(title: "Other")
        try loadController(searchBookmarks: [match, other])
        controller.searchBar(UISearchBar(), textDidChange: "Match")
        XCTAssertEqual(controller.searchDataSource.results.count, 1)
        let indexPath = IndexPath(row: 0, section: 0)
        XCTAssertNotNil(controller.tableView(controller.tableView, leadingSwipeActionsConfigurationForRowAt: indexPath))

        try swipeDeleteFirstRow()

        XCTAssertTrue(controller.searchDataSource.results.isEmpty)
        XCTAssertEqual(controller.tableView.numberOfRows(inSection: 0), 1)
        let cell = controller.searchDataSource.tableView(controller.tableView, cellForRowAt: IndexPath(row: 0, section: 0))
        XCTAssertTrue(cell is NoResultsCell)
        XCTAssertNil(controller.tableView(controller.tableView, leadingSwipeActionsConfigurationForRowAt: indexPath))
        XCTAssertNil(controller.tableView(controller.tableView, trailingSwipeActionsConfigurationForRowAt: indexPath))
        let remaining = BookmarkListViewModel(bookmarksDatabase: database, parentID: nil,
                                              favoritesDisplayMode: .displayNative(.mobile), errorEvents: nil)
        XCTAssertEqual(remaining.bookmarks.map(\.objectID), [other.objectID])
    }

    @MainActor
    func testDeletingOneOfMultipleSearchResultsKeepsRemainingResult() throws {
        let first = makeBookmark(title: "Match First")
        let second = makeBookmark(title: "Match Second")
        try loadController(searchBookmarks: [first, second])
        controller.searchBar(UISearchBar(), textDidChange: "Match")
        let remainingID = controller.searchDataSource.results[1].objectID
        XCTAssertEqual(controller.tableView.numberOfRows(inSection: 0), 2)

        try swipeDeleteFirstRow()

        XCTAssertEqual(controller.tableView.numberOfRows(inSection: 0), 1)
        XCTAssertEqual(controller.searchDataSource.results.map(\.objectID), [remainingID])
    }

    @MainActor
    func testDeletingSearchResultOutsideCurrentFolderUpdatesSearchRows() throws {
        let folder = BookmarkEntity.makeFolder(title: "Folder", parent: root, context: context)
        let first = makeBookmark(title: "Match First", parent: folder)
        let second = makeBookmark(title: "Match Second", parent: folder)
        try loadController(searchBookmarks: [first, second])
        controller.searchBar(UISearchBar(), textDidChange: "Match")
        let remainingID = controller.searchDataSource.results[1].objectID

        try swipeDeleteFirstRow()

        XCTAssertEqual(controller.tableView.numberOfRows(inSection: 0), 1)
        XCTAssertEqual(controller.searchDataSource.results.map(\.objectID), [remainingID])
    }

    @MainActor
    func testDeletingLastFolderBookmarkLeavesEmptyTable() throws {
        _ = makeBookmark(title: "Only bookmark")
        try loadController()
        XCTAssertEqual(controller.tableView.numberOfRows(inSection: 0), 1)

        try swipeDeleteFirstRow()

        XCTAssertEqual(controller.tableView.numberOfRows(inSection: 0), 0)
    }

    @MainActor
    func testDeletingOneOfMultipleFolderBookmarksKeepsRemainingBookmark() throws {
        _ = makeBookmark(title: "First")
        let second = makeBookmark(title: "Second")
        try loadController()
        XCTAssertEqual(controller.tableView.numberOfRows(inSection: 0), 2)

        try swipeDeleteFirstRow()

        XCTAssertEqual(controller.tableView.numberOfRows(inSection: 0), 1)
        let remaining = BookmarkListViewModel(bookmarksDatabase: database, parentID: nil,
                                              favoritesDisplayMode: .displayNative(.mobile), errorEvents: nil)
        XCTAssertEqual(remaining.bookmarks.map(\.objectID), [second.objectID])
    }

    private func makeBookmark(title: String, parent: BookmarkEntity? = nil) -> BookmarkEntity {
        BookmarkEntity.makeBookmark(title: title, url: "https://\(UUID().uuidString).example", parent: parent ?? root, context: context)
    }

    @MainActor
    private func loadController(searchBookmarks: [BookmarkEntity] = []) throws {
        try context.save()
        let searchStore = MockBookmarksSearchStore()
        searchStore.dataSet = try searchBookmarks.map {
            BookmarksCachingSearch.ScoredBookmark(objectID: $0.objectID, title: try XCTUnwrap($0.title),
                                                  url: try XCTUnwrap($0.urlObject), isFavorite: false)
        }
        let settings = AppSettingsMock()
        settings.favoritesDisplayMode = .displayNative(.mobile)
        let keyValueStore = MockThrowingKeyValueStore()
        let providers = SyncDataProviders(
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            bookmarksDatabase: database,
            secureVaultErrorReporter: SecureVaultReporter(),
            keyValueStore: keyValueStore,
            settingHandlers: [],
            favoritesDisplayModeStorage: MockFavoritesDisplayModeStoring(),
            syncErrorHandler: SyncErrorHandler(),
            faviconStoring: MockFaviconStore(),
            tld: TLD(),
            featureFlagger: MockFeatureFlagger()
        )
        let storyboard = UIStoryboard(name: "Bookmarks", bundle: Bundle(for: BookmarksViewController.self))
        controller = storyboard.instantiateViewController(identifier: "BookmarksViewController") { coder in
            BookmarksViewController(coder: coder, bookmarksDatabase: self.database,
                                    bookmarksSearch: BookmarksCachingSearch(bookmarksStore: searchStore),
                                    favicons: Favicons(),
                                    syncService: MockDDGSyncing(authState: .inactive, isSyncInProgress: false),
                                    syncDataProviders: providers, appSettings: settings, keyValueStore: keyValueStore,
                                    productSurfaceTelemetry: nil, pixelFiring: nil)
        }
        controller.loadViewIfNeeded()
        controller.tableView.reloadData()
        controller.tableView.layoutIfNeeded()
    }

    @MainActor
    private func swipeDeleteFirstRow(file: StaticString = #filePath, line: UInt = #line) throws {
        let tableView = try XCTUnwrap(controller.tableView)
        tableView.layoutIfNeeded()
        let indexPath = IndexPath(row: 0, section: 0)
        let configuration = try XCTUnwrap(controller.tableView(tableView, trailingSwipeActionsConfigurationForRowAt: indexPath))
        let action = try XCTUnwrap(configuration.actions.first)
        var completions: [Bool] = []
        UIView.performWithoutAnimation {
            action.handler(action, UIView()) { completions.append($0) }
        }
        tableView.layoutIfNeeded()
        XCTAssertEqual(completions, [true], file: file, line: line)
    }
}
