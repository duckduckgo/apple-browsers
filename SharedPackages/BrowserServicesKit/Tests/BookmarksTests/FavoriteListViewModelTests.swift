//
//  FavoriteListViewModelTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import BookmarksTestsUtils
import Common
import Foundation
import Persistence
import XCTest
@testable import Bookmarks

final class FavoriteListViewModelTests: XCTestCase {
    var bookmarksDatabase: CoreDataDatabase!
    var favoriteListViewModel: FavoritesListViewModel!
    var eventMapping: MockBookmarksModelErrorEventMapping!
    var firedEvents: [BookmarksModelError] = []
    var location: URL!

    override func setUp() {
        super.setUp()

        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let bundle = Bookmarks.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BookmarksModel") else {
            XCTFail("Failed to load model")
            return
        }
        bookmarksDatabase = CoreDataDatabase(name: type(of: self).description(), containerLocation: location, model: model)
        bookmarksDatabase.loadStore()
        eventMapping = MockBookmarksModelErrorEventMapping { [weak self] event in
            self?.firedEvents.append(event)
        }

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
        }

        favoriteListViewModel = FavoritesListViewModel(
            bookmarksDatabase: bookmarksDatabase,
            errorEvents: eventMapping,
            favoritesDisplayMode: .displayNative(.mobile)
        )
    }

    override func tearDown() {
        super.tearDown()
        firedEvents.removeAll()

        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: location)
    }

    func testWhenBookmarkIsDeletedAndAnotherIsMovedThenNoErrorIsFired() {

        let context = favoriteListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified], isDeleted: true)
            Bookmark(id: "2", favoritedOn: [.mobile, .unified])
            Bookmark(id: "3", favoritedOn: [.mobile, .unified], isDeleted: true)
            Bookmark(id: "4", favoritedOn: [.mobile, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)

            try! context.save()

            let favoriteFolderUUID = favoriteListViewModel.favoritesDisplayMode.displayedFolder.rawValue
            let rootFavoriteFolder = BookmarkUtils.fetchFavoritesFolder(withUUID: favoriteFolderUUID, in: context)!
            XCTAssertEqual(rootFavoriteFolder.favoritesArray.map(\.title), ["2", "4"])

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "2", context: context)!
            favoriteListViewModel.reloadData()
            favoriteListViewModel.moveFavorite(bookmark, fromIndex: 0, toIndex: 1)
            context.refreshAllObjects()

            XCTAssertEqual(rootFavoriteFolder.favoritesArray.map(\.title), ["4", "2"])
            XCTAssertEqual(firedEvents, [])
        }
    }

    func testWhenBookmarkIsMovedAndThereAreStubsThenCorrectIndexIsCalculated() {

        let context = favoriteListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Bookmark(id: "s1", favoritedOn: [.mobile, .unified], isStub: true)
            Bookmark(id: "2", favoritedOn: [.mobile, .unified])
            Bookmark(id: "s2", favoritedOn: [.mobile, .unified], isStub: true)
            Bookmark(id: "3", favoritedOn: [.mobile, .unified])
            Bookmark(id: "s3", favoritedOn: [.mobile, .unified], isStub: true)
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            let favoriteFolderUUID = favoriteListViewModel.favoritesDisplayMode.displayedFolder.rawValue
            let rootFavoriteFolder = BookmarkUtils.fetchFavoritesFolder(withUUID: favoriteFolderUUID, in: context)!

            favoriteListViewModel.reloadData()

            favoriteListViewModel.moveFavorite(bookmark, fromIndex: 0, toIndex: 0)
            XCTAssertEqual((rootFavoriteFolder.favorites?.array as! [BookmarkEntity]).map(\.uuid), ["1", "s1", "2", "s2", "3", "s3"])
            XCTAssertEqual(rootFavoriteFolder.favoritesArray.map(\.title), ["1", "2", "3"])

            favoriteListViewModel.moveFavorite(bookmark, fromIndex: 0, toIndex: 1)
            XCTAssertEqual((rootFavoriteFolder.favorites?.array as! [BookmarkEntity]).map(\.uuid), ["s1", "2", "1", "s2", "3", "s3"])
            XCTAssertEqual(rootFavoriteFolder.favoritesArray.map(\.title), ["2", "1", "3"])

            favoriteListViewModel.moveFavorite(bookmark, fromIndex: 1, toIndex: 2)
            XCTAssertEqual((rootFavoriteFolder.favorites?.array as! [BookmarkEntity]).map(\.uuid), ["s1", "2", "s2", "3", "1", "s3"])
            XCTAssertEqual(rootFavoriteFolder.favoritesArray.map(\.title), ["2", "3", "1"])

            XCTAssertEqual(firedEvents, [])
        }
    }

    func testDisplayNativeMode_WhenFavoriteIsUnfavoritedThenItIsRemovedFromNativeAndUnifiedFolder() async throws {

        favoriteListViewModel.favoritesDisplayMode = .displayNative(.mobile)
        let context = favoriteListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            favoriteListViewModel.reloadData()
            favoriteListViewModel.removeFavorite(bookmark)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
            })
        }
    }

    func testDisplayNativeMode_WhenAllFormFactorsFavoriteIsUnfavoritedThenItIsOnlyRemovedFromNativeFolder() async throws {

        favoriteListViewModel.favoritesDisplayMode = .displayNative(.mobile)
        let context = favoriteListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .desktop, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            favoriteListViewModel.reloadData()
            favoriteListViewModel.removeFavorite(bookmark)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1", favoritedOn: [.desktop, .unified])
            })
        }
    }

    func testDisplayAllMode_WhenNonNativeFavoriteIsUnfavoritedThenItIsRemovedFromAllFolders() async throws {

        favoriteListViewModel.favoritesDisplayMode = .displayUnified(native: .mobile)
        let context = favoriteListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.desktop, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            favoriteListViewModel.reloadData()
            favoriteListViewModel.removeFavorite(bookmark)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
            })
        }
    }

    func testDisplayAllMode_WhenAllFormFactorsFavoriteIsUnfavoritedThenItIsRemovedFromAllFolders() async throws {

        favoriteListViewModel.favoritesDisplayMode = .displayUnified(native: .mobile)
        let context = favoriteListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .desktop, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            favoriteListViewModel.reloadData()
            favoriteListViewModel.removeFavorite(bookmark)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
            })
        }
    }
}
