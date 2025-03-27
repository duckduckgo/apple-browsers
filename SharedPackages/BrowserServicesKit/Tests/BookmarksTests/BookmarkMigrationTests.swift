//
//  BookmarkMigrationTests.swift
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
import XCTest
import Persistence
@testable import Bookmarks
import Foundation

class BookmarkMigrationTests: XCTestCase {

    var location: URL!
    var resourceURLDir: URL!

    override func setUp() {
        super.setUp()

        ModelAccessHelper.compileModel(from: Bundle(for: BookmarkMigrationTests.self), named: "BookmarksModel")

        location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        guard let location = Bundle(for: BookmarkMigrationTests.self).resourceURL else {
            XCTFail("Failed to find bundle URL")
            return
        }

        let resourcesLocation = location.appendingPathComponent( "BrowserServicesKit_BookmarksTests.bundle/Contents/Resources/")
        if FileManager.default.fileExists(atPath: resourcesLocation.path) == false {
            resourceURLDir = Bundle.module.resourceURL
        } else {
            resourceURLDir = resourcesLocation
        }

    }

    override func tearDown() {
        super.tearDown()

        try? FileManager.default.removeItem(at: location)
    }

    func copyDatabase(name: String, formDirectory: URL, toDirectory: URL) throws {

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: toDirectory, withIntermediateDirectories: false)
        for ext in ["sqlite", "sqlite-shm", "sqlite-wal"] {

            try fileManager.copyItem(at: formDirectory.appendingPathComponent("\(name).\(ext)"),
                                     to: toDirectory.appendingPathComponent("\(name).\(ext)"))
        }
    }

    func loadDatabase(name: String) -> CoreDataDatabase? {
        let bundle = Bookmarks.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BookmarksModel") else {
            return nil
        }
        let bookmarksDatabase = CoreDataDatabase(name: name, containerLocation: location, model: model)
        bookmarksDatabase.loadStore()
        return bookmarksDatabase
    }

    func testWhenMigratingFromV1ThenRootFoldersContentsArePreservedInOrder() throws {
        try commonMigrationTestForDatabase(name: "Bookmarks_V1")
    }

    func testWhenMigratingFromV2ThenRootFoldersContentsArePreservedInOrder() throws {
        try commonMigrationTestForDatabase(name: "Bookmarks_V2")
    }

    func testWhenMigratingFromV3ThenRootFoldersContentsArePreservedInOrder() throws {
        try commonMigrationTestForDatabase(name: "Bookmarks_V3")
    }

    func testWhenMigratingFromV4ThenRootFoldersContentsArePreservedInOrder() throws {
        try commonMigrationTestForDatabase(name: "Bookmarks_V4")
    }

    func testWhenMigratingFromV5ThenRootFoldersContentsArePreservedInOrder() throws {
        try commonMigrationTestForDatabase(name: "Bookmarks_V5")
    }

    func commonMigrationTestForDatabase(name: String) throws {

        try copyDatabase(name: name, formDirectory: resourceURLDir, toDirectory: location)
        let legacyFavoritesInOrder = try? BookmarkFormFactorFavoritesMigration().getFavoritesOrderFromPreV4Model(dbContainerLocation: location,
                                                                                                          dbFileURL: location.appendingPathComponent("\(name).sqlite", conformingTo: .database))

        // Now perform migration and test it
        guard let migratedStack = loadDatabase(name: name) else {
            XCTFail("Could not initialize legacy stack")
            return
        }

        let latestContext = migratedStack.makeContext(concurrencyType: .privateQueueConcurrencyType)
        latestContext.performAndWait({
            BookmarkFormFactorFavoritesMigration.migrateToFormFactorSpecificFavorites(byCopyingExistingTo: FavoritesFolderID.mobile,
                                                                                      preservingOrderOf: legacyFavoritesInOrder,
                                                                                      in: latestContext)

            let mobileFavoritesArray = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.mobile.rawValue, in: latestContext)?.favoritesArray.compactMap(\.uuid)
            XCTAssertEqual(legacyFavoritesInOrder, mobileFavoritesArray)

            let uuids = BookmarkUtils.fetchAllBookmarksUUIDs(in: latestContext)
            XCTAssert(!uuids.isEmpty)
        })

        // Test whole structure
        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", favoritedOn: [.unified, .mobile])
            Folder(id: "3") {
                Folder(id: "31") {}
                Bookmark(id: "32", favoritedOn: [.unified, .mobile])
                Bookmark(id: "33", favoritedOn: [.unified, .mobile])
            }
            Bookmark(id: "4", favoritedOn: [.unified, .mobile])
            Bookmark(id: "5", favoritedOn: [.unified, .mobile])
        }

        latestContext.performAndWait {
            let rootFolder = BookmarkUtils.fetchRootFolder(latestContext)!
            assertEquivalent(withTimestamps: false, rootFolder, bookmarkTree)
        }

        try? migratedStack.tearDown(deleteStores: true)
    }

    func testThatMigrationToFormFactorSpecificFavoritesAddsFavoritesToNativeFolder() async throws {

        guard let bookmarksDatabase = loadDatabase(name: "Any") else {
            XCTFail("Failed to load model")
            return
        }

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            BookmarkUtils.insertRootFolder(uuid: BookmarkEntity.Constants.rootFolderID, into: context)
            BookmarkUtils.insertRootFolder(uuid: FavoritesFolderID.unified.rawValue, into: context)
            try! context.save()
        }

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", favoritedOn: [.unified])
            Folder(id: "10") {
                Bookmark(id: "12", favoritedOn: [.unified])
            }
            Bookmark(id: "3", favoritedOn: [.unified])
            Bookmark(id: "4", favoritedOn: [.unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)

            try! context.save()
            let favoritesArray = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.unified.rawValue, in: context)?.favoritesArray.compactMap(\.uuid)

            BookmarkFormFactorFavoritesMigration.migrateToFormFactorSpecificFavorites(byCopyingExistingTo: FavoritesFolderID.mobile,
                                                               preservingOrderOf: nil,
                                                               in: context)

            try! context.save()

            let mobileFavoritesArray = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.mobile.rawValue, in: context)?.favoritesArray.compactMap(\.uuid)
            XCTAssertEqual(favoritesArray, mobileFavoritesArray)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2", favoritedOn: [.mobile, .unified])
                Folder(id: "10") {
                    Bookmark(id: "12", favoritedOn: [.mobile, .unified])
                }
                Bookmark(id: "3", favoritedOn: [.mobile, .unified])
                Bookmark(id: "4", favoritedOn: [.mobile, .unified])
            })
        }

        try? bookmarksDatabase.tearDown(deleteStores: true)
    }
}
