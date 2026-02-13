//
//  HistoryCoordinator.swift
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

import Foundation
import Combine
import Common
import os.log
import QuartzCore

public typealias BrowsingHistory = [HistoryEntry]

/**
 * This protocol allows for debugging History.
 */
public protocol HistoryCoordinatingDebuggingSupport {
    /**
     * Adds visit at an arbitrary time, rather than current timestamp.
     *
     * > This function shouldn't be used in production code. Instead, `addVisit(of: URL)` or `addVisit(of: URL, tabID:)` should be used.
     */
    @discardableResult @MainActor func addVisit(of url: URL, at date: Date, tabID: String?) -> Visit?
}

public protocol HistoryCoordinating: AnyObject, HistoryCoordinatingDebuggingSupport {

    @MainActor func loadHistory(onCleanFinished: @escaping () -> Void)

    @MainActor var history: BrowsingHistory? { get }
    @MainActor var allHistoryVisits: [Visit]? { get }
    @MainActor var historyDictionary: [URL: HistoryEntry]? { get }
    var historyDictionaryPublisher: Published<[URL: HistoryEntry]?>.Publisher { get }
    var dataClearingPixelsHandling: DataClearingPixelsHandling? { get set }

    @MainActor func addBlockedTracker(entityName: String, on url: URL)
    @MainActor func trackerFound(on: URL)
    @MainActor func cookiePopupBlocked(on: URL)
    @MainActor func updateTitleIfNeeded(title: String, url: URL)
    @MainActor func markFailedToLoadUrl(_ url: URL)
    @MainActor func commitChanges(url: URL)

    @MainActor func title(for url: URL) -> String?

    @MainActor func burnAll(completion: @escaping @MainActor () -> Void)
    @MainActor func burnDomains(_ baseDomains: Set<String>, tld: TLD, completion: @escaping @MainActor (Set<URL>) -> Void)
    @MainActor func burnVisits(_ visits: [Visit], completion: @escaping @MainActor () -> Void)
    @MainActor func burnVisits(for tabID: String) async throws

    @MainActor func resetCookiePopupBlocked(for domains: Set<String>, tld: TLD, completion: @escaping @MainActor () -> Void)

    @MainActor func removeUrlEntry(_ url: URL, completion: (@MainActor (Error?) -> Void)?)
}

extension HistoryCoordinating {

    /**
     * Adds visit at an arbitrary time, rather than current timestamp.
     *
     * > This function shouldn't be used in production code. Instead, `addVisit(of: URL)` or `addVisit(of: URL, tabID:)` should be used.
     */
    @discardableResult
    @MainActor public func addVisit(of url: URL, at date: Date) -> Visit? {
        addVisit(of: url, at: date, tabID: nil)
    }

    @discardableResult
    @MainActor public func addVisit(of url: URL) -> Visit? {
        addVisit(of: url, at: Date(), tabID: nil)
    }

    @discardableResult
    @MainActor public func addVisit(of url: URL, tabID: String?) -> Visit? {
        addVisit(of: url, at: Date(), tabID: tabID)
    }
}

/// Coordinates access to History. Uses its own queue with high qos for all operations.
final public class HistoryCoordinator: HistoryCoordinating {

    public lazy var dataClearingPixelsHandling: DataClearingPixelsHandling? = nil
    let historyStoringProvider: () -> HistoryStoring

    public init(historyStoring: @autoclosure @escaping () -> HistoryStoring) {
        self.historyStoringProvider = historyStoring
    }

    @MainActor
    public func loadHistory(onCleanFinished: @escaping () -> Void) {
        historyDictionary = [:]
        cleanOldAndLoad(onCleanFinished: onCleanFinished)
        scheduleRegularCleaning()
    }

    private lazy var historyStoring: HistoryStoring = {
        return historyStoringProvider()
    }()
    private var regularCleaningTimer: Timer?

    // Source of truth
    @Published private(set) public var historyDictionary: [URL: HistoryEntry]?
    public var historyDictionaryPublisher: Published<[URL: HistoryEntry]?>.Publisher { $historyDictionary }

