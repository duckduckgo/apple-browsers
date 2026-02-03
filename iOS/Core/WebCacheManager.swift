//
//  WebCacheManager.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import WebKit
import os.log

import WKAbstractions

/// This is effectively a wrapper around a system singleton which returns abstracted wrapper.
///
///  We should turn this into a protocol and inject it where needed.
public enum DDGWebsiteDataStoreProvider {

    // Don't call this in tests.
    @MainActor
    public static func current(dataStoreIDManager: DataStoreIDManaging = DataStoreIDManager.shared) -> any DDGWebsiteDataStore {
        guard !ProcessInfo().arguments.contains("testing") else {
            fatalError("Don't call this from tests")
        }

        if #available(iOS 17, *), let id = dataStoreIDManager.currentID {
            return WebsiteDataStoreWrapper(wrapped: WKWebsiteDataStore(forIdentifier: id))
        } else {
            return WebsiteDataStoreWrapper(wrapped: WKWebsiteDataStore.default())
        }
    }

}

@MainActor
public protocol WebsiteDataManaging {

    func removeCookies(forDomains domains: [String], fromDataStore: any DDGWebsiteDataStore) async
    func consumeCookies(into httpCookieStore: DDGHTTPCookieStore) async
    func clear(dataStore: any DDGWebsiteDataStore) async
    func clear(dataStore: any DDGWebsiteDataStore, forDomains domains: [String]) async

}

public class WebCacheManager: WebsiteDataManaging {
    
    private typealias DataRecordInScopeEvaluator = (String) -> Bool
    private typealias CookieInScopeEvaluator = (HTTPCookie) -> Bool
    
    private enum Scope {
        case all
        case limited(dataRecords: DataRecordInScopeEvaluator, cookies: CookieInScopeEvaluator)
        
        var dataRecordsEvaluator: DataRecordInScopeEvaluator {
            switch self {
            case .all:
                return { _ in true }
            case .limited(let dataRecords, _):
                return dataRecords
            }
        }
        
        var cookiesEvaluator: CookieInScopeEvaluator {
            switch self {
            case .all:
                return { _ in true }
            case .limited(_, let cookies):
                return cookies
            }
        }
    }

    static let safelyRemovableWebsiteDataTypes: Set<String> = {
        var types = WKWebsiteDataStore.allWebsiteDataTypes()

        types.insert("_WKWebsiteDataTypeMediaKeys")
        types.insert("_WKWebsiteDataTypeHSTSCache")
        types.insert("_WKWebsiteDataTypeSearchFieldRecentSearches")
        types.insert("_WKWebsiteDataTypeResourceLoadStatistics")
        types.insert("_WKWebsiteDataTypeCredentials")
        types.insert("_WKWebsiteDataTypeAdClickAttributions")
        types.insert("_WKWebsiteDataTypePrivateClickMeasurements")
        types.insert("_WKWebsiteDataTypeAlternativeServices")

        fireproofableDataTypes.forEach {
            types.remove($0)
        }

        return types
    }()

    static let fireproofableDataTypes: Set<String> = {
        Set<String>([
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeCookies,
        ])
    }()

    static let fireproofableDataTypesExceptCookies: Set<String> = {
        var dataTypes = fireproofableDataTypes
        dataTypes.remove(WKWebsiteDataTypeCookies)
        return dataTypes
    }()

    let cookieStorage: MigratableCookieStorage
    let fireproofing: Fireproofing
    let dataStoreIDManager: DataStoreIDManaging
    let dataStoreCleaner: WebsiteDataStoreCleaning
    let observationsCleaner: ObservationsDataCleaning

    public init(cookieStorage: MigratableCookieStorage,
                fireproofing: Fireproofing,
                dataStoreIDManager: DataStoreIDManaging,
                dataStoreCleaner: WebsiteDataStoreCleaning = DefaultWebsiteDataStoreCleaner(),
                observationsCleaner: ObservationsDataCleaning = DefaultObservationsDataCleaner()) {
        self.cookieStorage = cookieStorage
        self.fireproofing = fireproofing
        self.dataStoreIDManager = dataStoreIDManager
        self.dataStoreCleaner = dataStoreCleaner
        self.observationsCleaner = observationsCleaner
    }

    /// The previous version saved cookies externally to the data so we can move them between containers.  We now use
    /// the default persistence so this only needs to happen once when the fire button is pressed.
    ///
    /// The migration code removes the key that is used to check for the isConsumed flag so will only be
    ///  true if the data needs to be migrated.
    public func consumeCookies(into httpCookieStore: DDGHTTPCookieStore) async {
        // This can only be true if the data has not yet been migrated.
        guard !cookieStorage.isConsumed else { return }

        let cookies = cookieStorage.cookies
        var consumedCookiesCount = 0
        for cookie in cookies {
            consumedCookiesCount += 1
            await httpCookieStore.setCookie(cookie)
        }

        cookieStorage.setConsumed()
    }

    public func removeCookies(forDomains domains: [String],
                              fromDataStore dataStore: any DDGWebsiteDataStore) async {
        let startTime = CACurrentMediaTime()
        let cookieStore = dataStore.httpCookieStore
        let cookies = await cookieStore.allCookies()
        for cookie in cookies where domains.contains(where: { HTTPCookie.cookieDomain(cookie.domain, matchesTestDomain: $0) }) {
            await cookieStore.deleteCookie(cookie)
        }
        let totalTime = CACurrentMediaTime() - startTime
        Pixel.fire(pixel: .cookieDeletionTime(.init(number: totalTime)))
    }

