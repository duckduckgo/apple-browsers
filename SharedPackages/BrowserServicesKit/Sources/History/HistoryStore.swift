//
//  HistoryStore.swift
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

import Common
import Foundation
import CoreData
import Combine
import os.log

final public class HistoryStore: HistoryStoring {

    public enum HistoryStoreEvents {

        case removeFailed
        case reloadFailed
        case cleanEntriesFailed
        case cleanVisitsFailed
        case saveFailed
        case insertVisitFailed
        case removeVisitsFailed

    }

    let context: NSManagedObjectContext
    let eventMapper: EventMapping<HistoryStoreEvents>

    public init(context: NSManagedObjectContext, eventMapper: EventMapping<HistoryStoreEvents>) {
        self.context = context
        self.eventMapper = eventMapper
    }

    enum HistoryStoreError: Error {
        case storeDeallocated
        case savingFailed
    }

    public func removeEntries(_ entries: [HistoryEntry]) -> Future<Void, Error> {
        return Future { [weak self] promise in
            self?.context.perform {
                guard let self = self else {
                    promise(.failure(HistoryStoreError.storeDeallocated))
                    return
                }

                let identifiers = entries.map { $0.identifier }
                switch self.remove(identifiers, context: self.context) {
                case .failure(let error):
                    self.context.reset()
                    promise(.failure(error))
                case .success:
                    promise(.success(()))
                }
            }
        }
    }

    public func cleanOld(until date: Date) -> Future<BrowsingHistory, Error> {
        return Future { [weak self] promise in
            self?.context.perform {
                guard let self = self else {
                    promise(.failure(HistoryStoreError.storeDeallocated))
                    return
                }

                switch self.clean(self.context, until: date) {
                case .failure(let error):
                    self.context.reset()
                    promise(.failure(error))
                case .success:
                    let reloadResult = self.reload(self.context)
                    promise(reloadResult)
                }
            }
        }
    }

    private func remove(_ identifiers: [UUID], context: NSManagedObjectContext) -> Result<Void, Error> {
        // To avoid long predicate, execute multiple times
        let chunkedIdentifiers = identifiers.chunked(into: 100)

        for identifiers in chunkedIdentifiers {
            let deleteRequest = BrowsingHistoryEntryManagedObject.fetchRequest()
            let predicates = identifiers.map({ NSPredicate(format: "identifier == %@", argumentArray: [$0]) })
            deleteRequest.predicate = NSCompoundPredicate(type: .or, subpredicates: predicates)

            do {
                let entriesToDelete = try context.fetch(deleteRequest)
                for entry in entriesToDelete {
                    context.delete(entry)
                }
                Logger.history.debug("\(entriesToDelete.count) items cleaned from history")
            } catch {
                eventMapper.fire(.removeFailed, error: error)
                self.context.reset()
                return .failure(error)
            }
        }

        do {
            try context.save()
        } catch {
            eventMapper.fire(.removeFailed, error: error)
            context.reset()
            return .failure(error)
        }

        return .success(())
    }