    // Output
    @MainActor
    public var history: BrowsingHistory? {
        guard let historyDictionary else { return nil }

        return makeHistory(from: historyDictionary)
    }

    @MainActor
    public var allHistoryVisits: [Visit]? {
        history?.flatMap { $0.visits }
    }

    @MainActor
    @discardableResult public func addVisit(of url: URL, at date: Date, tabID: String? = nil) -> Visit? {
        guard let historyDictionary else {
            Logger.history.debug("Visit of \(url.absoluteString) ignored")
            return nil
        }

        let entry = historyDictionary[url] ?? HistoryEntry(url: url)
        let visit = entry.addVisit(at: date, tabID: tabID)
        entry.failedToLoad = false

        self.historyDictionary?[url] = entry

        commitChanges(url: url)
        return visit
    }

    public func addBlockedTracker(entityName: String, on url: URL) {
        guard let historyDictionary else {
            Logger.history.debug("Add tracker to \(url.absoluteString) ignored, no history")
            return
        }

        guard let entry = historyDictionary[url] else {
            Logger.history.debug("Add tracker to \(url.absoluteString) ignored, no entry")
            return
        }

        entry.addBlockedTracker(entityName: entityName)
    }

    public func trackerFound(on url: URL) {
        guard let historyDictionary else {
            Logger.history.debug("Add tracker to \(url.absoluteString) ignored, no history")
            return
        }

        guard let entry = historyDictionary[url] else {
            Logger.history.debug("Add tracker to \(url.absoluteString) ignored, no entry")
            return
        }

        entry.trackersFound = true
    }

    public func cookiePopupBlocked(on url: URL) {
        guard let historyDictionary else {
            Logger.history.debug("Set cookie popup blocked on \(url.absoluteString) ignored, no history")
            return
        }

        guard let entry = historyDictionary[url] else {
            Logger.history.debug("Set cookie popup blocked on \(url.absoluteString) ignored, no entry")
            return
        }

        entry.cookiePopupBlocked = true
        commitChanges(url: url)
    }

    public func updateTitleIfNeeded(title: String, url: URL) {
        guard let historyDictionary else { return }
        guard let entry = historyDictionary[url] else {
            Logger.history.debug("Title update ignored - URL not part of history yet")
            return
        }
        guard !title.isEmpty, entry.title != title else { return }

        entry.title = title
    }

    public func markFailedToLoadUrl(_ url: URL) {
        // historyEntry.failedToLoad = true
        mark(url: url, keyPath: \HistoryEntry.failedToLoad, value: true)
    }

    public func commitChanges(url: URL) {
        guard let historyDictionary, let entry = historyDictionary[url] else { return }
        Logger.history.debug("HistoryCoordinator: committing \(url.absoluteString)")
        save(entry: entry)
    }

    public func title(for url: URL) -> String? {
        guard let historyEntry = historyDictionary?[url] else {
            return nil
        }

        return historyEntry.title
    }

    @MainActor
    public func burnAll(completion: @escaping @MainActor () -> Void) {
        Logger.history.debug("HistoryCoordinator: burnAll")
        self.historyDictionary = [:]
        clean(until: .distantFuture) {
            Logger.history.debug("HistoryCoordinator: burnAll completed")
            completion()
        }
    }

    @MainActor
    public func burnDomains(_ baseDomains: Set<String>, tld: TLD, completion: @escaping @MainActor (Set<URL>) -> Void) {
        guard let historyDictionary else { return }

        var urls = Set<URL>()
        let entries: [HistoryEntry] = historyDictionary.values.filter { historyEntry in
            guard let host = historyEntry.url.host,
                  baseDomains.contains(tld.eTLDplus1(host) ?? host) else { return false }
            urls.insert(historyEntry.url)
            return true
        }

        removeEntries(entries, completionHandler: { _ in
            completion(urls)
        })
    }

    @MainActor
    public func burnVisits(_ visits: [Visit], completion: @escaping @MainActor () -> Void) {
        removeVisits(visits) { _ in
            completion()
        }
    }

