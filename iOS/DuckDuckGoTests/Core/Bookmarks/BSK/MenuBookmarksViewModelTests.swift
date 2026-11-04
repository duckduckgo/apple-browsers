//
//  MenuBookmarksViewModelTests.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo
import Foundation
import Persistence
import XCTest

private extension MenuBookmarksViewModel {
    
    convenience init(bookmarksDatabase: CoreDataDatabase) {
        self.init(bookmarksDatabase: bookmarksDatabase,
                  errorEvents: .init(mapping: { event, _, _, _ in
            XCTFail("Unexpected error: \(event)")
        }))
    }
}

class MenuBookmarksViewModelTests: XCTestCase {
    
    let url = URL(string: "https://test.com")!
    var db: CoreDataDatabase!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        let model = CoreDataDatabase.loadModel(from: Bookmarks.bundle, named: "BookmarksModel")!
        
        db = CoreDataDatabase(name: "Test", containerLocation: tempDBDir(), model: model)
        db.loadStore()
        
        let mainContext = db.makeContext(concurrencyType: .mainQueueConcurrencyType, name: "TestContext")
        BasicBookmarksStructure.populateDB(context: mainContext)
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        
        try db.tearDown(deleteStores: true)
    }
    
    private func validateNewBookmark(_ bookmark: BookmarkEntity?) {
        guard let bookmark = bookmark else { XCTFail("Missing bookmark"); return }
        XCTAssertNotNil(bookmark)
        XCTAssertFalse(bookmark.isFavorite(on: .mobile))
        XCTAssertTrue(bookmark.favoriteFoldersSet.isEmpty)
        XCTAssertEqual(bookmark, bookmark.parent?.childrenArray.last)
    }
    
    private func validateNewFavorite(_ favorite: BookmarkEntity?) {
        guard let favorite = favorite else { XCTFail("Missing favorite"); return }
        XCTAssert(favorite.isFavorite(on: .mobile))
        XCTAssertFalse(favorite.favoriteFoldersSet.isEmpty)
        XCTAssertEqual(favorite, favorite.parent?.childrenArray.last)
        XCTAssertEqual(favorite, favorite.favoriteFoldersSet
            .first(where: { $0.uuid == FavoritesFolderID.mobile.rawValue })?
            .favorites?.lastObject as? BookmarkEntity)
    }

    func testWhenCheckingBookmarkStatusThenReturnOneIfFound() {
        let model = MenuBookmarksViewModel(bookmarksDatabase: db)
        
        XCTAssertNil(model.bookmark(for: URL(string: BasicBookmarksStructure.urlString(forName: "0"))!))
        XCTAssertNotNil(model.bookmark(for: URL(string: BasicBookmarksStructure.urlString(forName: "1"))!))
        XCTAssertNotNil(model.bookmark(for: URL(string: BasicBookmarksStructure.urlString(forName: "F2"))!))
        
        XCTAssertNil(model.favorite(for: URL(string: BasicBookmarksStructure.urlString(forName: "F2"))!))
        XCTAssertNotNil(model.favorite(for: URL(string: BasicBookmarksStructure.urlString(forName: "1"))!))
    }
    
    func testWhenAddingBookmarkThenNewEntryIsCreated() {
        let model = MenuBookmarksViewModel(bookmarksDatabase: db)
        
        XCTAssertNil(model.bookmark(for: url))
        model.createBookmark(title: "test", url: url)
        validateNewBookmark(model.bookmark(for: url))
        
        // Validate if other context will reflect same state
        let anotherModel = MenuBookmarksViewModel(bookmarksDatabase: db)
        validateNewBookmark(anotherModel.bookmark(for: url))
    }
    
    func testWhenAddingNewAsFavoriteThenNewEntryIsCreated() {
        let model = MenuBookmarksViewModel(bookmarksDatabase: db)
        
        XCTAssertNil(model.bookmark(for: url))
        model.createOrToggleFavorite(title: "test", url: url)
        validateNewFavorite(model.bookmark(for: url))
        
        // Validate if other context will reflect same state
        let anotherModel = MenuBookmarksViewModel(bookmarksDatabase: db)
        validateNewFavorite(anotherModel.bookmark(for: url))
    }
    
    func testWhenAddingExistingAsFavoriteThenBookmarkIsUpdated() {
        let model = MenuBookmarksViewModel(bookmarksDatabase: db)
        
        XCTAssertNil(model.bookmark(for: url))
        model.createBookmark(title: "test", url: url)
        let newBookmark = model.bookmark(for: url)
        let topLevelCount = newBookmark?.parent?.childrenArray.count ?? 0
        validateNewBookmark(newBookmark)
        model.createOrToggleFavorite(title: "test", url: url)
        validateNewFavorite(newBookmark)
        
        // Validate if other context will reflect same state
        let anotherModel = MenuBookmarksViewModel(bookmarksDatabase: db)
        let anotherBookmark = anotherModel.bookmark(for: url)
        let anotherLevelCount = newBookmark?.parent?.childrenArray.count ?? 0
        validateNewFavorite(anotherBookmark)
        
        XCTAssertEqual(topLevelCount, anotherLevelCount)
    }
    
    func testSavingFavoriteUpdatesExistingTitleWithoutRemovingOrDuplicatingBookmark() {
        for alreadyFavorite in [false, true] {
            let model = MenuBookmarksViewModel(bookmarksDatabase: db)
            let address = url.appendingPathComponent(String(alreadyFavorite))
            model.createBookmark(title: "Inbox", url: address)
            if alreadyFavorite {
                model.createOrToggleFavorite(title: "Inbox", url: address)
            }
            let bookmarkID = model.bookmark(for: address)?.objectID
            let bookmarkCount = model.bookmark(for: address)?.parent?.childrenArray.count

            XCTAssertTrue(model.saveFavorite(title: "Work Mail", urlString: address.absoluteString))

            let persistedModel = MenuBookmarksViewModel(bookmarksDatabase: db)
            let favorite = persistedModel.favorite(for: address)
            XCTAssertEqual(favorite?.title, "Work Mail")
            XCTAssertEqual(favorite?.objectID, bookmarkID)
            XCTAssertEqual(favorite?.parent?.childrenArray.count, bookmarkCount)
        }
    }

    func testSavingFavoriteWithoutNamePreservesExistingTitle() {
        for alreadyFavorite in [false, true] {
            let model = MenuBookmarksViewModel(bookmarksDatabase: db)
            let address = url.appendingPathComponent(String(alreadyFavorite))
            model.createBookmark(title: "Inbox", url: address)
            if alreadyFavorite {
                model.createOrToggleFavorite(title: "Inbox", url: address)
            }

            XCTAssertTrue(model.saveFavorite(title: nil, urlString: address.absoluteString))

            let persistedModel = MenuBookmarksViewModel(bookmarksDatabase: db)
            XCTAssertEqual(persistedModel.favorite(for: address)?.title, "Inbox")
        }
    }

    @MainActor
    func testSavingEditedBookmarkletRenamesExistingBookmarkWithoutDuplicatingIt() throws {
        for alreadyFavorite in [false, true] {
            let model = MenuBookmarksViewModel(bookmarksDatabase: db)
            let originalURL = url.appendingPathComponent(String(alreadyFavorite))
            model.createBookmark(title: "Original", url: originalURL)
            if alreadyFavorite {
                model.createOrToggleFavorite(title: "Original", url: originalURL)
            }

            let bookmark = try XCTUnwrap(model.bookmark(for: originalURL))
            let bookmarkCount = bookmark.parent?.childrenArray.count
            let script = "javascript:alert('Hello world \(alreadyFavorite)')"
            let editor = BookmarkEditorViewModel(editingEntityID: bookmark.objectID,
                                                  bookmarksDatabase: db,
                                                  favoritesDisplayMode: .displayNative(.mobile),
                                                  errorEvents: nil)
            editor.bookmark.url = script
            XCTAssertTrue(editor.canSave)
            editor.save()
            let encodedURL = try XCTUnwrap(BookmarkUtils.url(from: script))

            let addFavoriteModel = MenuBookmarksViewModel(bookmarksDatabase: db)
            let inputModel = AddFavoriteViewModel(bookmarks: addFavoriteModel)
            inputModel.urlText = script
            inputModel.name = "Renamed"
            XCTAssertTrue(inputModel.canSave)
            XCTAssertTrue(inputModel.save())

            let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)
            let persistedBookmark = try XCTUnwrap(try context.existingObject(with: bookmark.objectID) as? BookmarkEntity)
            XCTAssertEqual(persistedBookmark.title, "Renamed")
            XCTAssertEqual(persistedBookmark.url, script)
            XCTAssertTrue(persistedBookmark.isFavorite(on: .mobile))
            XCTAssertEqual(persistedBookmark.parent?.childrenArray.count, bookmarkCount)
            // Existing exact-string lookups retain their behavior.
            XCTAssertNil(addFavoriteModel.bookmark(for: encodedURL))
        }
    }

    func testSavingNewFavoriteWithoutNameUsesHost() {
        let model = MenuBookmarksViewModel(bookmarksDatabase: db)

        XCTAssertTrue(model.saveFavorite(title: nil, urlString: url.absoluteString))

        let persistedModel = MenuBookmarksViewModel(bookmarksDatabase: db)
        XCTAssertEqual(persistedModel.favorite(for: url)?.title, url.host)
    }

    @MainActor
    func testAddingBookmarkletPreservesEnteredURLAndReusesItOnNextSave() throws {
        let inputModel = AddFavoriteViewModel(bookmarks: MenuBookmarksViewModel(bookmarksDatabase: db))
        let script = "javascript:alert('Hello world')"
        inputModel.urlText = "  \(script)  \n"
        inputModel.name = "Original"
        XCTAssertTrue(inputModel.save())

        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let root = try XCTUnwrap(BookmarkUtils.fetchRootFolder(context))
        let bookmark = try XCTUnwrap(root.childrenArray.first { $0.url == script })
        let bookmarkCount = bookmark.parent?.childrenArray.count
        XCTAssertEqual(bookmark.url, script)
        XCTAssertEqual(bookmark.urlObject?.absoluteString, "javascript:alert('Hello%20world')")

        inputModel.name = "Renamed"
        XCTAssertTrue(inputModel.save())
        context.refresh(bookmark, mergeChanges: true)
        XCTAssertEqual(bookmark.title, "Renamed")
        XCTAssertEqual(bookmark.parent?.childrenArray.count, bookmarkCount)
    }

    func testWhenRemovingFavoriteThenBookmarkIsUpdated() {
        let model = MenuBookmarksViewModel(bookmarksDatabase: db)
        
        XCTAssertNil(model.bookmark(for: url))
        model.createOrToggleFavorite(title: "test", url: url)
        let newBookmark = model.bookmark(for: url)
        validateNewFavorite(newBookmark)
        model.createOrToggleFavorite(title: "test", url: url)
        validateNewBookmark(newBookmark)
        
        // Validate if other context will reflect same state
        let anotherModel = MenuBookmarksViewModel(bookmarksDatabase: db)
        validateNewBookmark(anotherModel.bookmark(for: url))
    }
}
