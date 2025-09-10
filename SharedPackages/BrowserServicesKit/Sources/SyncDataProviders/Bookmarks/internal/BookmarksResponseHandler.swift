//
//  BookmarksResponseHandler.swift
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

import Bookmarks
import Common
import CoreData
import DDGSync
import Foundation

final class BookmarksResponseHandler {
    let feature: Feature = .init(name: "bookmarks")

    let clientTimestamp: Date?
    let received: [SyncableBookmarkAdapter]
    let context: NSManagedObjectContext
    let shouldDeduplicateEntities: Bool

    let receivedByUUID: [String: SyncableBookmarkAdapter]
    let allReceivedIDs: Set<String>

    let topLevelFoldersSyncables: [SyncableBookmarkAdapter]
    let bookmarkSyncablesWithoutParent: [SyncableBookmarkAdapter]
    let favoritesUUIDsByFolderUUID: [String: [String]]

    var entitiesByUUID: [String: BookmarkEntity] = [:]
    var idsOfItemsThatRetainModifiedAt = Set<String>()
    var deduplicatedFolderUUIDs = Set<String>()

    var idsOfBookmarksWithModifiedURLs = Set<String>()
    var idsOfDeletedBookmarks = Set<String>()

    private let decrypt: (String) throws -> String
    private let metricsEvents: EventMapping<MetricsEvent>?

    init(
        received: [Syncable],
        clientTimestamp: Date? = nil,
        context: NSManagedObjectContext,
        crypter: Crypting,
        deduplicateEntities: Bool,
        metricsEvents: EventMapping<MetricsEvent>? = nil
    ) throws {
        self.clientTimestamp = clientTimestamp
        self.received = received.map { SyncableBookmarkAdapter(syncable: $0) }
        self.context = context
        self.shouldDeduplicateEntities = deduplicateEntities
        self.metricsEvents = metricsEvents

        let secretKey = try crypter.fetchSecretKey()
        self.decrypt = { try crypter.base64DecodeAndDecrypt($0, using: secretKey) }

        var syncablesByUUID: [String: SyncableBookmarkAdapter] = [:]
        var allUUIDs: Set<String> = []
        var childrenToParents: [String: String] = [:]
        var parentFoldersToChildren: [String: [String]] = [:]
        var favoritesUUIDsByFolderUUID: [String: [String]] = [:]

        self.received.forEach { syncable in
            guard let uuid = syncable.uuid else {
                return
            }
            syncablesByUUID[uuid] = syncable

            allUUIDs.insert(uuid)
            if syncable.isFolder {
                allUUIDs.formUnion(syncable.children)
            }

            if BookmarkEntity.isValidFavoritesFolderID(uuid) {
                favoritesUUIDsByFolderUUID[uuid] = syncable.children
            } else {
                if syncable.isFolder {
                    parentFoldersToChildren[uuid] = syncable.children
                }
                syncable.children.forEach { child in
                    childrenToParents[child] = uuid
                }
            }
        }

        self.allReceivedIDs = allUUIDs
        self.receivedByUUID = syncablesByUUID
        self.favoritesUUIDsByFolderUUID = favoritesUUIDsByFolderUUID

        let foldersWithoutParent = Set(parentFoldersToChildren.keys).subtracting(childrenToParents.keys)
        topLevelFoldersSyncables = foldersWithoutParent.compactMap { syncablesByUUID[$0] }

        bookmarkSyncablesWithoutParent = allUUIDs.subtracting(childrenToParents.keys)
            .subtracting(foldersWithoutParent.union(BookmarkEntity.Constants.favoriteFoldersIDs))
            .compactMap { syncablesByUUID[$0] }

        BookmarkEntity.fetchBookmarks(with: allReceivedIDs, in: context)
            .forEach { bookmark in
                guard let uuid = bookmark.uuid else {
                    return
                }
                entitiesByUUID[uuid] = bookmark
            }
    }

    func processReceivedBookmarks() throws {
        if received.isEmpty {
            return
        }

        for topLevelFolderSyncable in topLevelFoldersSyncables {
            do {
                try processTopLevelFolder(topLevelFolderSyncable)
            } catch SyncError.failedToDecryptValue(let message) where message.contains("invalid ciphertext length") {
                continue
            }
        }
        try processOrphanedBookmarks()
        processReceivedFavorites()
        cleanupOrphanedStubs()
    }

    // MARK: - Private

    private func processReceivedFavorites() {
        for (favoritesFolderUUID, favoritesUUIDs) in favoritesUUIDsByFolderUUID {
            guard let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(withUUID: favoritesFolderUUID, in: context) else {
                // Error - unable to process favorites
                return
            }

            // For non-first sync we rely fully on the server response
            if !shouldDeduplicateEntities {
                let favorites = favoritesFolder.favorites?.array as? [BookmarkEntity] ?? []
                favorites.forEach { $0.removeFromFavorites(favoritesRoot: favoritesFolder) }
            } else if !favoritesFolder.favoritesArray.isEmpty {
                // If we're deduplicating and there are favorites locally, we'll need to sync favorites folder back later.
                // Let's keep its modifiedAt.
                idsOfItemsThatRetainModifiedAt.insert(favoritesFolderUUID)
            }

            favoritesUUIDs.forEach { uuid in
                if let bookmark = entitiesByUUID[uuid] {
                    bookmark.removeFromFavorites(favoritesRoot: favoritesFolder)
                    bookmark.addToFavorites(favoritesRoot: favoritesFolder)
                } else {
                    let newStubEntity = BookmarkEntity.make(withUUID: uuid,
                                                            isFolder: false,
                                                            in: context)
                    newStubEntity.isStub = true
                    newStubEntity.addToFavorites(favoritesRoot: favoritesFolder)
                    entitiesByUUID[uuid] = newStubEntity
                }
            }

            favoritesFolder.updateLastChildrenSyncPayload(with: favoritesUUIDs)
        }
    }