    /// Burns all history visits associated with a specific tab.
    ///
    /// This method retrieves visit IDs from the tab history store, maps them to in-memory `Visit` objects,
    /// and removes them from history. Used when burning a single tab to clear its browsing history.
    ///
    /// - Parameter tabID: The unique identifier of the tab whose visits should be removed.
    /// - Throws: `EntryRemovalError.notAvailable` if history has not yet been loaded.
    @MainActor
    public func burnVisits(for tabID: String) async throws {
        guard let allVisits = allHistoryVisits else {
            Logger.history.error("burnVisits(for:) called but history not yet loaded")
            throw EntryRemovalError.notAvailable
        }

        let visitIDs = try await historyStoring.pageVisitIDs(in: tabID)
        let visitsAndIDsArray = allVisits.map { ($0.identifier, $0) }
        let visitByIDsDictionary = Dictionary(visitsAndIDsArray) { existing, _ in
            existing // Keep the first instance found.
        }
        let visits = visitIDs.compactMap { visitByIDsDictionary[$0] }

        assert(visits.count == visitIDs.count,
               "burnVisits(for:) found \(visitIDs.count) visit IDs but matched only \(visits.count) in memory")

        return await withCheckedContinuation { continuation in
            burnVisits(visits) {
                continuation.resume()
            }
        }
    }

    public enum EntryRemovalError: Error {
        case notAvailable
    }

    @MainActor
    public func resetCookiePopupBlocked(for domains: Set<String>, tld: TLD, completion: @escaping @MainActor () -> Void) {
        guard let historyDictionary else {
            completion()
            return
        }

        let entries: [HistoryEntry] = historyDictionary.values.filter { historyEntry in
            guard let host = historyEntry.url.host,
                  domains.contains(tld.eTLDplus1(host) ?? host) else { return false }
            return true
        }

        for entry in entries {
            entry.cookiePopupBlocked = false
            commitChanges(url: entry.url)
        }
        completion()
    }

    @MainActor
    public func removeUrlEntry(_ url: URL, completion: (@MainActor (Error?) -> Void)? = nil) {
        guard let historyDictionary else { return }
        guard let entry = historyDictionary[url] else {
            completion?(EntryRemovalError.notAvailable)
            return
        }

        removeEntries([entry], completionHandler: completion)
    }

    var cleaningDate: Date { .monthAgo }

    @objc private func cleanOld() {
        clean(until: cleaningDate)
    }

    private func cleanOldAndLoad(onCleanFinished: @escaping @MainActor () -> Void) {
        clean(until: cleaningDate, onCleanFinished: onCleanFinished)
    }

    private func clean(until date: Date, onCleanFinished: (@MainActor () -> Void)? = nil) {
        Task {
            do {
                let history = try await historyStoring.cleanOld(until: date)
                Logger.history.debug("History cleaned successfully")
                await MainActor.run { [weak self] in
                    self?.historyDictionary = self?.makeHistoryDictionary(from: history)
                    onCleanFinished?()
                }
            } catch {
                dataClearingPixelsHandling?.fireErrorPixel(error)
                Logger.history.error("Cleaning of history failed: \(error.localizedDescription)")
                await MainActor.run {
                    onCleanFinished?()
                }
            }
        }
    }

    @MainActor
    private func removeEntries(_ entries: some Sequence<HistoryEntry>, completionHandler: (@MainActor (Error?) -> Void)? = nil) {
        // Remove from the local memory
        entries.forEach { entry in
            historyDictionary?.removeValue(forKey: entry.url)
        }

        // Remove from the storage
        Task {
            do {
                try await historyStoring.removeEntries(entries)
                Logger.history.debug("Entries removed successfully")
                await MainActor.run {
                    completionHandler?(nil)
                }
            } catch {
                assertionFailure("Removal failed")
                dataClearingPixelsHandling?.fireErrorPixel(error)
                Logger.history.error("Removal failed: \(error.localizedDescription)")
                await MainActor.run {
                    completionHandler?(error)
                }
            }
        }
    }