    private func reload(_ context: NSManagedObjectContext) -> Result<BrowsingHistory, Error> {
        let fetchRequest = BrowsingHistoryEntryManagedObject.fetchRequest()
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let historyEntries = try context.fetch(fetchRequest)
            Logger.history.debug("\(historyEntries.count) entries loaded from history")
            let history = BrowsingHistory(historyEntries: historyEntries)
            return .success(history)
        } catch {
            eventMapper.fire(.reloadFailed, error: error)
            return .failure(error)
        }
    }

    private func clean(_ context: NSManagedObjectContext, until date: Date) -> Result<Void, Error> {
        // Clean using batch delete requests
        let deleteRequest = BrowsingHistoryEntryManagedObject.fetchRequest()
        deleteRequest.predicate = NSPredicate(format: "lastVisit < %@", date as NSDate)
        do {
            let itemsToBeDeleted = try context.fetch(deleteRequest)
            for item in itemsToBeDeleted {
                context.delete(item)
            }
            try context.save()
        } catch {
            eventMapper.fire(.cleanEntriesFailed, error: error)
            context.reset()
            return .failure(error)
        }

        let visitDeleteRequest = PageVisitManagedObject.fetchRequest()
        visitDeleteRequest.predicate = NSPredicate(format: "date < %@", date as NSDate)

        do {
            let itemsToBeDeleted = try context.fetch(visitDeleteRequest)
            for item in itemsToBeDeleted {
                context.delete(item)
            }
            try context.save()
            return .success(())
        } catch {
            eventMapper.fire(.cleanVisitsFailed, error: error)
            context.reset()
            return .failure(error)
        }
    }

    public func save(entry: HistoryEntry) -> Future<[(id: Visit.ID, date: Date)], Error> {
        return Future { [weak self] promise in
            self?.context.perform { [weak self] in
                guard let self = self else {
                    promise(.failure(HistoryStoreError.storeDeallocated))
                    return
                }

                // Check for existence
                let fetchRequest = BrowsingHistoryEntryManagedObject.fetchRequest()
                fetchRequest.returnsObjectsAsFaults = false
                fetchRequest.fetchLimit = 1
                fetchRequest.predicate = NSPredicate(format: "identifier == %@", entry.identifier as CVarArg)
                let fetchedObjects: [BrowsingHistoryEntryManagedObject]
                do {
                    fetchedObjects = try self.context.fetch(fetchRequest)
                } catch {
                    eventMapper.fire(.saveFailed, error: error)
                    promise(.failure(error))
                    return
                }

                assert(fetchedObjects.count <= 1, "More than 1 history entry with the same identifier")

                let historyEntryManagedObject: BrowsingHistoryEntryManagedObject
                if let fetchedObject = fetchedObjects.first {
                    // Update existing
                    fetchedObject.update(with: entry)
                    historyEntryManagedObject = fetchedObject
                } else {
                    // Add new
                    let insertedObject = NSEntityDescription.insertNewObject(forEntityName: BrowsingHistoryEntryManagedObject.entityName, into: self.context)
                    guard let historyEntryMO = insertedObject as? BrowsingHistoryEntryManagedObject else {
                        promise(.failure(HistoryStoreError.savingFailed))
                        return
                    }
                    historyEntryMO.update(with: entry, afterInsertion: true)
                    historyEntryManagedObject = historyEntryMO
                }

                let insertionResult = self.insertNewVisits(of: entry,
                                                           into: historyEntryManagedObject,
                                                           context: self.context)
                switch insertionResult {
                case .failure(let error):
                    eventMapper.fire(.saveFailed, error: error)
                    context.reset()
                    promise(.failure(error))
                case .success(let visitMOs):
                    do {
                        try self.context.save()
                    } catch {
                        eventMapper.fire(.saveFailed, error: error)
                        context.reset()
                        promise(.failure(HistoryStoreError.savingFailed))
                        return
                    }

                    let result = visitMOs.compactMap {
                        if let date = $0.date {
                            return (id: $0.objectID.uriRepresentation(), date: date)
                        } else {
                            return nil
                        }
                    }
                    promise(.success(result))
                }
            }
        }
    }

    private func insertNewVisits(of historyEntry: HistoryEntry,
                                 into historyEntryManagedObject: BrowsingHistoryEntryManagedObject,
                                 context: NSManagedObjectContext) -> Result<[PageVisitManagedObject], Error> {
        var result: [PageVisitManagedObject]? = Array()
        historyEntry.visits
            .filter {
                $0.savingState == .initialized
            }
            .forEach {
                $0.savingState = .saved
                let insertionResult = self.insert(visit: $0,
                                                  into: historyEntryManagedObject,
                                                  context: context)
                switch insertionResult {
                case .success(let visitMO): result?.append(visitMO)
                case .failure: result = nil
                }
            }
        if let result {
            return .success(result)
        } else {
            context.reset()
            return .failure(HistoryStoreError.savingFailed)
        }
    }

    private func insert(visit: Visit,
                        into historyEntryManagedObject: BrowsingHistoryEntryManagedObject,
                        context: NSManagedObjectContext) -> Result<PageVisitManagedObject, Error> {
        let insertedObject = NSEntityDescription.insertNewObject(forEntityName: PageVisitManagedObject.entityName, into: context)
        guard let visitMO = insertedObject as? PageVisitManagedObject else {
            eventMapper.fire(.insertVisitFailed)
            context.reset()
            return .failure(HistoryStoreError.savingFailed)
        }
        visitMO.update(with: visit, historyEntryManagedObject: historyEntryManagedObject)
        return .success(visitMO)
    }

    public func removeVisits(_ visits: [Visit]) -> Future<Void, Error> {
        return Future { [weak self] promise in
            self?.context.perform {
                guard let self = self else {
                    promise(.failure(HistoryStoreError.storeDeallocated))
                    return
                }

                switch self.remove(visits, context: self.context) {
                case .failure(let error):
                    self.context.reset()
                    promise(.failure(error))
                case .success:
                    promise(.success(()))
                }
            }
        }
    }

    private func remove(_ visits: [Visit], context: NSManagedObjectContext) -> Result<Void, Error> {
        // To avoid long predicate, execute multiple times
        let chunkedVisits = visits.chunked(into: 100)

        for visits in chunkedVisits {
            let deleteRequest = PageVisitManagedObject.fetchRequest()
            let predicates = visits.compactMap({ (visit: Visit) -> NSPredicate? in
                guard let historyEntry = visit.historyEntry else {
                    assertionFailure("No history entry")
                    return nil
                }

                return NSPredicate(format: "historyEntry.identifier == %@ && date == %@", argumentArray: [historyEntry.identifier, visit.date])
            })
            deleteRequest.predicate = NSCompoundPredicate(type: .or, subpredicates: predicates)
            do {
                let visitsToDelete = try self.context.fetch(deleteRequest)
                for visit in visitsToDelete {
                    context.delete(visit)
                }
            } catch {
                eventMapper.fire(.removeVisitsFailed, error: error)
                return .failure(error)
            }
        }

        do {
            try context.save()
        } catch {
            eventMapper.fire(.removeVisitsFailed, error: error)
            context.reset()
            return .failure(error)
        }

        return .success(())
    }

}

