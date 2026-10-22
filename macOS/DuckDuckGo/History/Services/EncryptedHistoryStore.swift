//
//  EncryptedHistoryStore.swift
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
import FoundationExtensions
import Foundation
import CoreData
import Combine
import History
import PixelKit
import os.log

actor EncryptedHistoryStore: HistoryStoring {

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    enum HistoryStoreError: Error {
        case savingFailed
    }

    let context: NSManagedObjectContext

    func removeEntries(_ entries: some Sequence<HistoryEntry>) async throws {
        try await withCheckedThrowingContinuation { continuation in
            context.perform {
                let identifiers = entries.map { $0.identifier }
                switch self.remove(identifiers, context: self.context) {
                case .failure(let error):
                    self.context.reset()
                    continuation.resume(throwing: error)
                case .success:
                    continuation.resume(returning: ())
                }
            }
        } as Void
    }

    func cleanOld(until date: Date) async throws -> BrowsingHistory {
        try await withCheckedThrowingContinuation { continuation in
            context.perform {
                switch self.clean(self.context, until: date) {
                case .failure(let error):
                    self.context.reset()
                    continuation.resume(throwing: error)
                case .success:
                    let reloadResult = self.reload(self.context)
                    continuation.resume(with: reloadResult)
                }
            }
        }
    }

    nonisolated private func remove(_ identifiers: [UUID], context: NSManagedObjectContext) -> Result<Void, Error> {
        // To avoid long predicate, execute multiple times
        let chunkedIdentifiers = identifiers.chunked(into: 100)

        for identifiers in chunkedIdentifiers {
            let deleteRequest = NSFetchRequest<HistoryEntryManagedObject>(entityName: HistoryEntryManagedObject.className())
            let predicates = identifiers.map({ NSPredicate(format: "identifier == %@", argumentArray: [$0]) })
            deleteRequest.predicate = NSCompoundPredicate(type: .or, subpredicates: predicates)

            do {
                let entriesToDelete = try context.fetch(deleteRequest)
                for entry in entriesToDelete {
                    context.delete(entry)
                }
                Logger.history.debug("\(entriesToDelete.count) items cleaned from history")
            } catch {
                PixelKit.fire(DebugEvent(GeneralPixel.historyRemoveFailed, error: error))
                self.context.reset()
                return .failure(error)
            }
        }

        do {
            try context.save()
        } catch {
            PixelKit.fire(DebugEvent(GeneralPixel.historyRemoveFailed, error: error))
            context.reset()
            return .failure(error)
        }

        return .success(())
    }

    nonisolated private func reload(_ context: NSManagedObjectContext) -> Result<BrowsingHistory, Error> {
        let fetchRequest = HistoryEntryManagedObject.fetchRequest() as NSFetchRequest<HistoryEntryManagedObject>
        fetchRequest.returnsObjectsAsFaults = false
        do {
            let historyEntries = try context.fetch(fetchRequest)
            Logger.history.debug("\(historyEntries.count) entries loaded from history")
            let history = BrowsingHistory(historyEntries: historyEntries)
            return .success(history)
        } catch {
            PixelKit.fire(DebugEvent(GeneralPixel.historyReloadFailed, error: error))
            return .failure(error)
        }
    }

    nonisolated private func clean(_ context: NSManagedObjectContext, until date: Date) -> Result<Void, Error> {
        switch cleanEntries(context, until: date) {
        case .success:
            return cleanVisits(context, until: date)
        case .failure(let error):
            return .failure(error)
        }
    }

    nonisolated private func cleanEntries(_ context: NSManagedObjectContext, until date: Date, maxRetries: Int = 4) -> Result<Void, Error> {
        let deleteRequest = NSFetchRequest<NSManagedObject>(entityName: HistoryEntryManagedObject.className())
        deleteRequest.predicate = NSPredicate(format: "lastVisit < %@", date as NSDate)

        var iteration = 0
        var lastError: Error?

        while iteration < maxRetries {
            do {
                let itemsToBeDeleted = try context.fetch(deleteRequest)
                for item in itemsToBeDeleted {
                    context.delete(item)
                }
                try context.save()
                return .success(())
            } catch {
                lastError = error
                let nsError = error as NSError
                if nsError.code == NSManagedObjectMergeError || nsError.code == NSManagedObjectConstraintMergeError {
                    iteration += 1
                    context.reset()
                } else {
                    break
                }
            }
        }

        if let lastError {
            PixelKit.fire(DebugEvent(GeneralPixel.historyCleanEntriesFailed, error: lastError))
            return .failure(lastError)
        }
        return .success(())
    }

    nonisolated private func cleanVisits(_ context: NSManagedObjectContext, until date: Date, maxRetries: Int = 4) -> Result<Void, Error> {
        let visitDeleteRequest = NSFetchRequest<VisitManagedObject>(entityName: VisitManagedObject.className())
        visitDeleteRequest.predicate = NSPredicate(format: "date < %@", date as NSDate)

        var iteration = 0
        var lastError: Error?

        while iteration < maxRetries {
            do {
                let itemsToBeDeleted = try context.fetch(visitDeleteRequest)
                for item in itemsToBeDeleted {
                    context.delete(item)
                }
                try context.save()
                return .success(())
            } catch {
                let nsError = error as NSError
                lastError = error
                if nsError.code == NSManagedObjectMergeError || nsError.code == NSManagedObjectConstraintMergeError {
                    iteration += 1
                    context.reset()
                } else {
                    break
                }
            }
        }

        if let lastError {
            PixelKit.fire(DebugEvent(GeneralPixel.historyCleanVisitsFailed, error: lastError))
            return .failure(lastError)
        }
        return .success(())
    }

    func save(entry: HistoryEntry) async throws -> [(id: Visit.ID, date: Date)] {
        try await save(entries: [entry])[entry.identifier] ?? []
    }

    func save(entries: [HistoryEntry]) async throws -> [UUID: [(id: Visit.ID, date: Date)]] {
        try await withCheckedThrowingContinuation { continuation in
            context.perform {
                let visitMOsByEntry: [UUID: [VisitManagedObject]]
                do {
                    let storedEntries = try self.fetchEntries(identifiedBy: entries.map(\.identifier), in: self.context)
                    visitMOsByEntry = try Dictionary(entries.map {
                        ($0.identifier, try self.insertOrUpdate($0, storedEntry: storedEntries[$0.identifier], in: self.context))
                    }, uniquingKeysWith: { first, second in first + second })
                } catch {
                    Self.fireSaveFailedPixels(error: error)
                    self.context.reset()
                    continuation.resume(throwing: error)
                    return
                }

                do {
                    try self.context.save()
                    Logger.history.debug("HistoryStore: saved \(entries.count) entries")
                } catch {
                    Self.fireSaveFailedPixels(error: error)
                    self.context.reset()
                    continuation.resume(throwing: HistoryStoreError.savingFailed)
                    return
                }

                continuation.resume(returning: visitMOsByEntry.mapValues { visitMOs in
                    visitMOs.compactMap { visitMO in
                        visitMO.date.map { (id: visitMO.objectID.uriRepresentation(), date: $0) }
                    }
                })
            }
        }
    }

    /// Fetches the stored entries up front: fetching them one by one while inserting would also scan every pending insert.
    nonisolated private func fetchEntries(identifiedBy identifiers: [UUID], in context: NSManagedObjectContext) throws -> [UUID: HistoryEntryManagedObject] {
        var storedEntries = [UUID: HistoryEntryManagedObject]()
        for chunk in identifiers.chunked(into: 500) {
            let fetchRequest = HistoryEntryManagedObject.fetchRequest() as NSFetchRequest<HistoryEntryManagedObject>
            fetchRequest.returnsObjectsAsFaults = false
            fetchRequest.predicate = NSPredicate(format: "identifier IN %@", chunk)
            for storedEntry in try context.fetch(fetchRequest) {
                if let identifier = storedEntry.identifier {
                    storedEntries[identifier] = storedEntry
                }
            }
        }
        return storedEntries
    }

    /// Stages the entry and its unsaved visits in the context without saving it.
    nonisolated private func insertOrUpdate(
        _ entry: HistoryEntry,
        storedEntry: HistoryEntryManagedObject?,
        in context: NSManagedObjectContext
    ) throws -> [VisitManagedObject] {
        let historyEntryManagedObject: HistoryEntryManagedObject
        if let storedEntry {
            storedEntry.update(with: entry)
            historyEntryManagedObject = storedEntry
        } else {
            let insertedObject = NSEntityDescription.insertNewObject(forEntityName: HistoryEntryManagedObject.className(), into: context)
            guard let historyEntryMO = insertedObject as? HistoryEntryManagedObject else {
                throw HistoryStoreError.savingFailed
            }
            historyEntryMO.update(with: entry, afterInsertion: true)
            historyEntryManagedObject = historyEntryMO
        }

        return try insertNewVisits(of: entry, into: historyEntryManagedObject, context: context).get()
    }

    private static func fireSaveFailedPixels(error: Error) {
        PixelKit.fire(DebugEvent(GeneralPixel.historySaveFailed, error: error))
        PixelKit.fire(DebugEvent(GeneralPixel.historySaveFailedDaily, error: error), frequency: .legacyDailyNoSuffix)
    }

    nonisolated private func insertNewVisits(of historyEntry: HistoryEntry,
                                             into historyEntryManagedObject: HistoryEntryManagedObject,
                                             context: NSManagedObjectContext) -> Result<[VisitManagedObject], Error> {
        var result: [VisitManagedObject]? = Array()
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

    nonisolated private func insert(visit: Visit,
                                    into historyEntryManagedObject: HistoryEntryManagedObject,
                                    context: NSManagedObjectContext) -> Result<VisitManagedObject, Error> {
        let insertedObject = NSEntityDescription.insertNewObject(forEntityName: VisitManagedObject.className(), into: context)
        guard let visitMO = insertedObject as? VisitManagedObject else {
            PixelKit.fire(DebugEvent(GeneralPixel.historyInsertVisitFailed))
            context.reset()
            return .failure(HistoryStoreError.savingFailed)
        }
        visitMO.update(with: visit, historyEntryManagedObject: historyEntryManagedObject)
        return .success(visitMO)
    }

    func removeVisits(_ visits: some Sequence<Visit>) async throws {
        try await withCheckedThrowingContinuation { continuation in
            context.perform {
                switch self.remove(visits, context: self.context) {
                case .failure(let error):
                    self.context.reset()
                    continuation.resume(throwing: error)
                case .success:
                    continuation.resume(returning: ())
                }
            }
        } as Void
    }

    func pageVisitIDs(in tabID: String) async throws -> [Visit.ID] {
        // macOS does not currently record tab history in core data - return empty array
        return []
    }

    nonisolated private func remove(_ visits: some Sequence<Visit>, context: NSManagedObjectContext) -> Result<Void, Error> {
        // To avoid long predicate, execute multiple times
        let chunkedVisits = visits.chunkedSequence(into: 100)

        for visits in chunkedVisits {
            let deleteRequest = NSFetchRequest<VisitManagedObject>(entityName: VisitManagedObject.className())
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
                PixelKit.fire(DebugEvent(GeneralPixel.historyRemoveVisitsFailed, error: error))
                return .failure(error)
            }
        }

        do {
            try context.save()
        } catch {
            PixelKit.fire(DebugEvent(GeneralPixel.historyRemoveVisitsFailed, error: error))
            context.reset()
            return .failure(error)
        }

        return .success(())
    }

}