    private func cleanupOrphanedStubs() {
        let stubs = BookmarkUtils.fetchStubbedEntities(context)

        for stub in stubs where stub.parent == nil && (stub.favoriteFolders?.count ?? 0) == 0 {
            context.delete(stub)
        }
    }

    private func processTopLevelFolder(_ topLevelFolderSyncable: SyncableBookmarkAdapter) throws {
        guard let topLevelFolderUUID = topLevelFolderSyncable.uuid else {
            return
        }
        var queues: [[String]] = [topLevelFolderSyncable.children]
        var parentUUIDs: [String] = [topLevelFolderUUID]

        try processEntity(with: topLevelFolderSyncable)

        while !queues.isEmpty {
            var queue = queues.removeFirst()
            let parentUUID = parentUUIDs.removeFirst()
            let parent = BookmarkEntity.fetchFolder(withUUID: parentUUID, in: context)

            // For non-first sync we rely fully on the server response
            if !shouldDeduplicateEntities {
                (parent?.children?.array as? [BookmarkEntity] ?? []).forEach { parent?.removeFromChildren($0) }
            }

            while !queue.isEmpty {
                let syncableUUID = queue.removeFirst()

                if let syncable = receivedByUUID[syncableUUID] {
                    try processEntity(with: syncable, parent: parent)
                    if syncable.isFolder, !syncable.children.isEmpty {
                        queues.append(syncable.children)
                        parentUUIDs.append(syncableUUID)
                    }
                    // If this entity belongs to a deduplicated non-empty folder, we'll need to sync that folder back later.
                    // Let's keep its modifiedAt.
                    if deduplicatedFolderUUIDs.contains(parentUUID) {
                        idsOfItemsThatRetainModifiedAt.insert(parentUUID)
                    }
                } else if let existingEntity = entitiesByUUID[syncableUUID] {
                    existingEntity.parent?.removeFromChildren(existingEntity)
                    parent?.addToChildren(existingEntity)
                } else {
                    let newStubEntity = BookmarkEntity.make(withUUID: syncableUUID,
                                                            isFolder: false,
                                                            in: context)
                    newStubEntity.isStub = true
                    parent?.addToChildren(newStubEntity)
                    entitiesByUUID[syncableUUID] = newStubEntity
                }
            }
        }
    }

    private func processOrphanedBookmarks() throws {

        for syncable in bookmarkSyncablesWithoutParent {
            guard !syncable.isFolder else {
                assertionFailure("Bookmark folder passed to \(#function)")
                continue
            }
            do {
                try processEntity(with: syncable)
            } catch SyncError.failedToDecryptValue(let message) where message.contains("invalid ciphertext length") {
                continue
            }
        }
    }

    private func processEntity(with syncable: SyncableBookmarkAdapter, parent: BookmarkEntity? = nil) throws {
        guard let syncableUUID = syncable.uuid else {
            return
        }

        if shouldDeduplicateEntities, let deduplicatedEntity = try BookmarkEntity.deduplicatedEntity(
            with: syncable,
            parentUUID: parent?.uuid,
            in: context,
            decryptedUsing: decrypt
        ) {

            if let oldUUID = deduplicatedEntity.uuid {
                entitiesByUUID.removeValue(forKey: oldUUID)
            }
            entitiesByUUID[syncableUUID] = deduplicatedEntity
            deduplicatedEntity.uuid = syncableUUID
            if deduplicatedEntity.isFolder, !deduplicatedEntity.childrenArray.isEmpty {
                deduplicatedFolderUUIDs.insert(syncableUUID)
            }
            if parent != nil {
                deduplicatedEntity.parent?.removeFromChildren(deduplicatedEntity)
                parent?.addToChildren(deduplicatedEntity)
            }

            deduplicatedEntity.updateLastChildrenSyncPayload(with: syncable.children)

        } else if let existingEntity = entitiesByUUID[syncableUUID] {
            let isModifiedAfterSyncTimestamp: Bool = {
                guard let clientTimestamp, let modifiedAt = existingEntity.modifiedAt else {
                    return false
                }
                return modifiedAt > clientTimestamp
            }()
            if isModifiedAfterSyncTimestamp {
                metricsEvents?.fire(.localTimestampResolutionTriggered(feature: feature))
            } else {
                try updateEntity(existingEntity, with: syncable)
            }

            if parent != nil, !existingEntity.isDeleted {
                existingEntity.parent?.removeFromChildren(existingEntity)
                parent?.addToChildren(existingEntity)
            }

            existingEntity.updateLastChildrenSyncPayload(with: syncable.children)

        } else if !syncable.isDeleted {

            assert(syncable.uuid != BookmarkEntity.Constants.rootFolderID, "Trying to make another root folder")

            let newEntity = BookmarkEntity.make(withUUID: syncableUUID, isFolder: syncable.isFolder, in: context)
            parent?.addToChildren(newEntity)
            try updateEntity(newEntity, with: syncable)
            entitiesByUUID[syncableUUID] = newEntity

            newEntity.updateLastChildrenSyncPayload(with: syncable.children)
        }
    }

    private func updateEntity(_ entity: BookmarkEntity, with syncable: SyncableBookmarkAdapter) throws {
        let url = entity.url
        try entity.update(with: syncable, in: context, decryptedUsing: decrypt, metricsEvents: metricsEvents)
        if let uuid = entity.uuid {
            if entity.isDeleted {
                idsOfDeletedBookmarks.insert(uuid)
            } else if entity.url != url {
                idsOfBookmarksWithModifiedURLs.insert(uuid)
            }
        }
    }
}
