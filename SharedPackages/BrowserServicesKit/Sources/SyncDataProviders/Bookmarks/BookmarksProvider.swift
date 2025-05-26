//
//  BookmarksProvider.swift
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

import Foundation
import Bookmarks
import Combine
import Common
import CoreData
import DDGSync
import Persistence
import os.log

public struct FaviconsFetcherInput {
    public var modifiedBookmarksUUIDs: Set<String>
    public var deletedBookmarksUUIDs: Set<String>
}

public final class BookmarksProvider: DataProvider {

    public private(set) var faviconsFetcherInput: FaviconsFetcherInput = .init(modifiedBookmarksUUIDs: [], deletedBookmarksUUIDs: [])

    public init(
        database: CoreDataDatabase,
        metadataStore: SyncMetadataStore,
        metricsEvents: EventMapping<MetricsEvent>? = nil,
        syncDidUpdateData: @escaping () -> Void,
        syncDidFinish: @escaping (FaviconsFetcherInput?) -> Void
    ) {
        self.database = database
        self.metricsEvents = metricsEvents
        super.init(feature: .init(name: "bookmarks"), metadataStore: metadataStore, syncDidUpdateData: syncDidUpdateData)
        self.syncDidFinish = { [weak self] in
            syncDidFinish(self?.faviconsFetcherInput)
        }
    }

    public override func fetchDescriptionsForObjectsThatFailedValidation() -> [String] {
        guard let lastSyncLocalTimestamp else {
            return []
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        var titles: [String] = []

        context.performAndWait {
            titles = BookmarkUtils.fetchTitlesForBookmarks(modifiedBefore: lastSyncLocalTimestamp, in: context)
        }
        return titles
    }

    // MARK: - DataProviding

    public override func prepareForFirstSync() throws {
        var saveError: Error?

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        context.performAndWait {
            let fetchRequest = BookmarkEntity.fetchRequest()
            let bookmarks = (try? context.fetch(fetchRequest)) ?? []
            for bookmark in bookmarks {
                bookmark.modifiedAt = Date()
                bookmark.lastChildrenArrayReceivedFromSync = nil
            }

            do {
                try context.save()
            } catch {
                saveError = error
            }
        }

        if let saveError {
            throw saveError
        }
    }

    public override func fetchChangedObjects(encryptedUsing crypter: Crypting) async throws -> [Syncable] {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)

        var syncableBookmarks: [Syncable] = []
        let encryptionKey = try crypter.fetchSecretKey()
        context.performAndWait {
            let bookmarks = BookmarkUtils.fetchModifiedBookmarks(context)
            syncableBookmarks = bookmarks.compactMap { bookmarkEntity in
                do {
                    return try Syncable(bookmark: bookmarkEntity, encryptedUsing: { try crypter.encryptAndBase64Encode($0, using: encryptionKey)})
                } catch {
                    if case Syncable.SyncableBookmarkError.validationFailed = error {
                        Logger.bookmarks.error("Validation failed for bookmark \(bookmarkEntity.uuid ?? "") with title: \(bookmarkEntity.title.flatMap { String($0.prefix(100)) } ?? "")")
                    }
                    return nil
                }
            }
        }
        return syncableBookmarks
    }

