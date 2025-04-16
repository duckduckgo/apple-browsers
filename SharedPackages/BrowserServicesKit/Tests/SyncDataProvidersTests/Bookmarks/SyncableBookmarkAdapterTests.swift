//
//  SyncableBookmarkAdapterTests.swift
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
import DDGSync
import Persistence
@testable import SyncDataProviders

final class SyncableBookmarkAdapterTests: BookmarksProviderTestsBase {

    func testThatLastChildrenArrayReceivedFromSyncIsSerializedAndDeserializedCorrectly() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let bookmarkEntity = BookmarkEntity(context: context)

        bookmarkEntity.lastChildrenArrayReceivedFromSync = nil
        XCTAssertEqual(bookmarkEntity.lastChildrenArrayReceivedFromSync, nil)

        bookmarkEntity.lastChildrenArrayReceivedFromSync = []
        XCTAssertEqual(bookmarkEntity.lastChildrenArrayReceivedFromSync, [])

        bookmarkEntity.lastChildrenArrayReceivedFromSync = ["1"]
        XCTAssertEqual(bookmarkEntity.lastChildrenArrayReceivedFromSync, ["1"])

        bookmarkEntity.lastChildrenArrayReceivedFromSync = [""]
        XCTAssertEqual(bookmarkEntity.lastChildrenArrayReceivedFromSync, [])

