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

/// This is effectively a wrapper around a system singleton which returns abstracted wrapper.
///
///  We should turn this into a protocol and inject it where needed.
public enum DDGWebsiteDataStoreProvider {

    // Don't call this in tests.
    public static func current(dataStoreIDManager: DataStoreIDManaging = DataStoreIDManager.shared) -> DDGWebsiteDataStore {
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

    func removeCookies(forDomains domains: [String], fromDataStore: DDGWebsiteDataStore) async
    func consumeCookies(into httpCookieStore: DDGHTTPCookieStore) async
    func clear(dataStore: DDGWebsiteDataStore) async

}

public class WebCacheManager: WebsiteDataManaging {

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
                              fromDataStore dataStore: DDGWebsiteDataStore) async {
        let startTime = CACurrentMediaTime()
        let cookieStore = dataStore.httpCookieStore
        let cookies = await cookieStore.allCookies()
        for cookie in cookies where domains.contains(where: { HTTPCookie.cookieDomain(cookie.domain, matchesTestDomain: $0) }) {
            await cookieStore.deleteCookie(cookie)
        }
        let totalTime = CACurrentMediaTime() - startTime
        Pixel.fire(pixel: .cookieDeletionTime(.init(number: totalTime)))
    }

    public func clear(dataStore: DDGWebsiteDataStore) async {

        let count = await dataStoreCleaner.countContainers()
        await performMigrationIfNeeded(dataStoreIDManager: dataStoreIDManager, cookieStorage: cookieStorage, destinationStore: dataStore)
        await clearData(inDataStore: dataStore, withFireproofing: fireproofing)
        await dataStoreCleaner.removeAllContainersAfterDelay(previousCount: count)

    }

}

extension WebCacheManager {

    private func performMigrationIfNeeded(dataStoreIDManager: DataStoreIDManaging,
                                          cookieStorage: MigratableCookieStorage,
                                          destinationStore: DDGWebsiteDataStore) async {

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

    private func clearData(inDataStore dataStore: DDGWebsiteDataStore, withFireproofing fireproofing: Fireproofing) async {
        let startTime = CACurrentMediaTime()

        await clearDataForSafelyRemovableDataTypes(fromStore: dataStore)
        await clearFireproofableDataForNonFireproofDomains(fromStore: dataStore, usingFireproofing: fireproofing)
        await clearCookiesForNonFireproofedDomains(fromStore: dataStore, usingFireproofing: fireproofing)
        await observationsCleaner.removeObservationsData()

        let totalTime = CACurrentMediaTime() - startTime
        Pixel.fire(pixel: .clearDataInDefaultPersistence(.init(number: totalTime)))
    }

    @MainActor
    private func clearDataForSafelyRemovableDataTypes(fromStore dataStore: DDGWebsiteDataStore) async {
        await dataStore.removeData(ofTypes: Self.safelyRemovableWebsiteDataTypes, modifiedSince: Date.distantPast)
    }

    @MainActor
    private func clearFireproofableDataForNonFireproofDomains(fromStore dataStore: DDGWebsiteDataStore, usingFireproofing fireproofing: Fireproofing) async {
        let allRecords = await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let removableRecords = allRecords.filter { record in
            !fireproofing.isAllowed(fireproofDomain: record.displayName)
        }

        var fireproofableTypesExceptCookies = Self.fireproofableDataTypesExceptCookies
        fireproofableTypesExceptCookies.remove(WKWebsiteDataTypeCookies)
        await dataStore.removeData(ofTypes: fireproofableTypesExceptCookies, for: removableRecords)
    }

    @MainActor
    private func clearCookiesForNonFireproofedDomains(fromStore dataStore: DDGWebsiteDataStore, usingFireproofing fireproofing: Fireproofing) async {
        let cookieStore = dataStore.httpCookieStore
        let cookies = await cookieStore.allCookies()

        let cookiesToRemove = cookies.filter { cookie in
            !fireproofing.isAllowed(cookieDomain: cookie.domain)
        }

        for cookie in cookiesToRemove {
            await cookieStore.deleteCookie(cookie)
        }
    }

}

@MainActor
public protocol DDGWebsiteDataStore {

    var httpCookieStore: DDGHTTPCookieStore { get }

    func removeData(ofTypes types: Set<String>, modifiedSince: Date) async
    func dataRecords(ofTypes types: Set<String>) async -> [DDGWebsiteDataRecord]
    func removeData(ofTypes types: Set<String>, for records: [DDGWebsiteDataRecord]) async

}

@MainActor
public protocol DDGHTTPCookieStore {

    func setCookie(_ cookie: HTTPCookie) async
    func allCookies() async -> [HTTPCookie]
    func deleteCookie(_ cookie: HTTPCookie) async

}

@MainActor
public protocol DDGWebsiteDataRecord {

    var displayName: String { get }

}

struct WebsiteDataStoreWrapper: DDGWebsiteDataStore {

    let wrapped: WKWebsiteDataStore

    var httpCookieStore: any DDGHTTPCookieStore {
        return HTTPCookieStoreWrapper(wrapped: wrapped.httpCookieStore)
    }

    func removeData(ofTypes types: Set<String>, modifiedSince: Date) async {
        await wrapped.removeData(ofTypes: types, modifiedSince: modifiedSince)
    }
    
    func dataRecords(ofTypes types: Set<String>) async -> [any DDGWebsiteDataRecord] {
        await wrapped.dataRecords(ofTypes: types).map { record in
            WebsiteDataRecordWrapper(wrapped: record)
        }
    }
    
    func removeData(ofTypes types: Set<String>, for records: [any DDGWebsiteDataRecord]) async {
        let unwrappedRecords = records.compactMap { ($0 as? WebsiteDataRecordWrapper)?.wrapped }
        assert(unwrappedRecords.count == records.count)
        await wrapped.removeData(ofTypes: types, for: unwrappedRecords)
    }

}

public struct HTTPCookieStoreWrapper: DDGHTTPCookieStore {

    public let wrapped: WKHTTPCookieStore

    public init(wrapped: WKHTTPCookieStore) {
        self.wrapped = wrapped
    }

    public func setCookie(_ cookie: HTTPCookie) async {
        await wrapped.setCookie(cookie)
    }
    
    public func allCookies() async -> [HTTPCookie] {
        await wrapped.allCookies()
    }
    
    public func deleteCookie(_ cookie: HTTPCookie) async {
        await wrapped.deleteCookie(cookie)
    }

}

struct WebsiteDataRecordWrapper: DDGWebsiteDataRecord {

    var displayName: String {
        wrapped.displayName
    }

    let wrapped: WKWebsiteDataRecord

}