fileprivate extension BrowsingHistory {

    init(historyEntries: [BrowsingHistoryEntryManagedObject]) {
        self = historyEntries.reduce(into: BrowsingHistory(), {
            if let historyEntry = HistoryEntry(historyEntryMO: $1) {
                $0.append(historyEntry)
            }
        })
    }

}

fileprivate extension HistoryEntry {

    convenience init?(historyEntryMO: BrowsingHistoryEntryManagedObject) {
        guard let url = historyEntryMO.url,
              let identifier = historyEntryMO.identifier,
              let lastVisit = historyEntryMO.lastVisit else {
            assertionFailure("HistoryEntry: Failed to init HistoryEntry from BrowsingHistoryEntryManagedObject")
            return nil
        }

        let title = historyEntryMO.title
        let numberOfTotalVisits = historyEntryMO.numberOfTotalVisits
        let numberOfTrackersBlocked = historyEntryMO.numberOfTrackersBlocked
        let blockedTrackingEntities = historyEntryMO.blockedTrackingEntities ?? ""
        let visits = Set(historyEntryMO.visits?.allObjects.compactMap {
            Visit(visitMO: $0 as? PageVisitManagedObject)
        } ?? [])

        assert(Dictionary(grouping: visits, by: \.date).filter({ $1.count > 1 }).isEmpty, "Duplicate of visit stored")

        self.init(identifier: identifier,
                  url: url,
                  title: title,
                  failedToLoad: historyEntryMO.failedToLoad,
                  numberOfTotalVisits: Int(numberOfTotalVisits),
                  lastVisit: lastVisit,
                  visits: visits,
                  numberOfTrackersBlocked: Int(numberOfTrackersBlocked),
                  blockedTrackingEntities: Set<String>(blockedTrackingEntities.components(separatedBy: "|")),
                  trackersFound: historyEntryMO.trackersFound)

        visits.forEach { visit in
            visit.historyEntry = self
        }
    }

}

fileprivate extension BrowsingHistoryEntryManagedObject {

    func update(with entry: HistoryEntry, afterInsertion: Bool = false) {
        if afterInsertion {
            identifier = entry.identifier
            url = entry.url
        }

        assert(url == entry.url, "URLs don't match")
        assert(identifier == entry.identifier, "Identifiers don't match")

        url = entry.url
        if let title = entry.title, !title.isEmpty {
            self.title = title
        }
        numberOfTotalVisits = Int64(entry.numberOfTotalVisits)
        lastVisit = entry.lastVisit
        failedToLoad = entry.failedToLoad
        numberOfTrackersBlocked = Int64(entry.numberOfTrackersBlocked)
        blockedTrackingEntities = entry.blockedTrackingEntities.isEmpty ? "" : entry.blockedTrackingEntities.joined(separator: "|")
        trackersFound = entry.trackersFound
    }

}

private extension PageVisitManagedObject {

    func update(with visit: Visit, historyEntryManagedObject: BrowsingHistoryEntryManagedObject) {
        date = visit.date
        historyEntry = historyEntryManagedObject
    }

}

private extension Visit {

    convenience init?(visitMO: PageVisitManagedObject?) {
        guard let visitMO = visitMO,
                let date = visitMO.date else {
            assertionFailure("Bad type or date is nil")
            return nil
        }

        let id = visitMO.objectID.uriRepresentation()
        self.init(date: date, identifier: id)
        savingState = .saved
    }

}

private extension NSManagedObject {

    static var entityName: String {
        String(describing: self)
    }

}
