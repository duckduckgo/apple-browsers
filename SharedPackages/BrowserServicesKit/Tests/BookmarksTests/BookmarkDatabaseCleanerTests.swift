//
//  BookmarkDatabaseCleanerTests.swift
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

import Common
import CoreData
import Foundation
import Persistence
import XCTest
@testable import Bookmarks

final class MockEventMapper: EventMapping<BookmarksCleanupError> {
    static var errors: [Error] = []

    public init() {
        super.init { event, _, _, _ in
            Self.errors.append(event.cleanupError)
        }
    }

    override init(mapping: @escaping EventMapping<BookmarksCleanupError>.Mapping) {
        fatalError("Use init()")
    }
}

final class BookmarkDatabaseCleanerTests: XCTestCase {
    var bookmarksDatabase: CoreDataDatabase!
    var location: URL!
    var databaseCleaner: BookmarkDatabaseCleaner!
    var eventMapper: MockEventMapper!

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

        eventMapper = MockEventMapper()
        MockEventMapper.errors.removeAll()
    }

    override func tearDown() {
        super.tearDown()

        try? bookmarksDatabase.tearDown(deleteStores: true)
        bookmarksDatabase = nil
        try? FileManager.default.removeItem(at: location)
    }

    func testWhenSyncIsActiveThenCleanupIsCancelled() throws {
        let expectation = expectation(description: "fetchBookmarksPendingDeletion")
        expectation.isInverted = true

        databaseCleaner = BookmarkDatabaseCleaner(
            bookmarkDatabase: bookmarksDatabase,
            errorEvents: eventMapper,
            fetchBookmarksPendingDeletion: { _ in
                expectation.fulfill()
                return []
            }
        )

        databaseCleaner.isSyncActive = { true }

        databaseCleaner.removeBookmarksPendingDeletion()

        waitForExpectations(timeout: 1)
        XCTAssertEqual(MockEventMapper.errors.count, 1)
        let error = try XCTUnwrap(MockEventMapper.errors.first)
        XCTAssertTrue(error is BookmarksCleanupCancelledError)
    }

    func testWhenThereAreNoConflictsThenCleanerContextIsSavedOnce() {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        var bookmarkUUID: String!
        var fetchBookmarksPendingDeletionCallCount = 0

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let folder1 = makeFolder(named: "Folder 1", in: context)
            let bookmark = makeBookmark(withParent: folder1, in: context)

            do {
                try context.save()
            } catch {
                XCTFail("failed to save context")
            }
            bookmarkUUID = bookmark.uuid
        }

        context.performAndWait {
            let bookmark = fetchBookmarkOrFolder(with: bookmarkUUID, in: context)!
            bookmark.markPendingDeletion()
            do {
                try context.save()
            } catch {
                XCTFail("failed to save context")
            }
        }

        databaseCleaner = BookmarkDatabaseCleaner(
            bookmarkDatabase: bookmarksDatabase,
            errorEvents: eventMapper,
            fetchBookmarksPendingDeletion: { cleanerContext in
                fetchBookmarksPendingDeletionCallCount += 1
                return BookmarkUtils.fetchBookmarksPendingDeletion(cleanerContext)
            }
        )
        databaseCleaner.removeBookmarksPendingDeletion()

        context.performAndWait {
            let bookmark = fetchBookmarkOrFolder(with: bookmarkUUID, in: context)
            XCTAssertNil(bookmark)
        }

        XCTAssertTrue(MockEventMapper.errors.isEmpty)
        XCTAssertEqual(fetchBookmarksPendingDeletionCallCount, 1)
    }

    func testWhenThereIsMergeConflictThenCleanupIsRetried() throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        var bookmarkUUID: String!
        var folder2UUID: String!
        var fetchBookmarksPendingDeletionCallCount = 0

        // Create Folder 1, Folder 2, and Bookmark inside Folder 1
        // Mark Bookmark for deletion
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            let folder1 = makeFolder(named: "Folder 1", in: context)
            let folder2 = makeFolder(named: "Folder 2", in: context)
            let bookmark = makeBookmark(withParent: folder1, in: context)
            bookmark.markPendingDeletion()

            do {
                try context.save()
            } catch {
                XCTFail("failed to save context")
            }
            bookmarkUUID = bookmark.uuid
            folder2UUID = folder2.uuid
        }

        databaseCleaner = BookmarkDatabaseCleaner(
            bookmarkDatabase: bookmarksDatabase,
            errorEvents: eventMapper,
            fetchBookmarksPendingDeletion: { [weak self] cleanerContext in
                fetchBookmarksPendingDeletionCallCount += 1
                let bookmarks = BookmarkUtils.fetchBookmarksPendingDeletion(cleanerContext)

                // After fetching bookmarks pending deletion, move the bookmark to Folder 2 in a different context
                // to create a merge conflict
                if bookmarks.first?.parent?.title != "Folder 2" {
                    context.performAndWait {
                        let bookmark = self!.fetchBookmarkOrFolder(with: bookmarkUUID, in: context)!
                        let folder2 = self!.fetchBookmarkOrFolder(with: folder2UUID, in: context)!

                        bookmark.parent = folder2
                        do {
                            try context.save()
                        } catch {
                            XCTFail("failed to save context")
                        }
                    }
                }

                return bookmarks
            }
        )

        databaseCleaner.removeBookmarksPendingDeletion()

        context.performAndWait {
            let bookmark = fetchBookmarkOrFolder(with: bookmarkUUID, in: context)
            XCTAssertNil(bookmark)
        }

        XCTAssertTrue(MockEventMapper.errors.isEmpty)
        XCTAssertEqual(fetchBookmarksPendingDeletionCallCount, 2)
    }

    private func makeFolder(named title: String, with parent: BookmarkEntity? = nil, in context: NSManagedObjectContext) -> BookmarkEntity {
        let parentFolder = parent ?? BookmarkUtils.fetchRootFolder(context)!
        return BookmarkEntity.makeFolder(title: title, parent: parentFolder, context: context)
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

    public func fetchBookmarkOrFolder(with uuid: String, in context: NSManagedObjectContext) -> BookmarkEntity? {
        let request = BookmarkEntity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), uuid)
        request.fetchLimit = 1

        return try? context.fetch(request).first
    }
}