    public override func handleInitialSyncResponse(received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleSyncResponse(isInitial: true, sent: [], received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
    }

    public override func handleSyncResponse(sent: [Syncable], received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        try await handleSyncResponse(isInitial: false, sent: sent, received: received, clientTimestamp: clientTimestamp, serverTimestamp: serverTimestamp, crypter: crypter)
    }

    // MARK: - Internal

    func handleSyncResponse(isInitial: Bool, sent: [Syncable], received: [Syncable], clientTimestamp: Date, serverTimestamp: String?, crypter: Crypting) async throws {
        var saveError: Error?

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        var saveAttemptsLeft = Const.maxContextSaveRetries

        context.performAndWait {
            while true {

                do {
                    let responseHandler = try BookmarksResponseHandler(
                        received: received,
                        clientTimestamp: clientTimestamp,
                        context: context,
                        crypter: crypter,
                        deduplicateEntities: isInitial,
                        metricsEvents: metricsEvents
                    )
                    let idsOfItemsToClearModifiedAt = cleanUpSentItems(sent, receivedUUIDs: Set(responseHandler.receivedByUUID.keys), clientTimestamp: clientTimestamp, in: context)
                    try responseHandler.processReceivedBookmarks()
                    faviconsFetcherInput.modifiedBookmarksUUIDs = responseHandler.idsOfBookmarksWithModifiedURLs
                    faviconsFetcherInput.deletedBookmarksUUIDs = responseHandler.idsOfDeletedBookmarks

#if DEBUG
                    willSaveContextAfterApplyingSyncResponse()
#endif
                    let uuids = idsOfItemsToClearModifiedAt.union(Set(responseHandler.receivedByUUID.keys).subtracting(responseHandler.idsOfItemsThatRetainModifiedAt))
                    try clearModifiedAtAndSaveContext(uuids: uuids, clientTimestamp: clientTimestamp, in: context)
                    break
                } catch {
                    if (error as NSError).code == NSManagedObjectMergeError {
                        context.reset()
                        saveAttemptsLeft -= 1
                        if saveAttemptsLeft == 0 {
                            saveError = error
                            break
                        }
                    } else {
                        saveError = error
                        break
                    }
                }

            }
        }
        if let saveError {
            throw saveError
        }

        if let serverTimestamp {
            updateSyncTimestamps(server: serverTimestamp, local: clientTimestamp)
            syncDidUpdateData()
        } else {
            lastSyncLocalTimestamp = clientTimestamp
        }
        syncDidFinish()
    }

    func cleanUpSentItems(_ sent: [Syncable], receivedUUIDs: Set<String>, clientTimestamp: Date, in context: NSManagedObjectContext) -> Set<String> {
        if sent.isEmpty {
            return []
        }
        let identifiers = sent.compactMap { SyncableBookmarkAdapter(syncable: $0).uuid }
        let bookmarks = BookmarkEntity.fetchBookmarks(with: identifiers, in: context)

        var idsOfItemsToClearModifiedAt = Set<String>()

        for bookmark in bookmarks {
            if let modifiedAt = bookmark.modifiedAt, modifiedAt > clientTimestamp {
                continue
            }
            let hasNewerVersionOnServer: Bool = bookmark.uuid.flatMap { receivedUUIDs.contains($0) } == true
            if bookmark.isPendingDeletion, !hasNewerVersionOnServer {
                context.delete(bookmark)
            } else {
                if !hasNewerVersionOnServer, bookmark.isFolder {
                    if bookmark.uuid.flatMap(BookmarkEntity.isValidFavoritesFolderID) == true {
                        bookmark.updateLastChildrenSyncPayload(with: bookmark.favoritesArray.compactMap(\.uuid))
                    } else {
                        bookmark.updateLastChildrenSyncPayload(with: bookmark.childrenArray.compactMap(\.uuid))
                    }
                }
                bookmark.modifiedAt = nil
                if let uuid = bookmark.uuid {
                    idsOfItemsToClearModifiedAt.insert(uuid)
                }
            }
        }

        return idsOfItemsToClearModifiedAt
    }

    /**
     * Saves context and ensures that `modifiedAt` field is cleared on affected objects.
     *
     * Context needs to be saved twice because setting `modifiedAt` to `nil` is not enough when `modifiedAt` was already `nil`.
     * In that case it would get updated to current date. So we first trigger save to populate `modifiedAt`,
     * and then we explicitly clear them for all affected objects and save again.
     */
    private func saveContextAndClearModifiedAt(_ context: NSManagedObjectContext, excludedUUIDs: Set<String> = []) throws {
        let insertedObjects = Array(context.insertedObjects).compactMap { $0 as? BookmarkEntity }
        let updatedObjects = Array(context.updatedObjects.subtracting(context.deletedObjects)).compactMap { $0 as? BookmarkEntity }

        try context.save()
        (insertedObjects + updatedObjects).forEach { bookmarkEntity in
            if let uuid = bookmarkEntity.uuid, !excludedUUIDs.contains(uuid) {
                bookmarkEntity.modifiedAt = nil
            }
        }
        try context.save()
    }

    private func clearModifiedAtAndSaveContext(uuids: Set<String>, clientTimestamp: Date, in context: NSManagedObjectContext) throws {
        let insertedObjects = Array(context.insertedObjects).compactMap { $0 as? BookmarkEntity }
        let updatedObjects = Array(context.updatedObjects.subtracting(context.deletedObjects)).compactMap { $0 as? BookmarkEntity }
        let modifiedObjects = insertedObjects + updatedObjects

        modifiedObjects.forEach { bookmarkEntity in
            if let uuid = bookmarkEntity.uuid, uuids.contains(uuid) {
                bookmarkEntity.shouldManageModifiedAt = false
                if let modifiedAt = bookmarkEntity.modifiedAt, modifiedAt < clientTimestamp {
                    bookmarkEntity.modifiedAt = nil
                }
            }
        }
        try context.save()
     }

    private let database: CoreDataDatabase
    private let metricsEvents: EventMapping<MetricsEvent>?

    enum Const {
        static let maxContextSaveRetries = 5
    }

    // MARK: - Test support

#if DEBUG
    var willSaveContextAfterApplyingSyncResponse: () -> Void = {}
#endif

}
