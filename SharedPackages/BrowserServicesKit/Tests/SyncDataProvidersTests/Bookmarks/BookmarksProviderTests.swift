//
//  BookmarksProviderTests.swift
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

import XCTest
import Bookmarks
import BookmarksTestsUtils
import Common
import CoreData
import DDGSync
import Persistence
@testable import SyncDataProviders

internal class BookmarksProviderTests: BookmarksProviderTestsBase {

    func testThatLastSyncTimestampIsNilByDefault() {
        XCTAssertNil(provider.lastSyncTimestamp)
        XCTAssertNil(provider.lastSyncLocalTimestamp)
    }

    func testThatLastSyncTimestampIsPersisted() throws {
        try provider.registerFeature(withState: .readyToSync)
        let date = Date()
        provider.updateSyncTimestamps(server: "12345", local: date)
        XCTAssertEqual(provider.lastSyncTimestamp, "12345")
        XCTAssertEqual(provider.lastSyncLocalTimestamp, date)
    }

    func testThatPrepareForFirstSyncClearsLastSyncTimestampAndSetsModifiedAtForAllBookmarks() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("Bookmark 1", id: "1", favoritedOn: [.mobile, .unified])
            Bookmark("Bookmark 2", id: "2")
            Folder("Folder", id: "3") {
                Bookmark("Bookmark 4", id: "4")
            }
            Bookmark("Bookmark 5", id: "5")
            Bookmark("Bookmark 6", id: "6")
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        provider.updateSyncTimestamps(server: "12345", local: nil)
        try provider.prepareForFirstSync()
        XCTAssertNil(provider.lastSyncTimestamp)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!

            assertEquivalent(rootFolder, BookmarkTree(modifiedAtConstraint: .notNil()) {
                Bookmark("Bookmark 1", id: "1", favoritedOn: [.mobile, .unified], modifiedAtConstraint: .notNil())
                Bookmark("Bookmark 2", id: "2", modifiedAtConstraint: .notNil())
                Folder("Folder", id: "3", modifiedAtConstraint: .notNil()) {
                    Bookmark("Bookmark 4", id: "4", modifiedAtConstraint: .notNil())
                }
                Bookmark("Bookmark 5", id: "5", modifiedAtConstraint: .notNil())
                Bookmark("Bookmark 6", id: "6", modifiedAtConstraint: .notNil())
            })

