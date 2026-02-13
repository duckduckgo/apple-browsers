//
//  TabHistoryStore.swift
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

@preconcurrency import Common
import Foundation
import CoreData

public protocol TabHistoryStoring {
    func tabHistory(for tabID: String) async throws -> [URL]
    func insertTabHistory(for tabID: String, url: URL) async throws
    func removeTabHistory(for tabIDs: [String]) async throws
    func cleanOrphanedTabHistory(excludingTabIDs openTabIDs: [String]) async throws
}

public struct TabHistoryStore: TabHistoryStoring {

    let context: NSManagedObjectContext
    let eventMapper: EventMapping<HistoryDatabaseError>

    public init(context: NSManagedObjectContext, eventMapper: EventMapping<HistoryDatabaseError>) {
        self.context = context
        self.eventMapper = eventMapper
    }

    /// Inserts standalone tab history record without Visit relationship.
    /// Used when global history is disabled.
    ///
    /// Creates an "orphaned" TabHistory record (visit = nil).
    public func insertTabHistory(for tabID: String, url: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform { [context] in
                // Create orphaned record (visit = nil)
                guard self.createTabHistoryRecord(tabID: tabID,
                                                   url: url,
                                                   linkedVisit: nil,
                                                   in: context) != nil else {
                    context.reset()
                    continuation.resume(throwing: HistoryDatabaseError.saveFailed)
                    return
                }

                do {
                    try context.save()
                    continuation.resume(returning: ())
                } catch {
                    context.reset()
                    eventMapper.fire(.insertTabHistoryFailed, error: error)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Creates a TabHistory managed object in the given context.
    /// Used by HistoryStore to insert a visit and wire up the relationship between *PageVisit* and *TabHistory*
    /// *Does NOT handle saving the context*
    /// - Returns: The created `TabHistoryManagedObject`, or `nil` if creation failed.
    internal func createTabHistoryRecord(tabID: String?,
                                         url: URL?,
                                         linkedVisit: PageVisitManagedObject?,
                                         in context: NSManagedObjectContext) -> TabHistoryManagedObject? {
        guard let tabID, let url else {
            return nil
        }
        guard let tabHistoryMO = NSEntityDescription.insertNewObject(forEntityName: TabHistoryManagedObject.entityName,
                                                                     into: context) as? TabHistoryManagedObject else {
            eventMapper.fire(.insertTabHistoryFailed)
            return nil
        }

        tabHistoryMO.tabID = tabID
        tabHistoryMO.url = url
        tabHistoryMO.visit = linkedVisit

        return tabHistoryMO
    }

    /// Fetches all URLs stored in the tab history for a given tab.
    public func tabHistory(for tabID: String) async throws -> [URL] {
        return try await fetchTabHistory(for: tabID) { tabHistoryMO in
            tabHistoryMO.url
        }
    }

    /// Retrieves all visit IDs associated with a specific tab.
    public func pageVisitIDs(in tabID: String) async throws -> [Visit.ID] {
        return try await fetchTabHistory(for: tabID) { tabHistoryMO in
            tabHistoryMO.visit?.objectID.uriRepresentation()
        }
    }

    typealias TabHistoryTransformingBlock<T> = (TabHistoryManagedObject) -> T?

    /// Fetches tab history records and transforms them using the provided closure.
    /// - Parameters:
    ///   - tabID: The unique identifier of the tab.
    ///   - transform: A closure that extracts the desired value from each `TabHistoryManagedObject`.
    /// - Returns: An array of transformed values
    private func fetchTabHistory<T>(for tabID: String, transform: @escaping TabHistoryTransformingBlock<T>) async throws -> [T] {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform { [context, eventMapper] in
                let fetchRequest = TabHistoryManagedObject.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "%K == %@",
                                                     #keyPath(TabHistoryManagedObject.tabID),
                                                     tabID)
                fetchRequest.returnsObjectsAsFaults = false
                do {
                    let fetchedObjects = try context.fetch(fetchRequest)
                    let results = fetchedObjects.compactMap { transform($0) }
                    continuation.resume(returning: results)
                } catch {
                    eventMapper.fire(.loadTabHistoryFailed, error: error)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Removes all tab history records for the specified tabs.
    /// Uses a batch delete request for efficient removal of multiple records.
    public func removeTabHistory(for tabIDs: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            context.perform { [context, eventMapper] in
                let fetchRequest: NSFetchRequest<NSFetchRequestResult> = TabHistoryManagedObject.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "%K IN %@",
                                                     #keyPath(TabHistoryManagedObject.tabID),
                                                     tabIDs)
                let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                do {
                    try context.execute(batchDeleteRequest)
                    // Batch deletes operate directly on the persistent store, bypassing the context.
                    // Reset updates the context to reflect the store.
                    context.reset()
                    continuation.resume(returning: ())
                } catch {
                    context.reset()
                    eventMapper.fire(.removeTabHistoryFailed, error: error)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Removes all tab history records for tabs that are no longer open.
    /// Uses a batch delete request for efficient removal of orphaned records.
    public func cleanOrphanedTabHistory(excludingTabIDs openTabIDs: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            context.perform { [context, eventMapper] in
                let fetchRequest: NSFetchRequest<NSFetchRequestResult> = TabHistoryManagedObject.fetchRequest()
                if !openTabIDs.isEmpty {
                    fetchRequest.predicate = NSPredicate(format: "NOT (%K IN %@)",
                                                         #keyPath(TabHistoryManagedObject.tabID),
                                                         openTabIDs)
                }
                let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                do {
                    try context.execute(batchDeleteRequest)
                    // Batch deletes operate directly on the persistent store, bypassing the context.
                    // Reset updates the context to reflect the store.
                    context.reset()
                    continuation.resume(returning: ())
                } catch {
                    context.reset()
                    eventMapper.fire(.cleanOrphanedTabHistoryFailed, error: error)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
