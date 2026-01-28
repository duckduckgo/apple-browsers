//
//  WebsiteDataStore.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import GRDB
import Subscription
import os.log

public protocol HTTPCookieStore {
    func allCookies() async -> [HTTPCookie]
    func setCookie(_ cookie: HTTPCookie) async
    func deleteCookie(_ cookie: HTTPCookie) async
}

protocol WebsiteDataStore {
    var cookieStore: HTTPCookieStore? { get }

    @MainActor func dataRecords(ofTypes dataTypes: Set<String>) async -> [WKWebsiteDataRecord]
    @MainActor func removeData(ofTypes dataTypes: Set<String>, modifiedSince date: Date) async
    @MainActor func removeData(ofTypes dataTypes: Set<String>, for records: [WKWebsiteDataRecord]) async
}

internal class WebCacheManager {

    private let fireproofDomains: FireproofDomains
    private let websiteDataStore: WebsiteDataStore
    
    enum ClearSteps: String {
        case fileCache = "file_cache"
        case deviceHashSalts = "device_hash_salts"
        case safelyRemovableDataTypes = "safely_removable_data_types"
        case localStorageAndIndexedDBForNonFireproofDomains = "local_storage_and_indexed_db_for_non_fireproof_domains"
        case cookies
        case resourceLoadStatisticsDatabase = "resource_load_statistics_database"
    }

    init(fireproofDomains: FireproofDomains, websiteDataStore: WebsiteDataStore = WKWebsiteDataStore.default()) {
        self.fireproofDomains = fireproofDomains
        self.websiteDataStore = websiteDataStore
    }

    func clear(baseDomains: Set<String>? = nil) async {
        let startTime = Date()
        // first cleanup ~/Library/Caches
        await clearFileCache()

        await clearDeviceHashSalts()

        await removeAllSafelyRemovableDataTypes()

        await removeLocalStorageAndIndexedDBForNonFireproofDomains()

        await removeCookies(for: baseDomains)

        await self.removeResourceLoadStatisticsDatabase()

        FirePixels.measure(with: FirePixels.burnWebCacheDuration, from: startTime)
        
        await checkResidue()
    }

    private func clearFileCache() async {
        let fm = FileManager.default
        let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier!)
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: false, attributes: nil)
        } catch {
            FirePixels.measure(with: FirePixels.burnWebCacheError(error))
            Logger.general.error("Could not create temporary directory: \(error.localizedDescription)")
            return
        }

        let contents = try? fm.contentsOfDirectory(atPath: cachesDir.path)
        for name in contents ?? [] {
            guard ["WebKit", "fsCachedData"].contains(name) || name.hasPrefix("Cache.") else { continue }
            do {
                try fm.moveItem(at: cachesDir.appendingPathComponent(name), to: tmpDir.appendingPathComponent(name))
            } catch {
                FirePixels.measure(with: FirePixels.burnWebCacheError(error))
            }
        }

        do {
            try fm.createDirectory(at: cachesDir.appendingPathComponent("WebKit"),
                                    withIntermediateDirectories: false,
                                    attributes: nil)
        } catch {
            FirePixels.measure(with: FirePixels.burnWebCacheError(error))
        }

        Process("/bin/rm", "-rf", tmpDir.path).launch()
    }

    private func clearDeviceHashSalts() async {
        guard let bundleID = Bundle.main.bundleIdentifier,
              var libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return
        }
        libraryURL.appendPathComponent("WebKit/\(bundleID)/WebsiteData/DeviceIdHashSalts/1")

        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: false, attributes: nil)
        } catch {
            FirePixels.measure(with: FirePixels.burnWebCacheError(error))
            Logger.general.error("Could not create temporary directory: \(error.localizedDescription)")
            return
        }
        
        do {
            try fm.moveItem(at: libraryURL, to: tmpDir.appendingPathComponent("1"))
        } catch {
            FirePixels.measure(with: FirePixels.burnWebCacheError(error))
        }

        do {
            try fm.createDirectory(at: libraryURL,
                                    withIntermediateDirectories: false,
                                    attributes: nil)
        } catch {
            FirePixels.measure(with: FirePixels.burnWebCacheError(error))
        }

        Process("/bin/rm", "-rf", tmpDir.path).launch()
    }

    @MainActor
    private func removeAllSafelyRemovableDataTypes() async {
        let safelyRemovableTypes = WKWebsiteDataStore.safelyRemovableWebsiteDataTypes

        // Remove all data except cookies, local storage, and IndexedDB for all domains, and then filter cookies to preserve those allowed by Fireproofing.
        await websiteDataStore.removeData(ofTypes: safelyRemovableTypes, modifiedSince: Date.distantPast)
    }

    @MainActor
    private func removeLocalStorageAndIndexedDBForNonFireproofDomains() async {
        let allRecords = await websiteDataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())

        let removableRecords = allRecords.filter { record in
            // For Local Storage, only remove records that *exactly match* the display name.
            // Subdomains or root domains should be excluded.
            !URL.duckduckgoDomain.contains(record.displayName) && !URL.duckAiDomain.contains(record.displayName) && !fireproofDomains.fireproofDomains.contains(record.displayName)
        }

        await websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypesExceptCookies, for: removableRecords)
    }

    @MainActor
    private func removeCookies(for baseDomains: Set<String>? = nil) async {
        guard let cookieStore = websiteDataStore.cookieStore else { return }
        var cookies = await cookieStore.allCookies()

        if let baseDomains = baseDomains {
            // If domains are specified, clear just their cookies
            cookies = cookies.filter { cookie in
                baseDomains.contains {
                    cookie.belongsTo($0)
                }
            }
        }

        // Don't clear fireproof domains
        let cookiesToRemove = cookies.filter { cookie in
            !self.fireproofDomains.isFireproof(cookieDomain: cookie.domain) && ![URL.duckduckgoDomain, URL.duckAiDomain].contains(cookie.domain)
        }

        for cookie in cookiesToRemove {
            Logger.fire.debug("Deleting cookie for \(cookie.domain) named \(cookie.name)")
            await cookieStore.deleteCookie(cookie)
        }
    }

    // WKWebView doesn't provide a way to remove the observations database, which contains domains that have been
    // visited by the user. This database is removed directly as a part of the Fire button process.
    private func removeResourceLoadStatisticsDatabase() async {
        guard let bundleID = Bundle.main.bundleIdentifier,
              var libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return
        }

        libraryURL.appendPathComponent("WebKit/\(bundleID)/WebsiteData/ResourceLoadStatistics")

        let contentsOfDirectory = (try? FileManager.default.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: [.nameKey])) ?? []
        let fileNames = contentsOfDirectory.compactMap(\.suggestedFilename)

        guard fileNames.contains("observations.db") else {
            return
        }

        // We've confirmed that the observations.db exists, now it can be cleaned out. We can't delete it entirely, as
        // WebKit won't recreate it until next app launch.

        let databasePath = libraryURL.appendingPathComponent("observations.db")

        guard let pool = try? DatabasePool(path: databasePath.absoluteString) else {
            return
        }

        removeObservationsData(from: pool)
        do {
            try await pool.vacuum()
        } catch {
            FirePixels.measure(with: FirePixels.burnWebCacheError(error))
        }

        // For an unknown reason, domains may be still present in the database binary when running `strings` over it, despite SQL queries returning an
        // empty array, and despite vacuuming the database. Delete again to be safe.
        removeObservationsData(from: pool)
    }

    private func removeObservationsData(from pool: DatabasePool) {
        do {
            try pool.write { database in
                try database.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE);")

                let tables = try String.fetchAll(database, sql: "SELECT name FROM sqlite_master WHERE type='table'")

                for table in tables {
                    try database.execute(sql: "DELETE FROM \(table)")
                }
            }
        } catch {
            FirePixels.measure(with: FirePixels.burnWebCacheError(error))
            Logger.fire.error("Failed to clear observations database: \(error.localizedDescription)")
        }
    }

}