        bookmarkEntity.lastChildrenArrayReceivedFromSync = ["1", "2", "3"]
        XCTAssertEqual(bookmarkEntity.lastChildrenArrayReceivedFromSync, ["1", "2", "3"])
    }

    func testThatLastChildrenArrayReceivedFromSyncIgnoresEmptyIdentifiers() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let bookmarkEntity = BookmarkEntity(context: context)

        bookmarkEntity.lastChildrenArrayReceivedFromSync = [""]
        XCTAssertEqual(bookmarkEntity.lastChildrenArrayReceivedFromSync, [])

        bookmarkEntity.lastChildrenArrayReceivedFromSync = ["", "", ""]
        XCTAssertEqual(bookmarkEntity.lastChildrenArrayReceivedFromSync, [])

        bookmarkEntity.lastChildrenArrayReceivedFromSync = ["", "1", "", "", "2", ""]
        XCTAssertEqual(bookmarkEntity.lastChildrenArrayReceivedFromSync, ["1", "2"])
    }

    func testThatAddingBookmarksToRootFolderReportsAllBookmarksAsInserted() async throws {
        let bookmarkTree = BookmarkTree(modifiedAt: Date(), lastChildrenArrayReceivedFromSync: []) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "16")
            Bookmark(id: "3")
            Bookmark(id: "4")
        }
        populateBookmarks(with: bookmarkTree)

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))

        let rootFolderSyncable = try XCTUnwrap(changedObjects.first { $0.uuid == BookmarkEntity.Constants.rootFolderID })
        XCTAssertEqual(rootFolderSyncable.children, ["1", "2", "16", "3", "4"])
        XCTAssertEqual(rootFolderSyncable.inserted, ["1", "2", "16", "3", "4"])
        XCTAssertEqual(rootFolderSyncable.removed, nil)
    }

    func testThatAddingBookmarksToSubfolderReportsAllBookmarksAsInserted() async throws {
        let bookmarkTree = BookmarkTree(lastChildrenArrayReceivedFromSync: ["1", "2", "5", "16", "3", "4"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "5", lastChildrenArrayReceivedFromSync: []) {
                Bookmark(id: "7")
                Bookmark(id: "6")
                Bookmark(id: "8")
            }
            Bookmark(id: "16")
            Bookmark(id: "3")
            Bookmark(id: "4")
        }
        populateBookmarks(with: bookmarkTree)

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))

        let rootFolderSyncable = try XCTUnwrap(changedObjects.first { $0.uuid == "5" })
        XCTAssertEqual(rootFolderSyncable.children, ["7", "6", "8"])
        XCTAssertEqual(rootFolderSyncable.inserted, ["7", "6", "8"])
        XCTAssertEqual(rootFolderSyncable.removed, nil)
    }

    func testThatDeletingAllBookmarksReportsAllBookmarksAsRemoved() async throws {
        let timestamp = Date()
        let bookmarkTree = BookmarkTree(modifiedAt: timestamp, lastChildrenArrayReceivedFromSync: ["1", "4", "3", "16", "2"]) {
            Bookmark(id: "1", isDeleted: true)
            Bookmark(id: "2", isDeleted: true)
            Bookmark(id: "16", isDeleted: true)
            Bookmark(id: "3", isDeleted: true)
            Bookmark(id: "4", isDeleted: true)
        }
        populateBookmarks(with: bookmarkTree)

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))

        let rootFolderSyncable = try XCTUnwrap(changedObjects.first { $0.uuid == BookmarkEntity.Constants.rootFolderID })
        XCTAssertEqual(rootFolderSyncable.children, [])
        XCTAssertEqual(rootFolderSyncable.inserted, nil)
        XCTAssertEqual(rootFolderSyncable.removed, ["1", "2", "16", "3", "4"])
    }

    func testThatDeletingAllBookmarksFromSubfolderReportsAllBookmarksAsRemoved() async throws {
        let timestamp = Date()
        let bookmarkTree = BookmarkTree(modifiedAt: timestamp, lastChildrenArrayReceivedFromSync: ["1", "2", "5", "16", "3", "4"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "5", lastChildrenArrayReceivedFromSync: ["7", "6", "8"]) {
                Bookmark(id: "7", isDeleted: true)
                Bookmark(id: "6", isDeleted: true)
                Bookmark(id: "8", isDeleted: true)
            }
            Bookmark(id: "16")
            Bookmark(id: "3")
            Bookmark(id: "4")
        }
        populateBookmarks(with: bookmarkTree)

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))

        let rootFolderSyncable = try XCTUnwrap(changedObjects.first { $0.uuid == "5" })
        XCTAssertEqual(rootFolderSyncable.children, [])
        XCTAssertEqual(rootFolderSyncable.inserted, nil)
        XCTAssertEqual(rootFolderSyncable.removed, ["7", "6", "8"])
    }

    func testThatUponInitialSyncFolderOnlySubmitsChildrenWithoutInsertedOrRemoved() async throws {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)

        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "4")
            Bookmark(id: "3")
            Bookmark(id: "16")
            Bookmark(id: "2")
        }

        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }

        try provider.prepareForFirstSync()
        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))

        let rootFolderSyncable = try XCTUnwrap(changedObjects.first { $0.uuid == BookmarkEntity.Constants.rootFolderID })
        XCTAssertEqual(rootFolderSyncable.children, ["1", "4", "3", "16", "2"])
        XCTAssertEqual(rootFolderSyncable.inserted, ["1", "4", "3", "16", "2"])
        XCTAssertEqual(rootFolderSyncable.removed, nil)
    }

    func testThatUponInitialSyncSubfolderOnlySubmitsChildrenWithoutInsertedOrRemoved() async throws {
        let bookmarkTree = BookmarkTree {
            Bookmark(id: "1")
            Bookmark(id: "4")
            Folder(id: "5", lastChildrenArrayReceivedFromSync: ["7", "6", "8"]) {
                Bookmark(id: "7")
                Bookmark(id: "6")
                Bookmark(id: "8")
            }
            Bookmark(id: "3")
            Bookmark(id: "16")
            Bookmark(id: "2")
        }
        populateBookmarks(with: bookmarkTree)

        try provider.prepareForFirstSync()
        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))

        let rootFolderSyncable = try XCTUnwrap(changedObjects.first { $0.uuid == "5" })
        XCTAssertEqual(rootFolderSyncable.children, ["7", "6", "8"])
        XCTAssertEqual(rootFolderSyncable.inserted, ["7", "6", "8"])
        XCTAssertEqual(rootFolderSyncable.removed, nil)
    }

    func testThatNewChildrenOfExistingFolderAreReportedAsInserted() async throws {
        let timestamp = Date()
        let bookmarkTree = BookmarkTree(modifiedAt: timestamp, lastChildrenArrayReceivedFromSync: ["1", "4", "3"]) {
            Bookmark(id: "1")
            Bookmark(id: "4")
            Bookmark(id: "3")
            Bookmark(id: "16", modifiedAt: timestamp)
            Bookmark(id: "2", modifiedAt: timestamp)
        }
        populateBookmarks(with: bookmarkTree)

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))

        let rootFolderSyncable = try XCTUnwrap(changedObjects.first { $0.uuid == BookmarkEntity.Constants.rootFolderID })
        XCTAssertEqual(rootFolderSyncable.children, ["1", "4", "3", "16", "2"])
        XCTAssertEqual(rootFolderSyncable.inserted, ["16", "2"])
        XCTAssertEqual(rootFolderSyncable.removed, nil)
    }

    func testThatDeletedChildrenOfExistingFolderAreReportedAsRemoved() async throws {
        let timestamp = Date()
        let bookmarkTree = BookmarkTree(modifiedAt: timestamp, lastChildrenArrayReceivedFromSync: ["1", "4", "3", "16", "2"]) {
            Bookmark(id: "1")
            Bookmark(id: "4")
            Bookmark(id: "3")
            Bookmark(id: "16", modifiedAt: timestamp, isDeleted: true)
            Bookmark(id: "2", modifiedAt: timestamp, isDeleted: true)
        }
        populateBookmarks(with: bookmarkTree)

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))

        let rootFolderSyncable = try XCTUnwrap(changedObjects.first { $0.uuid == BookmarkEntity.Constants.rootFolderID })
        XCTAssertEqual(rootFolderSyncable.children, ["1", "4", "3"])
        XCTAssertEqual(rootFolderSyncable.inserted, nil)
        XCTAssertEqual(rootFolderSyncable.removed, ["16", "2"])
    }

    func testThatReorderedChildrenOfExistingFolderAreNotReportedInInsertedOrRemoved() async throws {
        let timestamp = Date()
        let bookmarkTree = BookmarkTree(modifiedAt: timestamp, lastChildrenArrayReceivedFromSync: ["1", "4", "3", "16", "2"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Bookmark(id: "16")
            Bookmark(id: "3")
            Bookmark(id: "4")
        }
        populateBookmarks(with: bookmarkTree)

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))

        let rootFolderSyncable = try XCTUnwrap(changedObjects.first { $0.uuid == BookmarkEntity.Constants.rootFolderID })
        XCTAssertEqual(rootFolderSyncable.children, ["1", "2", "16", "3", "4"])
        XCTAssertEqual(rootFolderSyncable.inserted, nil)
        XCTAssertEqual(rootFolderSyncable.removed, nil)
    }

    func testThatInsertedAndRemovedChildrenOfExistingFolderAreReportedInInsertedAndRemoved() async throws {
        let timestamp = Date()
        let bookmarkTree = BookmarkTree(modifiedAt: timestamp, lastChildrenArrayReceivedFromSync: ["1", "4", "3", "16", "2"]) {
            Bookmark(id: "1")
            Bookmark(id: "2")
            Folder(id: "5", lastChildrenArrayReceivedFromSync: ["7", "6", "10", "8"]) {
                Bookmark(id: "7", isDeleted: true)
                Bookmark(id: "8")
                Bookmark(id: "9")
                Bookmark(id: "6")
                Bookmark(id: "10", isDeleted: true)
            }
            Bookmark(id: "16")
            Bookmark(id: "3")
            Bookmark(id: "4")
        }
        populateBookmarks(with: bookmarkTree)

        let changedObjects = try await provider.fetchChangedObjects(encryptedUsing: crypter)
            .map(SyncableBookmarkAdapter.init(syncable:))

        let rootFolderSyncable = try XCTUnwrap(changedObjects.first { $0.uuid == "5" })
        XCTAssertEqual(rootFolderSyncable.children, ["8", "9", "6"])
        XCTAssertEqual(rootFolderSyncable.inserted, ["9"])
        XCTAssertEqual(rootFolderSyncable.removed, ["7", "10"])
    }

    // MARK: - Private

    private func populateBookmarks(with bookmarkTree: BookmarkTree) {
        let context = bookmarksDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            BookmarkUtils.prepareFoldersStructure(in: context)
            bookmarkTree.createEntities(in: context)
            try! context.save()
        }
    }
}

private extension SyncableBookmarkAdapter {
    var inserted: Set<String>? {
        guard let folder = syncable.payload["folder"] as? [String: Any],
              let folderChildrenDictionary = folder["children"] as? [String: Any],
              let insertedChildren = folderChildrenDictionary["insert"] as? [String]
        else {
            return nil
        }

        return Set(insertedChildren)
    }

    var removed: Set<String>? {
        guard let folder = syncable.payload["folder"] as? [String: Any],
              let folderChildrenDictionary = folder["children"] as? [String: Any],
              let removedChildren = folderChildrenDictionary["remove"] as? [String]
        else {
            return nil
        }

        return Set(removedChildren)
    }
}
