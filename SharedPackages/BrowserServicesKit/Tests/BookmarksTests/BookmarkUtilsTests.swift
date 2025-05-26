//
//  BookmarkUtilsTests.swift
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
import Foundation
import Persistence
import XCTest
@testable import Bookmarks

final class BookmarkUtilsTests: XCTestCase {
    var bookmarksDatabase: CoreDataDatabase!
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
    }

    override func tearDown() {
        super.tearDown()

        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: location)
    }

    func testThatFetchingRootFolderPicksTheOneWithMostChildren() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()

            guard let root1 = BookmarkUtils.fetchRootFolder(context) else {
                XCTFail("root required")
                return
            }

            let root2 = BookmarkEntity.makeFolder(title: root1.title!, parent: root1, context: context)
            root2.uuid = root1.uuid
            root2.parent = nil

            let root3 = BookmarkEntity.makeFolder(title: root1.title!, parent: root1, context: context)
            root3.uuid = root1.uuid
            root3.parent = nil

            _ = BookmarkEntity.makeBookmark(title: "a", url: "a", parent: root2, context: context)
            _ = BookmarkEntity.makeBookmark(title: "b", url: "b", parent: root2, context: context)
            _ = BookmarkEntity.makeBookmark(title: "c", url: "c", parent: root1, context: context)

            try! context.save()

            let root = BookmarkUtils.fetchRootFolder(context)
            XCTAssertEqual(root, root2)
        }
    }

    func testThatFetchingRootFavoritesFolderPicksTheOneWithMostFavorites() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()

            guard let root = BookmarkUtils.fetchRootFolder(context),
                let mobileFav1 = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.mobile.rawValue, in: context),
                  let unifiedFav1 = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.unified.rawValue, in: context) else {
                XCTFail("root required")
                return
            }

            let mobileFav2 = BookmarkEntity.makeFolder(title: mobileFav1.title!, parent: root, context: context)
            mobileFav2.uuid = mobileFav1.uuid
            mobileFav2.parent = nil

            let unifiedFav2 = BookmarkEntity.makeFolder(title: unifiedFav1.title!, parent: root, context: context)
            unifiedFav2.uuid = unifiedFav1.uuid
            unifiedFav2.parent = nil

            let bA = BookmarkEntity.makeBookmark(title: "a", url: "a", parent: root, context: context)
            let bB = BookmarkEntity.makeBookmark(title: "b", url: "b", parent: root, context: context)

            bA.addToFavorites(favoritesRoot: mobileFav2)
            bA.addToFavorites(favoritesRoot: unifiedFav1)
            bB.addToFavorites(folders: [mobileFav2, unifiedFav1])

            try! context.save()

            let roots = BookmarkUtils.fetchFavoritesFolders(for: .displayUnified(native: .mobile), in: context)
            XCTAssertEqual(Set(roots.map { $0.uuid }), [mobileFav2.uuid, unifiedFav1.uuid])

            let mobileFav = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.mobile.rawValue, in: context)
            XCTAssertEqual(mobileFav, mobileFav2)

            let unifiedFav = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.unified.rawValue, in: context)
            XCTAssertEqual(unifiedFav, unifiedFav1)
        }
    }

    func testCopyFavoritesWhenDisablingSyncInDisplayNativeMode() async throws {

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
        }

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", favoritedOn: [.mobile, .unified])
            Bookmark(id: "3", favoritedOn: [.mobile, .unified])
            Bookmark(id: "4", favoritedOn: [.mobile, .unified])
            Bookmark(id: "5", favoritedOn: [.desktop, .unified])
            Bookmark(id: "6", favoritedOn: [.desktop, .unified])
            Bookmark(id: "7", favoritedOn: [.desktop, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)

            try! context.save()

            BookmarkUtils.copyFavorites(from: .mobile, to: .unified, clearingNonNativeFavoritesFolder: .desktop, in: context)

            try! context.save()

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2", favoritedOn: [.mobile, .unified])
                Bookmark(id: "3", favoritedOn: [.mobile, .unified])
                Bookmark(id: "4", favoritedOn: [.mobile, .unified])
                Bookmark(id: "5")
                Bookmark(id: "6")
                Bookmark(id: "7")
            })
        }
    }

    func testCopyFavoritesWhenDisablingSyncInDisplayAllMode() async throws {

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
        }

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", favoritedOn: [.mobile, .unified])
            Bookmark(id: "3", favoritedOn: [.mobile, .unified])
            Bookmark(id: "4", favoritedOn: [.mobile, .unified])
            Bookmark(id: "5", favoritedOn: [.desktop, .unified])
            Bookmark(id: "6", favoritedOn: [.desktop, .unified])
            Bookmark(id: "7", favoritedOn: [.desktop, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)

            try! context.save()

            BookmarkUtils.copyFavorites(from: .unified, to: .mobile, clearingNonNativeFavoritesFolder: .desktop, in: context)

            try! context.save()

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2", favoritedOn: [.mobile, .unified])
                Bookmark(id: "3", favoritedOn: [.mobile, .unified])
                Bookmark(id: "4", favoritedOn: [.mobile, .unified])
                Bookmark(id: "5", favoritedOn: [.mobile, .unified])
                Bookmark(id: "6", favoritedOn: [.mobile, .unified])
                Bookmark(id: "7", favoritedOn: [.mobile, .unified])
            })
        }
    }

    func testThatNumberOfBookmarksSkipsFoldersAndIncludesFavorites() {

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
        }

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Folder(id: "2") {
                Bookmark(id: "3")
                Bookmark(id: "4")
                Folder(id: "5") {
                    Folder(id: "6") {
                        Bookmark(id: "7", favoritedOn: [.desktop, .unified])
                    }
                    Folder(id: "8")
                    Bookmark(id: "9", favoritedOn: [.desktop, .unified])
                    Bookmark(id: "10", favoritedOn: [.desktop, .unified])
                }
            }
            Bookmark(id: "11")
            Bookmark(id: "12")
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)

            try! context.save()

            XCTAssertEqual(BookmarkUtils.numberOfBookmarks(in: context), 8)
        }
    }

    func testThatNumberOfFavoritesHonorsDisplayMode() {

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
        }

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Folder(id: "2") {
                Bookmark(id: "3", favoritedOn: [.mobile, .unified])
                Bookmark(id: "4")
                Folder(id: "5") {
                    Folder(id: "6") {
                        Bookmark(id: "7", favoritedOn: [.desktop, .unified])
                    }
                    Folder(id: "8")
                    Bookmark(id: "9", favoritedOn: [.mobile, .unified])
                    Bookmark(id: "10", favoritedOn: [.desktop, .unified])
                }
            }
            Bookmark(id: "11", favoritedOn: [.desktop, .unified])
            Bookmark(id: "12")
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)

            try! context.save()

            XCTAssertEqual(BookmarkUtils.numberOfFavorites(for: .displayNative(.desktop), in: context), 3)
            XCTAssertEqual(BookmarkUtils.numberOfFavorites(for: .displayNative(.mobile), in: context), 2)
            XCTAssertEqual(BookmarkUtils.numberOfFavorites(for: .displayUnified(native: .desktop), in: context), 5)
            XCTAssertEqual(BookmarkUtils.numberOfFavorites(for: .displayUnified(native: .mobile), in: context), 5)
        }
    }
}
