//
//  BookmarkListViewModelTests.swift
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
import CoreData
import Foundation
import Persistence
import XCTest
@testable import Bookmarks

class MockBookmarksModelErrorEventMapping: EventMapping<BookmarksModelError> {

    init(didFireEvent: @escaping (BookmarksModelError) -> Void) {
        super.init { event, _, _, _ in
            didFireEvent(event)
        }
    }

    override init(mapping: @escaping EventMapping<BookmarksModelError>.Mapping) {
        fatalError("Use init()")
    }
}

final class BookmarkListViewModelTests: XCTestCase {
    var bookmarksDatabase: CoreDataDatabase!
    var bookmarkListViewModel: BookmarkListViewModel!
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

        bookmarkListViewModel = BookmarkListViewModel(
            bookmarksDatabase: bookmarksDatabase,
            parentID: nil,
            favoritesDisplayMode: .displayNative(.mobile),
            errorEvents: eventMapping
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

        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", isDeleted: true)
            Bookmark(id: "2")
            Bookmark(id: "3", isDeleted: true)
            Bookmark(id: "4")
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)

            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "2", context: context)!

            bookmarkListViewModel.reloadData()
            bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 0, toIndex: 1)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1", isDeleted: true)
                Bookmark(id: "3", isDeleted: true)
                Bookmark(id: "4")
                Bookmark(id: "2")
            })

            XCTAssertEqual(firedEvents, [])
        }
    }

    func testWhenBookmarkIsMovedToIndexOutsideOfRootFolderBoundsThenErrorIsFired() {

        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            bookmarkListViewModel.reloadData()
            bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 0, toIndex: 5)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2")
            })

            XCTAssertEqual(firedEvents, [.indexOutOfRange(.bookmarks)])
        }
    }

    func testWhenBookmarkIsMovedAndThereAreStubsThenCorrectIndexIsCalculated() {

        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "s1", isStub: true)
            Bookmark(id: "2")
            Bookmark(id: "s2", isStub: true)
            Bookmark(id: "3")
            Bookmark(id: "s3", isStub: true)
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            bookmarkListViewModel.reloadData()

            bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 0, toIndex: 0)
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "s1", isStub: true)
                Bookmark(id: "2")
                Bookmark(id: "s2", isStub: true)
                Bookmark(id: "3")
                Bookmark(id: "s3", isStub: true)
            })

            bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 0, toIndex: 1)
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "s1", isStub: true)
                Bookmark(id: "2")
                Bookmark(id: "1")
                Bookmark(id: "s2", isStub: true)
                Bookmark(id: "3")
                Bookmark(id: "s3", isStub: true)
            })

            bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 1, toIndex: 2)
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "s1", isStub: true)
                Bookmark(id: "2")
                Bookmark(id: "s2", isStub: true)
                Bookmark(id: "3")
                Bookmark(id: "1")
                Bookmark(id: "s3", isStub: true)
            })

            XCTAssertEqual(firedEvents, [])
        }
    }

    func testWhenOrphanedBookmarkIsMovedThenItIsAttachedToRootFolder() async throws {

        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", isOrphaned: true)
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "2", context: context)!

            bookmarkListViewModel.reloadData()
            bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 1, toIndex: 0)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "2")
                Bookmark(id: "1")
            })
        }
    }

    func testWhenOrphanedBookmarkIsMovedUpThenAllOrphanedBookmarksBeforeItAreAttachedToRootFolder() async throws {

        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", isOrphaned: true)
            Bookmark(id: "3", isOrphaned: true)
            Bookmark(id: "4", isOrphaned: true)
            Bookmark(id: "5", isOrphaned: true)
            Bookmark(id: "6", isOrphaned: true)
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "5", context: context)!

            bookmarkListViewModel.reloadData()
            firedEvents.removeAll()
            bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 4, toIndex: 2)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2")
                Bookmark(id: "5")
                Bookmark(id: "3")
                Bookmark(id: "4")
                Bookmark(id: "6", isOrphaned: true)
            })
        }
    }

    func testWhenOrphanedBookmarkIsMovedDownThenAllOrphanedBookmarksBeforeToIndexAreAttachedToRootFolder() async throws {

        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", isOrphaned: true)
            Bookmark(id: "3", isOrphaned: true)
            Bookmark(id: "4", isOrphaned: true)
            Bookmark(id: "5", isOrphaned: true)
            Bookmark(id: "6", isOrphaned: true)
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "3", context: context)!

            bookmarkListViewModel.reloadData()
            firedEvents.removeAll()
            bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 2, toIndex: 4)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
                Bookmark(id: "2")
                Bookmark(id: "4")
                Bookmark(id: "5")
                Bookmark(id: "3")
                Bookmark(id: "6", isOrphaned: true)
            })
        }
    }

    func testWhenBookmarkIsMovedBelowOrphanedBookmarkThenAllOrphanedBookmarksBeforeToIndexAreAttachedToRootFolder() async throws {

        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", isOrphaned: true)
            Bookmark(id: "3", isOrphaned: true)
            Bookmark(id: "4", isOrphaned: true)
            Bookmark(id: "5", isOrphaned: true)
            Bookmark(id: "6", isOrphaned: true)
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            bookmarkListViewModel.reloadData()
            firedEvents.removeAll()
            bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 0, toIndex: 3)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "2")
                Bookmark(id: "3")
                Bookmark(id: "4")
                Bookmark(id: "1")
                Bookmark(id: "5", isOrphaned: true)
                Bookmark(id: "6", isOrphaned: true)
            })
        }
    }

    func testWhenBookmarkIsMovedWithinNonOrphanedBookmarksThenOrphanedBookmarksAreNotAffected() async throws {

        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "3", isOrphaned: true)
            Bookmark(id: "4", isOrphaned: true)
            Bookmark(id: "5", isOrphaned: true)
            Bookmark(id: "6", isOrphaned: true)
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "2", context: context)!

            bookmarkListViewModel.reloadData()
            firedEvents.removeAll()
            bookmarkListViewModel.moveBookmark(bookmark, fromIndex: 1, toIndex: 0)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "2")
                Bookmark(id: "1")
                Bookmark(id: "3", isOrphaned: true)
                Bookmark(id: "4", isOrphaned: true)
                Bookmark(id: "5", isOrphaned: true)
                Bookmark(id: "6", isOrphaned: true)
            })
        }
    }

    func testDisplayNativeMode_WhenBookmarkIsFavoritedThenItIsAddedToNativeAndUnifiedFolders() async throws {

        bookmarkListViewModel.favoritesDisplayMode = .displayNative(.mobile)
        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            bookmarkListViewModel.reloadData()
            bookmarkListViewModel.toggleFavorite(bookmark)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            })
        }
    }

    func testDisplayNativeMode_WhenNonNativeFavoriteIsFavoritedThenItIsAddedToNativeFolder() async throws {

        bookmarkListViewModel.favoritesDisplayMode = .displayNative(.mobile)
        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.desktop, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            bookmarkListViewModel.reloadData()
            bookmarkListViewModel.toggleFavorite(bookmark)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1", favoritedOn: [.mobile, .desktop, .unified])
            })
        }
    }

    func testDisplayNativeMode_WhenNonNativeBrokenFavoriteIsFavoritedThenItIsAddedToNativeAndUnifiedFolder() async throws {

        bookmarkListViewModel.favoritesDisplayMode = .displayNative(.mobile)
        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.desktop])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            bookmarkListViewModel.reloadData()
            bookmarkListViewModel.toggleFavorite(bookmark)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1", favoritedOn: [.mobile, .desktop, .unified])
            })
        }
    }

    func testDisplayNativeMode_WhenFavoriteIsUnfavoritedThenItIsRemovedFromNativeAndUnifiedFolder() async throws {

        bookmarkListViewModel.favoritesDisplayMode = .displayNative(.mobile)
        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            bookmarkListViewModel.reloadData()
            bookmarkListViewModel.toggleFavorite(bookmark)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
            })
        }
    }

    func testDisplayNativeMode_WhenAllFormFactorsFavoriteIsUnfavoritedThenItIsOnlyRemovedFromNativeFolder() async throws {

        bookmarkListViewModel.favoritesDisplayMode = .displayNative(.mobile)
        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .desktop, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            bookmarkListViewModel.reloadData()
            bookmarkListViewModel.toggleFavorite(bookmark)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1", favoritedOn: [.desktop, .unified])
            })
        }
    }

    func testDisplayAllMode_WhenBookmarkIsFavoritedThenItIsAddedToNativeAndUnifiedFolders() async throws {

        bookmarkListViewModel.favoritesDisplayMode = .displayUnified(native: .mobile)
        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            bookmarkListViewModel.reloadData()
            bookmarkListViewModel.toggleFavorite(bookmark)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            })
        }
    }

    func testDisplayAllMode_WhenNonNativeFavoriteIsUnfavoritedThenItIsRemovedFromAllFolders() async throws {

        bookmarkListViewModel.favoritesDisplayMode = .displayUnified(native: .mobile)
        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.desktop, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            bookmarkListViewModel.reloadData()
            bookmarkListViewModel.toggleFavorite(bookmark)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
            })
        }
    }

    func testDisplayAllMode_WhenNonNativeBrokenFavoriteIsFavoritedThenItIsAddedToNativeAndUnifiedFolder() async throws {

        bookmarkListViewModel.favoritesDisplayMode = .displayUnified(native: .mobile)
        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.desktop])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            bookmarkListViewModel.reloadData()
            bookmarkListViewModel.toggleFavorite(bookmark)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1", favoritedOn: [.mobile, .desktop, .unified])
            })
        }
    }

    func testDisplayAllMode_WhenAllFormFactorsFavoriteIsUnfavoritedThenItIsRemovedFromAllFolders() async throws {

        bookmarkListViewModel.favoritesDisplayMode = .displayUnified(native: .mobile)
        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .desktop, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmark(withUUID: "1", context: context)!

            bookmarkListViewModel.reloadData()
            bookmarkListViewModel.toggleFavorite(bookmark)

            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree {
                Bookmark(id: "1")
            })
        }
    }

    func testWhenURLIsBookmarkThenEntityReturned() async throws {

        let context = bookmarkListViewModel.context

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", url: "https://example.com", favoritedOn: [.mobile, .desktop, .unified])
        }

        context.performAndWait {
            bookmarkTree.createEntities(in: context)
            try! context.save()
            XCTAssertNotNil(bookmarkListViewModel.bookmark(for: URL(string: "https://example.com")!))
            XCTAssertNil(bookmarkListViewModel.bookmark(for: URL(string: "https://example2.com")!))
        }
    }
}

extension BookmarkEntity {
    static func fetchBookmark(withUUID uuid: String, context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), uuid)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }
}