    @MainActor
    private func removeVisits(_ visits: [Visit],
                              completionHandler: (@MainActor (Error?) -> Void)? = nil) {
        var entriesToRemove = Set<HistoryEntry>()
        var entriesToSave = Set<HistoryEntry>()

        // Remove from the local memory
        visits.forEach { visit in
            if let historyEntry = visit.historyEntry {
                historyEntry.visits.remove(visit)

                if historyEntry.visits.count > 0 {
                    if let newLastVisit = historyEntry.visits.map({ $0.date }).max() {
                        historyEntry.lastVisit = newLastVisit
                        entriesToSave.insert(historyEntry)
                    } else {
                        assertionFailure("No history entry")
                    }
                } else {
                    entriesToRemove.insert(historyEntry)
                }
            } else {
                assertionFailure("No history entry")
            }
        }

        entriesToSave.forEach { entry in
            save(entry: entry)
        }
        // Remove from the local memory _before_ enqueuing async removal from database
        entriesToRemove.forEach { entry in
            historyDictionary?.removeValue(forKey: entry.url)
        }

        // Remove from the storage
        Task {
            do {
                let startTime = CACurrentMediaTime()
                try await historyStoring.removeVisits(visits)
                Logger.history.debug("Visits removed successfully")
                // Remove entries with no remaining visits
                await MainActor.run {
                    self.removeEntries(entriesToRemove, completionHandler: completionHandler)
                }
                dataClearingPixelsHandling?.fireDurationPixel(startTime)
            } catch {
                assertionFailure("Removal failed")
                dataClearingPixelsHandling?.fireErrorPixel(error)
                Logger.history.error("Removal failed: \(error.localizedDescription)")
                await MainActor.run {
                    completionHandler?(error)
                }
            }
        }
    }

    private func scheduleRegularCleaning() {
        let timer = Timer(fire: .startOfDayTomorrow,
                          interval: .day,
                          repeats: true) { [weak self] _ in
            self?.cleanOld()
        }
        RunLoop.main.add(timer, forMode: RunLoop.Mode.common)
        regularCleaningTimer = timer
    }

    private func makeHistoryDictionary(from history: BrowsingHistory) -> [URL: HistoryEntry] {
        dispatchPrecondition(condition: .onQueue(.main))

        return history.reduce(into: [URL: HistoryEntry](), { $0[$1.url] = $1 })
    }

    private func makeHistory(from dictionary: [URL: HistoryEntry]) -> BrowsingHistory {
        dispatchPrecondition(condition: .onQueue(.main))

        return BrowsingHistory(dictionary.values)
    }

    /// Public for some custom macOS migration
    public func save(entry: HistoryEntry) {
        guard let entryCopy = entry.copy() as? HistoryEntry else {
            assertionFailure("Copying HistoryEntry failed")
            return
        }
        entry.visits.forEach { $0.savingState = .saved }

        Task {
            do {
                let result = try await historyStoring.save(entry: entryCopy)
                Logger.history.debug("Visit entry updated successfully. URL: \(entry.url.absoluteString), Title: \(entry.title ?? "-"), Number of visits: \(entry.numberOfTotalVisits), failed to load: \(entry.failedToLoad ? "yes" : "no"), cookie popup blocked: \(entry.cookiePopupBlocked ? "yes" : "no")")
                await MainActor.run {
                    for (id, date) in result {
                        if let visit = entry.visits.first(where: { $0.date == date }) {
                            visit.identifier = id
                        }
                    }
                }
            } catch {
                Logger.history.error("Saving of history entry failed: \(error.localizedDescription)")
            }
        }
    }

    /// Sets boolean value for the keyPath in HistroryEntry for the specified url
    /// Does the same for the root URL if it has no visits
    @MainActor
    private func mark(url: URL, keyPath: WritableKeyPath<HistoryEntry, Bool>, value: Bool) {
        guard let historyDictionary, var entry = historyDictionary[url] else {
            Logger.history.debug("Marking of \(url.absoluteString) not saved. History not loaded yet or entry doesn't exist")
            return
        }

        entry[keyPath: keyPath] = value
    }

}
