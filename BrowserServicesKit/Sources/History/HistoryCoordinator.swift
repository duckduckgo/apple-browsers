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

public typealias BrowsingHistory = [HistoryEntry]

/**
 * This protocol allows for debugging History.
 */
public protocol HistoryCoordinatingDebuggingSupport {
    /**
     * Adds visit at an arbitrary time, rather than current timestamp.
     *
     * > This function shouldn't be used in production code. Instead, `addVisit(of: URL)` should be used.
     */
    @discardableResult func addVisit(of url: URL, at date: Date) -> Visit?
}

public protocol HistoryCoordinating: AnyObject, HistoryCoordinatingDebuggingSupport {

    func loadHistory(onCleanFinished: @escaping () -> Void)

    var history: BrowsingHistory? { get }
    var allHistoryVisits: [Visit]? { get }
    var historyDictionary: [URL: HistoryEntry]? { get }
    var historyDictionaryPublisher: Published<[URL: HistoryEntry]?>.Publisher { get }

    @discardableResult func addVisit(of url: URL) -> Visit?
    func addBlockedTracker(entityName: String, on url: URL)
    func trackerFound(on: URL)
    func updateTitleIfNeeded(title: String, url: URL)
    func markFailedToLoadUrl(_ url: URL)
    func commitChanges(url: URL)

    func title(for url: URL) -> String?

    func burnAll(completion: @escaping () -> Void)
    func burnDomains(_ baseDomains: Set<String>, tld: TLD, completion: @escaping (Set<URL>) -> Void)
    func burnVisits(_ visits: [Visit], completion: @escaping () -> Void)

    func removeUrlEntry(_ url: URL, completion: ((Error?) -> Void)?)
}

extension HistoryCoordinating {
    @discardableResult
    public func addVisit(of url: URL) -> Visit? {
        addVisit(of: url, at: Date())
    }
}

/// Coordinates access to History. Uses its own queue with high qos for all operations.
final public class HistoryCoordinator: HistoryCoordinating {

    let historyStoringProvider: () -> HistoryStoring

    public init(historyStoring: @autoclosure @escaping () -> HistoryStoring) {
        self.historyStoringProvider = historyStoring
    }

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
    public var history: BrowsingHistory? {
        guard let historyDictionary = historyDictionary else {
            return nil
        }

        return makeHistory(from: historyDictionary)
    }

    public var allHistoryVisits: [Visit]? {
        history?.flatMap { $0.visits }
    }

    private var cancellables = Set<AnyCancellable>()

    @discardableResult public func addVisit(of url: URL, at date: Date) -> Visit? {
        guard let historyDictionary = historyDictionary else {
            Logger.history.debug("Visit of \(url.absoluteString) ignored")
            return nil
        }

        let entry = historyDictionary[url] ?? HistoryEntry(url: url)
        let visit = entry.addVisit(at: date)
        entry.failedToLoad = false

        self.historyDictionary?[url] = entry

        commitChanges(url: url)
        return visit
    }