            let favoritesFolders = BookmarkUtils.fetchFavoritesFolders(for: .displayUnified(native: .mobile), in: context)
            XCTAssertTrue(favoritesFolders.allSatisfy { $0.modifiedAt != nil })
        }
    }

    func testThatFetchChangedObjectsReturnsFavoritesFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        try provider.prepareForFirstSync()
        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))

        XCTAssertEqual(
            Set(changedObjects.compactMap(\.uuid)),
            BookmarkEntity.Constants.favoriteFoldersIDs.union(["1", BookmarkEntity.Constants.rootFolderID])
        )
    }

    func testThatFetchChangedObjectsReturnsAllObjectsWithNonNilModifiedAt() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Folder(id: "2") {
                Bookmark(id: "3")
                Bookmark(id: "4")
                Folder(id: "5") {
                    Bookmark(id: "6")
                }
            }
            Bookmark(id: "7")
            Bookmark(id: "8")
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()

            // clear modifiedAt for some entities
            let bookmarks = BookmarkEntity.fetchBookmarks(with: ["1", "4", "8"], in: context)
            bookmarks.forEach { $0.modifiedAt = nil }
            try! context.save()
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))

        XCTAssertEqual(
            Set(changedObjects.compactMap(\.uuid)),
            Set(["2", "3", "5", "6", "7"])
        )
    }

    func testThatFetchChangedObjectsFiltersOutInvalidBookmarksAndTruncatesFolderTitles() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let longTitle = String(repeating: "x", count: 10000)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1", favoritedOn: [.mobile, .unified])
            Folder(id: "2") {
                Bookmark(longTitle, id: "3")
                Bookmark(id: "4")
                Folder(longTitle, id: "5") {
                    Bookmark(id: "6")
                }
            }
            Bookmark(id: "7")
            Bookmark(id: "8")
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()

            // clear modifiedAt for some entities
            let bookmarks = BookmarkEntity.fetchBookmarks(with: ["1", "4", "8"], in: context)
            bookmarks.forEach { $0.modifiedAt = nil }
            try! context.save()
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))

        XCTAssertEqual(
            Set(changedObjects.compactMap(\.uuid)),
            Set(["2", "5", "6", "7"])
        )

        let folder5Syncable = try XCTUnwrap(changedObjects.first { $0.uuid == "5" })
        let expectedFolderTitle = try crypter.encryptAndBase64Encode(String(longTitle.prefix(Syncable.BookmarkValidationConstraints.maxFolderTitleLength)))
        XCTAssertEqual(folder5Syncable.encryptedTitle, expectedFolderTitle)
    }

    func testWhenBookmarkIsSoftDeletedThenFetchChangedObjectsReturnsBookmarkAndItsParent() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Folder(id: "2") {
                Bookmark(id: "3")
                Bookmark(id: "4")
                Bookmark(id: "5")
            }
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()

            // clear modifiedAt for all entities
            let bookmarks = BookmarkEntity.fetchBookmarks(with: ["1", "2", "3", "4", "5"], in: context)
            bookmarks.forEach { $0.modifiedAt = nil }
            try! context.save()

            let bookmark = BookmarkEntity.fetchBookmarks(with: ["4"], in: context).first
            XCTAssertNotNil(bookmark)
            bookmark?.markPendingDeletion()
            try! context.save()
        }

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))
        let changedFolder = try XCTUnwrap(changedObjects.first(where: { $0.uuid == "2" }))

        XCTAssertEqual(Set(changedObjects.compactMap(\.uuid)), Set(["2", "4"]))
        XCTAssertEqual(changedFolder.children, ["3", "5"])
    }

    func testThatSentItemsAreProperlyCleanedUp() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("Bookmark 1", id: "1")
            Bookmark("Bookmark 2", id: "2", isDeleted: true)
            Folder("Folder", id: "3", isDeleted: true) {
                Bookmark("Bookmark 4", id: "4", isDeleted: true)
            }
            Bookmark("Bookmark 5", id: "5")
            Bookmark("Bookmark 6", id: "6")
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!

            assertEquivalent(rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "5", "6"]) {
                Bookmark("Bookmark 1", id: "1")
                Bookmark("Bookmark 5", id: "5")
                Bookmark("Bookmark 6", id: "6")
            })
        }
    }

    func testThatItemsThatFailedValidationRetainTheirTimestamps() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let longValue = String(repeating: "x", count: 10000)
        let timestamp = Date()

        let bookmarkTree = BookmarkTree {
            Bookmark("Bookmark 1", id: "1", url: longValue, modifiedAt: timestamp)
            Bookmark("Bookmark 2", id: "2", modifiedAt: timestamp)
            Folder(longValue, id: "3", modifiedAt: timestamp) {
                Bookmark("Bookmark 4", id: "4", modifiedAt: timestamp)
            }
            Bookmark(longValue, id: "5", modifiedAt: timestamp)
            Bookmark("Bookmark 6", id: "6", modifiedAt: timestamp)
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        try await provider.handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!

            assertEquivalent(withTimestamps: true, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2", "3", "5", "6"]) {
                Bookmark("Bookmark 1", id: "1", url: longValue, modifiedAt: timestamp)
                Bookmark("Bookmark 2", id: "2")
                // folder is accepted, its name is truncated for sync but full value is retained locally
                Folder(longValue, id: "3", lastChildrenArrayReceivedFromSync: ["4"]) {
                    Bookmark("Bookmark 4", id: "4")
                }
                Bookmark(longValue, id: "5", modifiedAt: timestamp)
                Bookmark("Bookmark 6", id: "6")
            })
        }
    }

    // MARK: - Initial Sync

    func testThatInitialSyncIntoEmptyDatabaseClearsModifiedAtFromAllReceivedObjects() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let received: [Syncable] = [
            .rootFolder(children: ["1", "4", "5"]),
            .folder(id: "1", children: ["2", "3"]),
            .bookmark(id: "2"),
            .bookmark(id: "3"),
            .bookmark(id: "4"),
            .bookmark(id: "5")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
        }

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "4", "5"]) {
                Folder(id: "1", lastChildrenArrayReceivedFromSync: ["2", "3"]) {
                    Bookmark(id: "2")
                    Bookmark(id: "3")
                }
                Bookmark(id: "4")
                Bookmark(id: "5")
            })
        }
    }

    func testThatInitialSyncClearsModifiedAtFromDeduplicatedBookmark() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1", url: "test")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["2"]),
            .bookmark("test", id: "2", url: "test")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["2"]) {
                Bookmark("test", id: "2", url: "test")
            })
        }
    }

    func testWhenInitialSyncAppendsBookmarksToRootFolderThenRootFolderIsMarkedAsModified() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["3", "4"]),
            .bookmark(id: "3"),
            .bookmark(id: "4")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let clientTimestamp = Date()
        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: clientTimestamp, serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree(modifiedAtConstraint: .notNil(), lastChildrenArrayReceivedFromSync: ["3", "4"]) {
                Bookmark(id: "1", modifiedAtConstraint: .notNil())
                Bookmark(id: "2", modifiedAtConstraint: .notNil())
                Bookmark(id: "3", modifiedAtConstraint: .nil())
                Bookmark(id: "4", modifiedAtConstraint: .nil())
            })
        }
    }

    func testWhenInitialSyncAppendsBookmarksToDuplicateFolderThenFolderIsDeduplicatedAndMarkedAsModified() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder("Folder", id: "1") {
                Bookmark(id: "2")
                Bookmark(id: "3")
            }
        }

        let received: [Syncable] = [
            .rootFolder(children: ["4"]),
            .folder("Folder", id: "4", children: ["5", "6"]),
            .bookmark(id: "5"),
            .bookmark(id: "6")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let clientTimestamp = Date()
        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: clientTimestamp, serverTimestamp: "1234", crypter: crypter)

        context.performAndWait {
            context.refreshAllObjects()
            let rootFolder = BookmarkUtils.fetchRootFolder(context)!
            assertEquivalent(rootFolder, BookmarkTree(modifiedAtConstraint: .nil(), lastChildrenArrayReceivedFromSync: ["4"]) {
                Folder("Folder", id: "4", modifiedAtConstraint: .greaterThan(clientTimestamp), lastChildrenArrayReceivedFromSync: ["5", "6"]) {
                    Bookmark(id: "2", modifiedAtConstraint: .notNil())
                    Bookmark(id: "3", modifiedAtConstraint: .notNil())
                    Bookmark(id: "5", modifiedAtConstraint: .nil())
                    Bookmark(id: "6", modifiedAtConstraint: .nil())
                }
            })
        }
    }

    func testWhenInitialSyncAppendsBookmarksToEmptyDuplicateFolderThenFolderIsDeduplicatedAndNotMarkedAsModified() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder("Folder", id: "1")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["4"]),
            .folder("Folder", id: "4", children: ["5", "6"]),
            .bookmark(id: "5"),
            .bookmark(id: "6")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let clientTimestamp = Date()
        let rootFolder = try await handleInitialSyncResponse(received: received, clientTimestamp: clientTimestamp, serverTimestamp: "1234", in: context)
        assertEquivalent(rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["4"]) {
            Folder("Folder", id: "4", lastChildrenArrayReceivedFromSync: ["5", "6"]) {
                Bookmark(id: "5")
                Bookmark(id: "6")
            }
        })
    }

    func testWhenThereIsMergeConflictDuringInitialSyncThenSyncResponseHandlingIsRetried() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .bookmark("test", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            try! context.save()
        }

        var willSaveCallCount = 0

        var bookmarkModificationDate: Date?
        provider.willSaveContextAfterApplyingSyncResponse = {
            willSaveCallCount += 1
            if bookmarkModificationDate != nil {
                return
            }
            context.performAndWait {
                let bookmarkTree = BookmarkTree {
                    Bookmark("test-local", id: "1")
                }
                let (rootFolder, _) = bookmarkTree.createEntities(in: context)
                // skip setting modifiedAt for rootFolder to keep unit test simpler (we don't care about checking modifiedAt for rootFolder here)
                rootFolder.shouldManageModifiedAt = false
                try! context.save()
                bookmarkModificationDate = rootFolder.childrenArray.first!.modifiedAt
            }
        }
        let rootFolder = try await handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)

        XCTAssertEqual(willSaveCallCount, 2)

        assertEquivalent(rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1"]) {
            Bookmark("test-local", id: "1", modifiedAt: bookmarkModificationDate)
        })
    }

    // MARK: - Regular Sync

    func testWhenObjectDeleteIsSentAndTheSameObjectDeleteIsReceivedThenObjectIsDeleted() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1", isDeleted: true)
        }

        let received: [Syncable] = [
            .rootFolder(children: []),
            .bookmark("test2", id: "1", isDeleted: true)
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        let rootFolder = try await handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: []) {})
    }

    func testWhenObjectDeleteIsSentAndTheSameObjectUpdateIsReceivedThenObjectIsNotDeleted() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1", isDeleted: true)
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .bookmark("test2", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        let rootFolder = try await handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1"]) {
            Bookmark("test2", id: "1")
        })
    }

    func testWhenObjectDeleteIsSentAndTheSameObjectUpdateIsReceivedWithoutParentFolderThenObjectIsNotDeleted() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1", isDeleted: true)
        }

        let received: [Syncable] = [
            .bookmark("test2", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        let rootFolder = try await handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withLastChildrenArrayReceivedFromSync: false, rootFolder, BookmarkTree {
            Bookmark("test2", id: "1")
        })
    }

    func testWhenObjectDeleteIsSentAndTheSameObjectUpdateIsReceivedThenObjectIsNotDeletedAndIsNotMovedWithinFolder() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1", isDeleted: true)
            Bookmark(id: "2")
        }

        let received: [Syncable] = [
            .bookmark("test2", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        let rootFolder = try await handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withLastChildrenArrayReceivedFromSync: false, rootFolder, BookmarkTree {
            Bookmark("test2", id: "1")
            Bookmark(id: "2")
        })
    }

    func testWhenFolderUpdateIsSentAndTheSameFolderUpdateIsReceivedThenServerVersionIsApplied() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1", isDeleted: true)
        }

        let received: [Syncable] = [
            .rootFolder(children: ["2"]),
            .bookmark("test2", id: "2")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        let rootFolder = try await handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["2"]) {
            Bookmark("test2", id: "2")
        })
    }

    func testWhenObjectWasSentAndThenDeletedLocallyAndAnUpdateIsReceivedThenTheObjectIsDeleted() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let modifiedAt = Date()
        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .bookmark("test2", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        context.performAndWait {
            let bookmark = BookmarkEntity.fetchBookmarks(with: ["1"], in: context).first!
            bookmark.markPendingDeletion()
            try! context.save()
        }

        let rootFolder = try await handleSyncResponse(sent: sent, received: received, clientTimestamp: modifiedAt.addingTimeInterval(-1), serverTimestamp: "1234", in: context)
        XCTAssertTrue(rootFolder.childrenArray.isEmpty)
    }

    func testWhenObjectWasUpdatedLocallyAfterStartingSyncThenRemoteChangesAreDropped() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .bookmark("test2", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        var bookmarkModificationDate: Date?

        context.performAndWait {
            let bookmark = BookmarkEntity.fetchBookmarks(with: ["1"], in: context).first!
            bookmark.title = "test3"
            try! context.save()
            bookmarkModificationDate = bookmark.modifiedAt
        }

        let rootFolder = try await handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().addingTimeInterval(-1), serverTimestamp: "1234", in: context)
        assertEquivalent(rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1"]) {
            Bookmark("test3", id: "1", url: "test", modifiedAt: bookmarkModificationDate)
        })
    }

    func testWhenObjectWasUpdatedLocallyAfterStartingSyncThenRemoteDeletionIsApplied() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1")
        }

        let received: [Syncable] = [
            .rootFolder(children: []),
            .bookmark("test2", id: "1", isDeleted: true)
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        context.performAndWait {
            let bookmark = BookmarkEntity.fetchBookmarks(with: ["1"], in: context).first!
            bookmark.title = "test3"
            try! context.save()
        }

        let rootFolder = try await handleSyncResponse(sent: sent, received: received, clientTimestamp: Date().addingTimeInterval(-1), serverTimestamp: "1234", in: context)
        assertEquivalent(rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: []) {})
    }

    func testWhenBookmarkIsMovedBetweenFoldersRemotelyAndUpdatedLocallyAfterStartingSyncThenItsModifiedAtIsNotCleared() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "1") {
                Bookmark("test", id: "3")
            }
            Folder(id: "2")
        }

        let received: [Syncable] = [
            .folder(id: "1", children: []),
            .folder(id: "2", children: ["3"])
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()

            // clear modifiedAt for all entities
            let bookmarks = BookmarkEntity.fetchBookmarks(with: ["1", "2", "3"], in: context)
            bookmarks.forEach { $0.modifiedAt = nil }
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        var bookmarkModificationDate: Date!

        context.performAndWait {
            let bookmark = BookmarkEntity.fetchBookmarks(with: ["3"], in: context).first!
            bookmark.title = "test3"
            try! context.save()
            bookmarkModificationDate = bookmark.modifiedAt
        }

        let rootFolder = try await handleSyncResponse(sent: sent, received: received, clientTimestamp: bookmarkModificationDate.addingTimeInterval(-1), serverTimestamp: "1234", in: context)
        assertEquivalent(withLastChildrenArrayReceivedFromSync: false, rootFolder, BookmarkTree {
            Folder(id: "1")
            Folder(id: "2") {
                Bookmark("test3", id: "3", url: "test", modifiedAt: bookmarkModificationDate)
            }
        })
    }

    func testWhenThereIsMergeConflictDuringRegularSyncThenSyncResponseHandlingIsRetried() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .bookmark("test2", id: "1")
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        var bookmarkModificationDate: Date?
        provider.willSaveContextAfterApplyingSyncResponse = {
            if bookmarkModificationDate != nil {
                return
            }
            context.performAndWait {
                let bookmark = BookmarkEntity.fetchBookmarks(with: ["1"], in: context).first!
                bookmark.title = "test3"
                try! context.save()
                bookmarkModificationDate = bookmark.modifiedAt
            }
        }
        let rootFolder = try await handleSyncResponse(sent: sent, received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1"]) {
            Bookmark("test3", id: "1", url: "test", modifiedAt: bookmarkModificationDate)
        })
    }

    // MARK: - syncDidFinish callback

    func testThatSyncDidFinishCallbackReportsModifiedAndDeletedObjectIDs() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark("test", id: "1")
            Bookmark("test2", id: "2")
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "3"]),
            .bookmark("test1", id: "1"),
            .bookmark("test3", id: "3"),
            .bookmark(id: "2", isDeleted: true)
        ]

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        expectedSyncResult = .newData(modifiedIds: ["1", "3", "bookmarks_root"], deletedIds: ["2"])

        let rootFolder = try await handleSyncResponse(sent: [], received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "3"]) {
            Bookmark("test1", id: "1")
            Bookmark("test3", id: "3")
        })
    }

    // MARK: - Last Children Array Received From Sync

    func testThatLastChildrenArrayIsUpdatedAfterEveryHandledResponse() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2")
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        var received: [Syncable] = [
            .rootFolder(children: ["3"]),
            .bookmark(id: "3")
        ]

        var rootFolder = try await handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["3"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "3")
        })

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        rootFolder = try await handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2", "3"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "3")
        })

        received = [
            .rootFolder(children: ["1", "2", "3", "4"]),
            .bookmark(id: "4")
        ]

        rootFolder = try await handleSyncResponse(sent: [], received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2", "3", "4"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "3")
            Bookmark(id: "4")
        })
    }

    // MARK: - Changes to Folders without changes to their children

    func testThatWhenBookmarkIsMovedBetweenFoldersThenItsModifiedAtIsNotSet() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "1") {
                Bookmark(id: "3")
            }
            Folder(id: "2")
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        // send existing items to clear modifiedAt
        _ = try await handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", in: context)

        let received: [Syncable] = [
            .folder(id: "1"),
            .folder(id: "2", children: ["3"])
        ]

        let rootFolder = try await handleSyncResponse(sent: [], received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withTimestamps: true, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: nil) {
            Folder(id: "1", modifiedAt: nil, lastChildrenArrayReceivedFromSync: [])
            Folder(id: "2", modifiedAt: nil, lastChildrenArrayReceivedFromSync: ["3"]) {
                Bookmark(id: "3", modifiedAt: nil)
            }
        })
    }

    func testThatWhenBookmarkFavoriteFoldersChangeThenItsModifiedAtIsNotSet() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "2", favoritedOn: [.mobile])
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let received: [Syncable] = [
            .mobileFavoritesFolder(favorites: ["1"])
        ]

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        // send existing items to clear modifiedAt
        _ = try await handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", in: context)

        let rootFolder = try await handleSyncResponse(sent: [], received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withTimestamps: true, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: nil) {
            Bookmark(id: "1", favoritedOn: [.mobile], modifiedAt: nil)
            Bookmark(id: "2", modifiedAt: nil)
        })
    }

    func testThatWhenBookmarkFavoriteFoldersAndParentChangeThenItsModifiedAtIsNotSet() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Folder(id: "1") {
                Bookmark(id: "3")
            }
            Folder(id: "2")
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let received: [Syncable] = [
            .mobileFavoritesFolder(favorites: ["3"]),
            .folder(id: "1"),
            .folder(id: "2", children: ["3"])
        ]

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)
        // send existing items to clear modifiedAt
        _ = try await handleSyncResponse(sent: sent, received: [], clientTimestamp: Date(), serverTimestamp: "1234", in: context)

        let rootFolder = try await handleSyncResponse(sent: [], received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withTimestamps: true, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: nil) {
            Folder(id: "1", lastChildrenArrayReceivedFromSync: [])
            Folder(id: "2", lastChildrenArrayReceivedFromSync: ["3"]) {
                Bookmark(id: "3", favoritedOn: [.mobile], modifiedAt: nil)
            }
        })
    }

    // MARK: - Stubs

    func testThatLastChildrenArrayTakesIntoAccountStubs() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {}

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2"]), // Creates a Stub with id 2
            .bookmark(id: "1")
        ]

        let rootFolder = try await handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2"]) {
            Bookmark(id: "1")
            Bookmark(id: "2", isStub: true)
        })

        // Add new bookmark with id 3
        context.performAndWait {
            let root = BookmarkUtils.fetchRootFolder(context)!
            let newBookmark = BookmarkEntity.makeBookmark(title: "3", url: "3", parent: root, context: context)
            newBookmark.uuid = "3"
            try! context.save()
        }

        let sent = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        // Only Root and "3" should be sent
        XCTAssertEqual(sent.count, 2)

        let sentRootData = sent.first(where: { $0.payload["id"] as? String == rootFolder.uuid })
        XCTAssertNotNil(sentRootData)
        let folderChanges = sentRootData?.payload["folder"] as? [String: [String: [String]]]
        XCTAssertNotNil(folderChanges)

        // We expect to send create for 3
        XCTAssertEqual(folderChanges?["children"]?["insert"], ["3"])

        // Ensure there is no removal for 2
        XCTAssertNil(folderChanges?["children"]?["remove"])
    }

    func testThatPatchPreservesOrderWithStubs() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {}

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let received: [Syncable] = [
            .rootFolder(children: ["2", "1", "3"]), // Create Stubs with id 2 and 3
            .favoritesFolder(favorites: ["3", "1", "2"]),
            .bookmark(id: "1")
        ]

        let rootFolder = try await handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["2", "1", "3"]) {
            Bookmark(id: "2", favoritedOn: [.unified], isStub: true)
            Bookmark(id: "1", favoritedOn: [.unified])
            Bookmark(id: "3", favoritedOn: [.unified], isStub: true)
        })

        context.performAndWait {
            let bookmarks = BookmarkEntity.fetchBookmarks(with: ["1", "2", "3"], in: context)
            bookmarks.forEach { $0.modifiedAt = nil }

            let favoriteFolder = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.unified.rawValue, in: context)
            favoriteFolder?.modifiedAt = Date()
            rootFolder.modifiedAt = Date()
            try! context.save()
        }

        let patchData = try await provider.fetchChangedObjects(encryptedUsing: crypter)

        let changedObjects = patchData.map(SyncableBookmarkAdapter.init(syncable:))

        XCTAssertEqual(changedObjects.count, 2)
        let changedRoot = changedObjects.first(where: { $0.uuid == BookmarkEntity.Constants.rootFolderID })
        let changedFavRoot = changedObjects.first(where: { BookmarkEntity.Constants.favoriteFoldersIDs.contains($0.uuid!) })
        XCTAssertEqual(changedRoot?.children, ["2", "1", "3"])
        XCTAssertEqual(changedFavRoot?.children, ["3", "1", "2"])
    }

    func testThatRemoteRemovalOfStubReferenceRemovesTheStub() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {}

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1", "2", "3"]), // Create Stubs with id 2 and 3
            .bookmark(id: "1")
        ]

        var rootFolder = try await handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2", "3"]) {
            Bookmark(id: "1")
            Bookmark(id: "2", isStub: true)
            Bookmark(id: "3", isStub: true)
        })

        // Simulate two kinds of "removal":
        // - "2" is only removed from children list.
        // - "3" is removed from children list and deleted.
        let receivedUpdate: [Syncable] = [
            .rootFolder(children: ["1"]),
            .bookmark(id: "3", isDeleted: true)
        ]

        rootFolder = try await handleSyncResponse(sent: [], received: receivedUpdate, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1"]) {
            Bookmark(id: "1")
        })
    }

    func testThatRemoteRemovalOfFolderRemovesTheStub() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {}

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        let received: [Syncable] = [
            .rootFolder(children: ["1"]),
            .folder(id: "1", children: ["2"])
        ]

        var rootFolder = try await handleInitialSyncResponse(received: received, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: ["1"]) {
            Folder(id: "1", lastChildrenArrayReceivedFromSync: ["2"]) {
                Bookmark(id: "2", isStub: true)
            }
        })

        let receivedUpdate: [Syncable] = [
            .rootFolder(children: []),
            .folder(id: "1", isDeleted: true)
        ]

        rootFolder = try await handleSyncResponse(sent: [], received: receivedUpdate, clientTimestamp: Date(), serverTimestamp: "1234", in: context)
        assertEquivalent(withTimestamps: false, rootFolder, BookmarkTree(lastChildrenArrayReceivedFromSync: []) {
        })
    }

    // MARK: - Helpers

    func handleInitialSyncResponse(
        received: [Syncable],
        clientTimestamp: Date,
        serverTimestamp: String?,
        in context: NSManagedObjectContext
    ) async throws -> BookmarkEntity {

        try await provider.handleInitialSyncResponse(received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
        var rootFolder: BookmarkEntity!
        context.performAndWait {
            context.refreshAllObjects()
            rootFolder = BookmarkUtils.fetchRootFolder(context)
        }
        return rootFolder
    }

    func handleSyncResponse(
        sent: [Syncable],
        received: [Syncable],
        clientTimestamp: Date,
        serverTimestamp: String?,
        in context: NSManagedObjectContext
    ) async throws -> BookmarkEntity {

        try await provider.handleSyncResponse(sent: sent, received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
        var rootFolder: BookmarkEntity!
        context.performAndWait {
            context.refreshAllObjects()
            rootFolder = BookmarkUtils.fetchRootFolder(context)
        }
        return rootFolder
    }
}
