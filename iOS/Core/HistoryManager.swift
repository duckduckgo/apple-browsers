//
//  HistoryManager.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import CoreData
import Foundation
import BrowserServicesKit
import History
import Common
import Persistence
import os.log

public protocol HistoryManaging {

    var isEnabledByUser: Bool { get }
    var history: BrowsingHistory? { get }
    @MainActor func removeAllHistory() async
    @MainActor func deleteHistoryForURL(_ url: URL) async
    @MainActor func addVisit(of url: URL, tabID: String?)
    @MainActor func updateTitleIfNeeded(title: String, url: URL)
    @MainActor func commitChanges(url: URL)
    @MainActor func tabHistory(tabID: String) async throws -> [URL]
    @MainActor func removeTabHistory(for tabIDs: [String]) async
}

public class HistoryManager: HistoryManaging {

    let dbCoordinator: HistoryCoordinating
    let tld: TLD
    let tabHistoryCoordinator: TabHistoryCoordinating

    private var historyCoordinator: HistoryCoordinating {
        guard isEnabledByUser else {
            return NullHistoryCoordinator()
        }
        return dbCoordinator
    }

    public let isAutocompleteEnabledByUser: () -> Bool
    public let isRecentlyVisitedSitesEnabledByUser: () -> Bool

    public var isEnabledByUser: Bool {
        return isAutocompleteEnabledByUser() && isRecentlyVisitedSitesEnabledByUser()
    }

    /// Use `make()`
    init(dbCoordinator: HistoryCoordinating,
         tld: TLD,
         tabHistoryCoordinator: TabHistoryCoordinating,
         isAutocompleteEnabledByUser: @autoclosure @escaping () -> Bool,
         isRecentlyVisitedSitesEnabledByUser: @autoclosure @escaping () -> Bool) {

        self.dbCoordinator = dbCoordinator
        self.tld = tld
        self.tabHistoryCoordinator = tabHistoryCoordinator
        self.isAutocompleteEnabledByUser = isAutocompleteEnabledByUser
        self.isRecentlyVisitedSitesEnabledByUser = isRecentlyVisitedSitesEnabledByUser
    }
    
    @MainActor
    public var history: BrowsingHistory? {
        historyCoordinator.history
    }

    @MainActor
    public func removeAllHistory() async {
        await withCheckedContinuation { continuation in
            dbCoordinator.burnAll {
                continuation.resume()
            }
        }
    }

    @MainActor
    public func deleteHistoryForURL(_ url: URL) async {
        guard let domain = url.host else { return }
        let baseDomain = tld.eTLDplus1(domain) ?? domain

        await withCheckedContinuation { continuation in
            historyCoordinator.burnDomains([baseDomain], tld: tld) { _ in
                continuation.resume()
            }
        }
    }
    
    @MainActor
    public func addVisit(of url: URL, tabID: String?) {
        if isEnabledByUser {
            historyCoordinator.addVisit(of: url, tabID: tabID)
        } else {
            tabHistoryCoordinator.addVisit(of: url, tabID: tabID)
        }
    }
    
    @MainActor
    public func updateTitleIfNeeded(title: String, url: URL) {
        historyCoordinator.updateTitleIfNeeded(title: title, url: url)
    }
    
    @MainActor
    public func commitChanges(url: URL) {
        historyCoordinator.commitChanges(url: url)
    }
    
    @MainActor
    public func tabHistory(tabID: String) async throws -> [URL] {
        return try await tabHistoryCoordinator.tabHistory(tabID: tabID)
    }

    @MainActor
    public func removeTabHistory(for tabIDs: [String]) async {
        do {
            try await tabHistoryCoordinator.removeVisits(for: tabIDs)
        } catch {
            Logger.history.error("Failed to remove tab history: \(error.localizedDescription)")
        }
    }

}

class NullHistoryCoordinator: HistoryCoordinating {

    func loadHistory(onCleanFinished: @escaping () -> Void) {
    }

    var history: History.BrowsingHistory?

    var allHistoryVisits: [History.Visit]?

    @Published private(set) public var historyDictionary: [URL: HistoryEntry]?
    var historyDictionaryPublisher: Published<[URL: History.HistoryEntry]?>.Publisher {
        $historyDictionary
    }

    func addVisit(of url: URL, at date: Date, tabID: String?) -> History.Visit? {
        return nil
    }

    func addBlockedTracker(entityName: String, on url: URL) {
    }

    func trackerFound(on: URL) {
    }

    func cookiePopupBlocked(on: URL) {
    }

    func updateTitleIfNeeded(title: String, url: URL) {
    }

    func markFailedToLoadUrl(_ url: URL) {
    }

    func commitChanges(url: URL) {
    }