fileprivate extension BrowsingHistory {

    init(historyEntries: [HistoryEntryManagedObject]) {
        self = historyEntries.reduce(into: BrowsingHistory(), {
            if let historyEntry = HistoryEntry(historyEntryMO: $1) {
                $0.append(historyEntry)
            }
        })
    }

}

fileprivate extension HistoryEntry {

    convenience init?(historyEntryMO: HistoryEntryManagedObject) {
        guard let url = historyEntryMO.urlEncrypted as? URL,
              let identifier = historyEntryMO.identifier,
              let lastVisit = historyEntryMO.lastVisit else {
            PixelKit.fire(DebugEvent(GeneralPixel.historyEntryDecryptionFailedUnique), frequency: .legacyDaily)
            assertionFailure("HistoryEntry: Failed to init HistoryEntry from HistoryEntryManagedObject")
            return nil
        }

        let title = historyEntryMO.titleEncrypted as? String
        let numberOfTotalVisits = historyEntryMO.numberOfTotalVisits
        let numberOfTrackersBlocked = historyEntryMO.numberOfTrackersBlocked
        let blockedTrackingEntities = historyEntryMO.blockedTrackingEntities ?? ""
        let visits = Set(historyEntryMO.visits?.allObjects.compactMap {
            Visit(visitMO: $0 as? VisitManagedObject)
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
                  trackersFound: historyEntryMO.trackersFound,
                  cookiePopupBlocked: historyEntryMO.cookiePopupBlocked)

        visits.forEach { visit in
            visit.historyEntry = self
        }
    }

}

fileprivate extension HistoryEntryManagedObject {

    func update(with entry: HistoryEntry, afterInsertion: Bool = false) {
        if afterInsertion {
            identifier = entry.identifier
            urlEncrypted = entry.url as NSURL
        }

        assert(urlEncrypted as? URL == entry.url, "URLs don't match")
        assert(identifier == entry.identifier, "Identifiers don't match")

        urlEncrypted = entry.url as NSURL
        if let title = entry.title, !title.isEmpty {
            self.titleEncrypted = title as NSString
        }
        numberOfTotalVisits = Int64(entry.numberOfTotalVisits)
        lastVisit = entry.lastVisit
        failedToLoad = entry.failedToLoad
        numberOfTrackersBlocked = Int64(entry.numberOfTrackersBlocked)
        blockedTrackingEntities = entry.blockedTrackingEntities.isEmpty ? "" : entry.blockedTrackingEntities.joined(separator: "|")
        trackersFound = entry.trackersFound
        cookiePopupBlocked = entry.cookiePopupBlocked
    }

}

private extension VisitManagedObject {

    func update(with visit: Visit, historyEntryManagedObject: HistoryEntryManagedObject) {
        date = visit.date
        historyEntry = historyEntryManagedObject
    }

}

private extension Visit {

    convenience init?(visitMO: VisitManagedObject?) {
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
