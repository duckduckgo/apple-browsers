//
//  FavoritesDebugViewModelTests.swift
//  DuckDuckGoTests
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

import XCTest
import Combine
import CoreData
import Bookmarks
import Persistence
@testable import DuckDuckGo

final class FavoritesDebugViewModelTests: XCTestCase {

    private var database: CoreDataDatabase!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let model = try XCTUnwrap(CoreDataDatabase.loadModel(from: Bookmarks.bundle, named: "BookmarksModel"))
        database = CoreDataDatabase(name: "FavoritesDebugTests", containerLocation: tempDBDir(), model: model)
        database.loadStore()
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        BookmarkUtils.prepareFoldersStructure(in: context)
        try context.save()
    }

    override func tearDownWithError() throws {
        try database.tearDown(deleteStores: true)
        database = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testAddingPresetAndCustomCountsIsAdditive() throws {
        let model = makeModel()
        XCTAssertEqual(model.favoritesCount, 0)

        for count in [5, 30, 7] {
            let previousCount = model.favoritesCount
            try model.addFavorites(count: count)
            XCTAssertEqual(model.favoritesCount, previousCount + count)
            XCTAssertEqual(favorites(on: .mobile).count, previousCount + count)
        }
        XCTAssertEqual(favorites(on: .unified).count, 42)
    }

    @MainActor
    func testRepeatedAddsCreateUniqueURLs() throws {
        let model = makeModel()
        try model.addFavorites(count: 5)
        try model.addFavorites(count: 5)

        let urls = favorites(on: .mobile).compactMap { $0.url }
        XCTAssertEqual(urls.count, 10)
        XCTAssertEqual(Set(urls).count, 10)
    }

    @MainActor
    func testAddingFavoritesPreservesExistingBookmarksAndFavorites() throws {
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let root = try XCTUnwrap(BookmarkUtils.fetchRootFolder(context))
        let bookmark = BookmarkEntity.makeBookmark(title: "Existing bookmark", url: "https://existing.example/bookmark",
                                                   parent: root, context: context)
        let favorite = BookmarkEntity.makeBookmark(title: "Existing favorite", url: "https://existing.example/favorite",
                                                   parent: root, context: context)
        favorite.addToFavorites(with: .displayNative(.mobile), in: context)
        try context.save()
        let bookmarkID = bookmark.objectID
        let favoriteID = favorite.objectID

        let model = makeModel()
        XCTAssertEqual(model.favoritesCount, 1)
        try model.addFavorites(count: 5)

        let persistedContext = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let persistedBookmark = try XCTUnwrap(try persistedContext.existingObject(with: bookmarkID) as? BookmarkEntity)
        let persistedFavorite = try XCTUnwrap(try persistedContext.existingObject(with: favoriteID) as? BookmarkEntity)
        XCTAssertEqual(persistedBookmark.title, "Existing bookmark")
        XCTAssertEqual(persistedBookmark.url, "https://existing.example/bookmark")
        XCTAssertFalse(persistedBookmark.isFavorite(on: .mobile))
        XCTAssertEqual(persistedBookmark.parent?.objectID, root.objectID)
        XCTAssertEqual(persistedFavorite.title, "Existing favorite")
        XCTAssertEqual(persistedFavorite.url, "https://existing.example/favorite")
        XCTAssertTrue(persistedFavorite.isFavorite(on: .mobile))
        XCTAssertEqual(persistedFavorite.parent?.objectID, root.objectID)
        XCTAssertEqual(model.favoritesCount, 6)
    }

    @MainActor
    func testRemovingNativeFavoritesPreservesBookmarksAndDesktopFavorites() throws {
        let originalIDs = try seedFormFactorFavorites()
        let model = makeModel()
        XCTAssertEqual(model.favoritesCount, 2)

        try model.removeAllFavorites()

        XCTAssertEqual(model.favoritesCount, 0)
        XCTAssertTrue(favorites(on: .mobile).isEmpty)
        XCTAssertEqual(Set(favorites(on: .desktop).compactMap { $0.title }), ["Desktop", "Both"])
        XCTAssertEqual(Set(favorites(on: .unified).compactMap { $0.title }), ["Desktop", "Both"])
        XCTAssertEqual(try bookmarkIDs(), originalIDs)
    }

    @MainActor
    func testRemovingUnifiedFavoritesPreservesAllBookmarks() throws {
        let originalIDs = try seedFormFactorFavorites()
        let model = makeModel(displayMode: .displayUnified(native: .mobile))
        XCTAssertEqual(model.favoritesCount, 3)

        try model.removeAllFavorites()

        XCTAssertEqual(model.favoritesCount, 0)
        for folder: FavoritesFolderID in [.mobile, .desktop, .unified] {
            XCTAssertTrue(favorites(on: folder).isEmpty)
        }
        XCTAssertEqual(try bookmarkIDs(), originalIDs)
        try model.removeAllFavorites()
        XCTAssertEqual(model.favoritesCount, 0)
    }

    @MainActor
    func testInvalidCountsDoNotChangeBookmarksOrFavorites() throws {
        let model = makeModel()
        try model.addFavorites(count: 5)
        let originalIDs = try bookmarkIDs()

        for count in [-1, 0, 1_001, Int.max] {
            XCTAssertThrowsError(try model.addFavorites(count: count))
            XCTAssertEqual(model.favoritesCount, 5)
            XCTAssertEqual(favorites(on: .mobile).count, 5)
            XCTAssertEqual(try bookmarkIDs(), originalIDs)
        }
    }

    @MainActor
    func testSavingUpdatesAnExistingFavoritesList() throws {
        let favoritesModel = FavoritesListViewModel(bookmarksDatabase: database,
                                                    errorEvents: nil,
                                                    favoritesDisplayMode: .displayNative(.mobile))
        let updated = expectation(description: "Existing favorites list receives changes")
        let observation = favoritesModel.externalUpdates.sink { updated.fulfill() }
        defer { observation.cancel() }

        try makeModel().addFavorites(count: 5)

        waitForExpectations(timeout: 1)
        XCTAssertEqual(favoritesModel.favorites.count, 5)
    }

    @MainActor
    func testExternalSaveUpdatesCountAndNewFavoriteCanBeRemoved() throws {
        let model = makeModel()
        XCTAssertEqual(model.favoritesCount, 0)
        let updated = expectation(description: "Debug favorites count receives external save")
        let observation = model.$favoritesCount.dropFirst().filter { $0 == 1 }.prefix(1).sink { _ in
            updated.fulfill()
        }
        defer { observation.cancel() }

        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let root = try XCTUnwrap(BookmarkUtils.fetchRootFolder(context))
        let favorite = BookmarkEntity.makeBookmark(title: "External favorite", url: "https://existing.example/external",
                                                   parent: root, context: context)
        favorite.addToFavorites(with: .displayNative(.mobile), in: context)
        try context.save()

        waitForExpectations(timeout: 1)
        XCTAssertEqual(model.favoritesCount, 1)

        try model.removeAllFavorites()

        XCTAssertEqual(model.favoritesCount, 0)
        XCTAssertTrue(favorites(on: .mobile).isEmpty)
        XCTAssertTrue(favorites(on: .unified).isEmpty)
    }

    @MainActor
    private func makeModel(displayMode: FavoritesDisplayMode = .displayNative(.mobile)) -> FavoritesDebugViewModel {
        FavoritesDebugViewModel(bookmarksDatabase: database, favoritesDisplayMode: displayMode)
    }

    private func favorites(on folder: FavoritesFolderID) -> [(title: String?, url: String?)] {
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let bookmarks = BookmarkUtils.fetchFavoritesFolder(withUUID: folder.rawValue, in: context)?.favoritesArray ?? []
        return bookmarks.map { (title: $0.title, url: $0.url) }
    }

    private func bookmarkIDs() throws -> Set<NSManagedObjectID> {
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == NO", #keyPath(BookmarkEntity.isFolder))
        return Set(try context.fetch(request).map(\.objectID))
    }

    private func seedFormFactorFavorites() throws -> Set<NSManagedObjectID> {
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let root = try XCTUnwrap(BookmarkUtils.fetchRootFolder(context))
        for title in ["Mobile", "Desktop", "Both"] {
            let bookmark = BookmarkEntity.makeBookmark(title: title, url: "https://existing.example/\(title)",
                                                       parent: root, context: context)
            if title != "Desktop" {
                bookmark.addToFavorites(with: .displayNative(.mobile), in: context)
            }
            if title != "Mobile" {
                bookmark.addToFavorites(with: .displayNative(.desktop), in: context)
            }
        }
        try context.save()
        return try bookmarkIDs()
    }
}