    func title(for url: URL) -> String? {
        return nil
    }

    func burnAll(completion: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncOrNow {
            completion()
        }
    }

    func burnDomains(_ baseDomains: Set<String>, tld: Common.TLD, completion: @escaping @MainActor (Set<URL>) -> Void) {
        DispatchQueue.main.asyncOrNow {
            completion([])
        }
    }

    func burnVisits(_ visits: [History.Visit], completion: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncOrNow {
            completion()
        }
    }

    func resetCookiePopupBlocked(for domains: Set<String>, tld: Common.TLD, completion: @escaping @MainActor () -> Void) {

    }

    func removeUrlEntry(_ url: URL, completion: (@MainActor ((any Error)?) -> Void)?) {
        DispatchQueue.main.asyncOrNow {
            completion?(nil)
        }
    }

}

public class HistoryDatabase {

    private init() { }

    public static var defaultDBLocation: URL = {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.general.fault("HistoryDatabase.make - OUT, failed to get application support directory")
            fatalError("Failed to get location")
        }
        return url
    }()

    public static var defaultDBFileURL: URL = {
        return defaultDBLocation.appendingPathComponent("History.sqlite", conformingTo: .database)
    }()

    public static func make(location: URL = defaultDBLocation, readOnly: Bool = false) -> CoreDataDatabase {
        Logger.general.debug("HistoryDatabase.make - IN - \(location.absoluteString)")
        let bundle = History.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "BrowsingHistory") else {
            Logger.general.debug("HistoryDatabase.make - OUT, failed to loadModel")
            fatalError("Failed to load model")
        }

        let db = CoreDataDatabase(name: "History",
                                  containerLocation: location,
                                  model: model,
                                  readOnly: readOnly)
        Logger.general.debug("HistoryDatabase.make - OUT")
        return db
    }
}

class HistoryStoreEventMapper: EventMapping<History.HistoryDatabaseError> {
    public init() {
        super.init { event, error, _, _ in
            switch event {
            case .removeFailed:
                Pixel.fire(pixel: .historyRemoveFailed, error: error)

            case .reloadFailed:
                Pixel.fire(pixel: .historyReloadFailed, error: error)

            case .cleanEntriesFailed:
                Pixel.fire(pixel: .historyCleanEntriesFailed, error: error)

            case .cleanVisitsFailed:
                Pixel.fire(pixel: .historyCleanVisitsFailed, error: error)

            case .saveFailed:
                Pixel.fire(pixel: .historySaveFailed, error: error)

            case .insertVisitFailed:
                Pixel.fire(pixel: .historyInsertVisitFailed, error: error)

            case .removeVisitsFailed:
                Pixel.fire(pixel: .historyRemoveVisitsFailed, error: error)

            case .loadTabHistoryFailed:
                Pixel.fire(pixel: .historyLoadTabHistoryFailed, error: error)

            case .insertTabHistoryFailed:
                Pixel.fire(pixel: .historyInsertTabHistoryFailed, error: error)
                
            case .removeTabHistoryFailed:
                Pixel.fire(pixel: .historyRemoveTabHistoryFailed, error: error)
            }

        }
    }

    override init(mapping: @escaping EventMapping<History.HistoryDatabaseError>.Mapping) {
        fatalError("Use init()")
    }
}

extension HistoryManager {

    /// Should only be called once in the app
    public static func make(isAutocompleteEnabledByUser: @autoclosure @escaping () -> Bool,
                            isRecentlyVisitedSitesEnabledByUser: @autoclosure @escaping () -> Bool,
                            tld: TLD) -> Result<HistoryManager, Error> {

        let database = HistoryDatabase.make()
        var loadError: Error?
        database.loadStore { _, error in
            loadError = error
        }

        if let loadError {
            return .failure(loadError)
        }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        let dbCoordinator = HistoryCoordinator(historyStoring: HistoryStore(context: context, eventMapper: HistoryStoreEventMapper()))
        let tabHistoryStore = TabHistoryStore(context: context, eventMapper: HistoryStoreEventMapper())
        let tabHistoryCoordinator = TabHistoryCoordinator(tabHistoryStoring: tabHistoryStore)
        let historyManager = HistoryManager(dbCoordinator: dbCoordinator,
                                            tld: tld,
                                            tabHistoryCoordinator: tabHistoryCoordinator,
                                            isAutocompleteEnabledByUser: isAutocompleteEnabledByUser(),
                                            isRecentlyVisitedSitesEnabledByUser: isRecentlyVisitedSitesEnabledByUser())

        MainActor.assumeMainThread {
            dbCoordinator.loadHistory(onCleanFinished: {
                // Do future migrations after clean has finished.  See macOS for an example.
            })
        }

        return .success(historyManager)
    }

}
