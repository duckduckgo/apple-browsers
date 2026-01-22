//
//  TabHistoryStore.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
    func tabHistory(tabID: String) async throws -> [URL]
    func insertTabHistory(tabID: String, url: URL) async throws
}

public struct TabHistoryStore: TabHistoryStoring {

    let context: NSManagedObjectContext
    let eventMapper: EventMapping<HistoryDatabaseError>

    public init(context: NSManagedObjectContext, eventMapper: EventMapping<HistoryDatabaseError>) {
        self.context = context
        self.eventMapper = eventMapper
    }

    /// Inserts standalone tab history record without Visit relationship.
    /// Used when global history is disabled but tab navigation must work.
    ///
    /// Creates an "orphaned" TabHistory record (visit = nil).
    public func insertTabHistory(tabID: String, url: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform { [context] in
                // Create orphaned record (visit = nil)
                guard let _ = self.createTabHistoryRecord(tabID: tabID,
                                                          url: url,
                                                          linkedVisit: nil,  // ← Orphaned!
                                                          in: context
                ) else {
                    context.reset()
                    continuation.resume(throwing: HistoryDatabaseError.saveFailed)
                    return
                }

                do {
                    try context.save()
                    continuation.resume(returning: ())
                } catch {
                    context.reset()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

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

    public func tabHistory(tabID: String) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            context.perform { [context, eventMapper] in
                let fetchRequest = TabHistoryManagedObject.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "%K == %@",
                                                     #keyPath(TabHistoryManagedObject.tabID),
                                                     tabID)
                fetchRequest.returnsObjectsAsFaults = false
                do {
                    let fetchedObjects = try context.fetch(fetchRequest)
                    let urls = fetchedObjects.map { $0.url }
                    continuation.resume(returning: urls)
                } catch {
                    eventMapper.fire(.loadTabHistoryFailed, error: error)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
