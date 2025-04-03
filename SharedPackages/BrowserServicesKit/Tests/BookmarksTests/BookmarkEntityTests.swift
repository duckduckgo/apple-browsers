//
//  BookmarkEntityTests.swift
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import CoreData
import Foundation
import XCTest
import Persistence
@testable import Bookmarks

final class BookmarkEntityTests: XCTestCase {
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

    func testWhenSettingUpDatabaseThenModifiedAtIsNotSetForRootAndFavoritesFolders() throws {

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            let favoritesFolders = BookmarkEntity.Constants.favoriteFoldersIDs.map { BookmarkUtils.fetchFavoritesFolder(withUUID: $0, in: context)! }

            XCTAssertNil(rootFolder.modifiedAt)
            XCTAssertTrue(favoritesFolders.allSatisfy { $0.modifiedAt == nil })
        }
    }

    func testWhenBookmarkIsSavedThenModifiedAtIsUpdated() throws {

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let bookmark = makeBookmark(in: context)
            try! context.save()

            let firstSaveModifiedAt = bookmark.modifiedAt
            XCTAssertNotNil(firstSaveModifiedAt)

            bookmark.url = "https://www.duck.com"

            try! context.save()

            let nextSaveModifiedAt = bookmark.modifiedAt
            XCTAssertNotNil(nextSaveModifiedAt)

            XCTAssertTrue(firstSaveModifiedAt! < nextSaveModifiedAt!)
        }
    }

    func testWhenBookmarkIsMarkedPendingDeletionThenModifiedAtIsPopulatedForBookmarkAndItsParentFolder() throws {

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let rootFolder = BookmarkUtils.fetchRootFolder(context)
            let bookmark = makeBookmark(in: context)
            try! context.save()
            XCTAssertNotNil(bookmark.modifiedAt)

            bookmark.modifiedAt = nil
            rootFolder?.modifiedAt = nil
            try! context.save()
            XCTAssertNil(bookmark.modifiedAt)
            XCTAssertNil(rootFolder?.modifiedAt)

            bookmark.markPendingDeletion()
            try! context.save()
            XCTAssertNotNil(bookmark.modifiedAt)
            XCTAssertNotNil(rootFolder?.modifiedAt)
        }
    }

    func testWhenBookmarkModificationTimestampIsUpdatedThenItIsNotOverwrittenUponSave() throws {

        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let bookmark = makeBookmark(in: context)
            try! context.save()

            let firstSaveModifiedAt = bookmark.modifiedAt
            XCTAssertNotNil(firstSaveModifiedAt)

            bookmark.modifiedAt = nil

            try! context.save()

            XCTAssertNil(bookmark.modifiedAt)
        }
    }

    private func makeBookmark(withParent parent: BookmarkEntity? = nil, in context: NSManagedObjectContext) -> BookmarkEntity {
        let parentFolder = parent ?? BookmarkUtils.fetchRootFolder(context)!
        return BookmarkEntity.makeBookmark(
            title: "Bookmark 1",
            url: "https://www.duckduckgo.com",
            parent: parentFolder,
            context: context
        )
    }
}