    public func addBlockedTracker(entityName: String, on url: URL) {
        guard let historyDictionary = historyDictionary else {
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
        guard let historyDictionary = historyDictionary else {
            Logger.history.debug("Add tracker to \(url.absoluteString) ignored, no history")
            return
        }

        guard let entry = historyDictionary[url] else {
            Logger.history.debug("Add tracker to \(url.absoluteString) ignored, no entry")
            return
        }

        entry.trackersFound = true
    }

    public func updateTitleIfNeeded(title: String, url: URL) {
        guard let historyDictionary = historyDictionary else { return }
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
        guard let historyDictionary = historyDictionary,
              let entry = historyDictionary[url] else {
            return
        }

        save(entry: entry)
    }

    public func title(for url: URL) -> String? {
        guard let historyEntry = historyDictionary?[url] else {
            return nil
        }

        return historyEntry.title
    }

    public func burnAll(completion: @escaping () -> Void) {
        clean(until: Date()) {
            self.historyDictionary = [:]
            completion()
        }
    }

    public func burnDomains(_ baseDomains: Set<String>, tld: TLD, completion: @escaping (Set<URL>) -> Void) {
        guard let historyDictionary = historyDictionary else { return }

        var urls = Set<URL>()
        let entries: [HistoryEntry] = historyDictionary.values.filter { historyEntry in
            guard let host = historyEntry.url.host,
                  let baseDomain = tld.eTLDplus1(host),
                  baseDomains.contains(baseDomain) else { return false }
            urls.insert(historyEntry.url)
            return true
        }

        removeEntries(entries, completionHandler: { _ in
            completion(urls)
        })
    }

    public func burnVisits(_ visits: [Visit], completion: @escaping () -> Void) {
        removeVisits(visits) { _ in
            completion()
        }
    }

    public enum EntryRemovalError: Error {
        case notAvailable
    }

    public func removeUrlEntry(_ url: URL, completion: ((Error?) -> Void)? = nil) {
        guard let historyDictionary = historyDictionary else { return }
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

    private func cleanOldAndLoad(onCleanFinished: @escaping () -> Void) {
        clean(until: cleaningDate, onCleanFinished: onCleanFinished)
    }

    private func clean(until date: Date, onCleanFinished: (() -> Void)? = nil) {
        historyStoring.cleanOld(until: date)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    Logger.history.debug("History cleaned successfully")
                case .failure(let error):
                    // This should really be a pixel
                    Logger.history.error("Cleaning of history failed: \(error.localizedDescription)")
                }
                onCleanFinished?()
            }, receiveValue: { [weak self] history in
                self?.historyDictionary = self?.makeHistoryDictionary(from: history)
            })
            .store(in: &cancellables)
    }

    private func removeEntries(_ entries: [HistoryEntry],
                               completionHandler: ((Error?) -> Void)? = nil) {
        // Remove from the local memory
        entries.forEach { entry in
            historyDictionary?.removeValue(forKey: entry.url)
        }

        // Remove from the storage
        historyStoring.removeEntries(entries)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    Logger.history.debug("Entries removed successfully")
                    completionHandler?(nil)
                case .failure(let error):
                    assertionFailure("Removal failed")
                    Logger.history.error("Removal failed: \(error.localizedDescription)")
                    completionHandler?(error)
                }
            }, receiveValue: {})
            .store(in: &cancellables)
    }

    private func removeVisits(_ visits: [Visit],
                              completionHandler: ((Error?) -> Void)? = nil) {
        var entriesToRemove = [HistoryEntry]()

        // Remove from the local memory
        visits.forEach { visit in
            if let historyEntry = visit.historyEntry {
                historyEntry.visits.remove(visit)

                if historyEntry.visits.count > 0 {
                    if let newLastVisit = historyEntry.visits.map({ $0.date }).max() {
                        historyEntry.lastVisit = newLastVisit
                        save(entry: historyEntry)
                    } else {
                        assertionFailure("No history entry")
                    }
                } else {
                    entriesToRemove.append(historyEntry)
                }
            } else {
                assertionFailure("No history entry")
            }
        }

        // Remove from the storage
        historyStoring.removeVisits(visits)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] completion in
                switch completion {
                case .finished:
                    Logger.history.debug("Visits removed successfully")
                    // Remove entries with no remaining visits
                    self?.removeEntries(entriesToRemove, completionHandler: completionHandler)
                case .failure(let error):
                    assertionFailure("Removal failed")
                    Logger.history.error("Removal failed: \(error.localizedDescription)")
                    completionHandler?(error)
                }
            }, receiveValue: {})
            .store(in: &cancellables)
    }

    private func scheduleRegularCleaning() {
        let timer = Timer(fireAt: .startOfDayTomorrow,
                          interval: .day,
                          target: self,
                          selector: #selector(cleanOld),
                          userInfo: nil,
                          repeats: true)
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

        historyStoring.save(entry: entryCopy)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .finished:
                    Logger.history.debug("Visit entry updated successfully. URL: \(entry.url.absoluteString), Title: \(entry.title ?? "-"), Number of visits: \(entry.numberOfTotalVisits), failed to load: \(entry.failedToLoad ? "yes" : "no")")
                case .failure(let error):
                    Logger.history.error("Saving of history entry failed: \(error.localizedDescription)")
                }
            }, receiveValue: { result in
                for (id, date) in result {
                    if let visit = entry.visits.first(where: { $0.date == date }) {
                        visit.identifier = id
                    }
                }
            })
            .store(in: &cancellables)
    }

    /// Sets boolean value for the keyPath in HistroryEntry for the specified url
    /// Does the same for the root URL if it has no visits
    private func mark(url: URL, keyPath: WritableKeyPath<HistoryEntry, Bool>, value: Bool) {
        guard let historyDictionary = historyDictionary, var entry = historyDictionary[url] else {
            Logger.history.debug("Marking of \(url.absoluteString) not saved. History not loaded yet or entry doesn't exist")
            return
        }

        entry[keyPath: keyPath] = value
    }

}