// MARK: - Residue Check

private extension WebCacheManager {
    func checkResidue(for baseDomains: Set<String>? = nil) async {
        var stepsWithResidue: [ClearSteps] = []
        
        if checkFileCacheResidue() {
            stepsWithResidue.append(.fileCache)
        }
        if checkDeviceHashSalts() {
            stepsWithResidue.append(.deviceHashSalts)
        }
        
        if await checkSafelyRemovableDataTypesResidue() {
            stepsWithResidue.append(.safelyRemovableDataTypes)
        }
        
        if await checkLocalStorageResidue() {
            stepsWithResidue.append(.localStorageAndIndexedDBForNonFireproofDomains)
        }
        
        if await checkCookiesResidue() {
            stepsWithResidue.append(.cookies)
        }
        
        if !stepsWithResidue.isEmpty {
            let stepsString = stepsWithResidue.map{ $0.rawValue }
            FirePixels.measure(with: FirePixels.burnWebCacheHasResidue, stepsWithResidue: stepsString.joined(separator: ","))
        }
    }
    
    func checkFileCacheResidue() -> Bool {
        let fm = FileManager.default
        guard let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier!) else { return false }
        
        let contents = (try? fm.contentsOfDirectory(atPath: cachesDir.path)) ?? []
        return contents.contains { name in
            // "WebKit" is recreated. Skip it during recheck
            ["fsCachedData"].contains(name) || name.hasPrefix("Cache.")
        }
    }
    
    func checkDeviceHashSalts() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier,
              var libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return false
        }
        libraryURL.appendPathComponent("WebKit/\(bundleID)/WebsiteData/DeviceIdHashSalts/1")
            
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: libraryURL.path)) ?? []
        return !contents.isEmpty
    }
    
    @MainActor
    func checkSafelyRemovableDataTypesResidue() async -> Bool {
        let safelyRemovableTypes = WKWebsiteDataStore.safelyRemovableWebsiteDataTypes
        let records = await WKWebsiteDataStore.default().dataRecords(ofTypes: safelyRemovableTypes)
        return !records.isEmpty
    }
    
    @MainActor
    func checkLocalStorageResidue() async -> Bool {
        let records = await WKWebsiteDataStore.default().dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypesExceptCookies)
        
        return records.contains { record in
            !URL.duckduckgoDomain.contains(record.displayName) &&
            !URL.duckAiDomain.contains(record.displayName) &&
            !fireproofDomains.fireproofDomains.contains(record.displayName)
        }
    }
    
    @MainActor
    func checkCookiesResidue(for baseDomains: Set<String>? = nil) async -> Bool {
        guard let cookieStore = websiteDataStore.cookieStore else { return false }
        var cookies = await cookieStore.allCookies()
            
        if let baseDomains = baseDomains {
            cookies = cookies.filter { cookie in
                baseDomains.contains { cookie.belongsTo($0) }
            }
        }
            
        return cookies.contains { cookie in
            !self.fireproofDomains.isFireproof(cookieDomain: cookie.domain) &&
            cookie.domain != URL.duckduckgoDomain &&
            cookie.domain != URL.duckAiDomain
        }
    }
    
    func checkResourceLoadStatisticsDatabaseResidue() -> Bool {
       return false
    }
}

extension WKHTTPCookieStore: HTTPCookieStore {}

extension WKWebsiteDataStore: WebsiteDataStore {

    var cookieStore: HTTPCookieStore? {
        httpCookieStore
    }

}