    public func clear(dataStore: any DDGWebsiteDataStore) async {

        let count = await dataStoreCleaner.countContainers()
        await performMigrationIfNeeded(dataStoreIDManager: dataStoreIDManager, cookieStorage: cookieStorage, destinationStore: dataStore)
        await clearData(inDataStore: dataStore, withFireproofing: fireproofing, scope: .all)
        await dataStoreCleaner.removeAllContainersAfterDelay(previousCount: count)

    }
    
    /// Clears website data for specific domains, respecting fireproofing settings.
    ///
    /// Uses a data-store-first approach: iterates through data records (which have eTLD+1 as displayName),
    /// checks fireproofing on the displayName, then filters by whether the domain was visited.
    /// This matches the behavior of "Burn All" for consistency.
    public func clear(dataStore: any DDGWebsiteDataStore, forDomains domains: [String]) async {
        // Normalize visited domains to eTLD+1 upfront for matching against data records
        let tld = TLD()
        let visitedETLDplus1 = Set(domains.compactMap { tld.eTLDplus1($0) ?? $0 })
        
        let dataRecordInScope: DataRecordInScopeEvaluator = { recordDisplayName in
            visitedETLDplus1.contains(recordDisplayName)
        }
        
        let cookieInScope: CookieInScopeEvaluator = { cookie in
            domains.contains(where: { HTTPCookie.cookieDomain(cookie.domain, matchesTestDomain: $0) })
        }
        
        let scope = Scope.limited(dataRecords: dataRecordInScope, cookies: cookieInScope)
        await performMigrationIfNeeded(dataStoreIDManager: dataStoreIDManager, cookieStorage: cookieStorage, destinationStore: dataStore)
        await clearData(inDataStore: dataStore, withFireproofing: fireproofing, scope: scope)
    }

}

extension WebCacheManager {

    private func performMigrationIfNeeded(dataStoreIDManager: DataStoreIDManaging,
                                          cookieStorage: MigratableCookieStorage,
                                          destinationStore: any DDGWebsiteDataStore) async {

        // Check version here rather than on function so that we don't need complicated logic related to verison in the calling function.
        // Also, migration will not be needed if we are on a version lower than this.
        guard #available(iOS 17, *) else { return }

        // If there's no id, then migration has been done or isn't needed
        guard dataStoreIDManager.currentID != nil else { return }

        // Get all cookies, we'll clean them later to keep all that logic in the same place
        let cookies = cookieStorage.cookies

        // The returned cookies should be kept so move them to the data store
        for cookie in cookies {
            await destinationStore.httpCookieStore.setCookie(cookie)
        }

        cookieStorage.migrationComplete()
        dataStoreIDManager.invalidateCurrentID()
    }

    private func removeContainersIfNeeded(previousCount: Int) async {
        await dataStoreCleaner.removeAllContainersAfterDelay(previousCount: previousCount)
    }

    private func clearData(inDataStore dataStore: any DDGWebsiteDataStore,
                           withFireproofing fireproofing: Fireproofing,
                           scope: Scope) async {
        let startTime = CACurrentMediaTime()

        await clearDataForSafelyRemovableDataTypes(fromStore: dataStore, scope: scope)
        await clearFireproofableDataForNonFireproofDomains(fromStore: dataStore, usingFireproofing: fireproofing, scope: scope)
        await clearCookiesForNonFireproofedDomains(fromStore: dataStore, usingFireproofing: fireproofing, scope: scope)
        await observationsCleaner.removeObservationsData()

        let totalTime = CACurrentMediaTime() - startTime
        Pixel.fire(pixel: .clearDataInDefaultPersistence(.init(number: totalTime)))
    }

    @MainActor
    private func clearDataForSafelyRemovableDataTypes(fromStore dataStore: some DDGWebsiteDataStore,
                                                      scope: Scope) async {
        switch scope {
        case .all:
            await dataStore.removeData(ofTypes: Self.safelyRemovableWebsiteDataTypes, modifiedSince: Date.distantPast)
        case .limited(let dataRecords, _):
            let allRecords = await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
            let removableRecords = allRecords.filter { record in
                dataRecords(record.displayName)
            }
            await dataStore.removeData(ofTypes: Self.safelyRemovableWebsiteDataTypes, for: removableRecords)
        }
    }

    @MainActor
    private func clearFireproofableDataForNonFireproofDomains(fromStore dataStore: some DDGWebsiteDataStore,
                                                              usingFireproofing fireproofing: Fireproofing,
                                                              scope: Scope) async {
        let allRecords = await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let removableRecords = allRecords.filter { record in
            let fireproofed = fireproofing.isAllowed(fireproofDomain: record.displayName)
            return !fireproofed && scope.dataRecordsEvaluator(record.displayName)
        }

        let fireproofableTypesExceptCookies = Self.fireproofableDataTypesExceptCookies
        await dataStore.removeData(ofTypes: fireproofableTypesExceptCookies, for: removableRecords)
    }

    @MainActor
    private func clearCookiesForNonFireproofedDomains(fromStore dataStore: any DDGWebsiteDataStore, usingFireproofing fireproofing: Fireproofing, scope: Scope) async {
        let cookieStore = dataStore.httpCookieStore
        let cookies = await cookieStore.allCookies()

        let cookiesToRemove = cookies.filter { cookie in
            let fireproofed = fireproofing.isAllowed(cookieDomain: cookie.domain)
            return !fireproofed && scope.cookiesEvaluator(cookie)
        }

        for cookie in cookiesToRemove {
            await cookieStore.deleteCookie(cookie)
        }
    }

}
