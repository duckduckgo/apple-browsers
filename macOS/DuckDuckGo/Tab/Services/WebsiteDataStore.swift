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

    init(fireproofDomains: FireproofDomains, websiteDataStore: WebsiteDataStore = WKWebsiteDataStore.default()) {
        self.fireproofDomains = fireproofDomains
        self.websiteDataStore = websiteDataStore
    }

    func clear(baseDomains: Set<String>? = nil, dataClearingWideEventService: DataClearingWideEventService? = nil) async {
        // first cleanup ~/Library/Caches
        dataClearingWideEventService?.start(.clearFileCache)
        let fileCacheResult = await clearFileCache()
        dataClearingWideEventService?.update(.clearFileCache, result: fileCacheResult)

        dataClearingWideEventService?.start(.clearDeviceHashSalts)
        let deviceHashSaltsResult = await clearDeviceHashSalts()
        dataClearingWideEventService?.update(.clearDeviceHashSalts, result: deviceHashSaltsResult)

        dataClearingWideEventService?.start(.clearSafelyRemovableWebsiteData)
        let safelyRemovableResult = await removeAllSafelyRemovableDataTypes()
        dataClearingWideEventService?.update(.clearSafelyRemovableWebsiteData, result: safelyRemovableResult)

        dataClearingWideEventService?.start(.clearFireproofableDataForNonFireproofDomains)
        let fireproofableDataResult = await removeLocalStorageAndIndexedDBForNonFireproofDomains()
        dataClearingWideEventService?.update(.clearFireproofableDataForNonFireproofDomains, result: fireproofableDataResult)

        dataClearingWideEventService?.start(.clearCookiesForNonFireproofedDomains)
        let cookiesResult = await removeCookies(for: baseDomains)
        dataClearingWideEventService?.update(.clearCookiesForNonFireproofedDomains, result: cookiesResult)

        dataClearingWideEventService?.start(.clearRemoveResourceLoadStatisticsDatabase)
        let resourceLoadStatsResult = await self.removeResourceLoadStatisticsDatabase()
        dataClearingWideEventService?.update(.clearRemoveResourceLoadStatisticsDatabase, result: resourceLoadStatsResult)
    }

    private func clearFileCache() async -> Result<Void, Error> {
        var firstError: Error?
        let fm = FileManager.default
        let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent(Bundle.main.bundleIdentifier!)
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: false, attributes: nil)
        } catch {
            Logger.general.error("Could not create temporary directory: \(error.localizedDescription)")
            firstError = firstError ?? error
        }

        var contents: [String] = []
        do {
            contents = try fm.contentsOfDirectory(atPath: cachesDir.path)
        } catch {
            firstError = firstError ?? error
        }

        for name in contents {
            guard ["WebKit", "fsCachedData"].contains(name) || name.hasPrefix("Cache.") else { continue }

            do {
                try fm.moveItem(at: cachesDir.appendingPathComponent(name), to: tmpDir.appendingPathComponent(name))
            } catch {
                firstError = firstError ?? error
            }
        }

        do {
            try fm.createDirectory(at: cachesDir.appendingPathComponent("WebKit"),
                                    withIntermediateDirectories: false,
                                    attributes: nil)
        } catch {
            firstError = firstError ?? error
        }

        Process("/bin/rm", "-rf", tmpDir.path).launch()

        if let error = firstError {
            return .failure(error)
        }
        return .success(())
    }

    private func clearDeviceHashSalts() async -> Result<Void, Error> {
        var firstError: Error?

        guard let bundleID = Bundle.main.bundleIdentifier,
              var libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            let error = DataClearingWideEventError(description: "Could not get bundle ID or library URL")
            return .failure(error)
        }
        libraryURL.appendPathComponent("WebKit/\(bundleID)/WebsiteData/DeviceIdHashSalts/1")

        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        do {
            try fm.createDirectory(at: tmpDir, withIntermediateDirectories: false, attributes: nil)
        } catch {
            Logger.general.error("Could not create temporary directory: \(error.localizedDescription)")
            firstError = firstError ?? error
        }

        do {
            try fm.moveItem(at: libraryURL, to: tmpDir.appendingPathComponent("1"))
        } catch {
            firstError = firstError ?? error
        }

        do {
            try fm.createDirectory(at: libraryURL,
                                    withIntermediateDirectories: false,
                                    attributes: nil)
        } catch {
            firstError = firstError ?? error
        }

        Process("/bin/rm", "-rf", tmpDir.path).launch()

        if let error = firstError {
            return .failure(error)
        }
        return .success(())
    }

    @MainActor
    private func removeAllSafelyRemovableDataTypes() async -> Result<Void, Error> {
        let safelyRemovableTypes = WKWebsiteDataStore.safelyRemovableWebsiteDataTypes

        // Remove all data except cookies, local storage, and IndexedDB for all domains, and then filter cookies to preserve those allowed by Fireproofing.
        await websiteDataStore.removeData(ofTypes: safelyRemovableTypes, modifiedSince: Date.distantPast)
        return .success(())
    }

    @MainActor
    private func removeLocalStorageAndIndexedDBForNonFireproofDomains() async -> Result<Void, Error> {
        let allRecords = await websiteDataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())

        let removableRecords = allRecords.filter { record in
            // For Local Storage, only remove records that *exactly match* the display name.
            // Subdomains or root domains should be excluded.
            !URL.duckduckgoDomain.contains(record.displayName) && !URL.duckAiDomain.contains(record.displayName) && !fireproofDomains.fireproofDomains.contains(record.displayName)
        }
        await websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypesExceptCookies, for: removableRecords)
        return .success(())
    }

    @MainActor
    private func removeCookies(for baseDomains: Set<String>? = nil) async -> Result<Void, Error> {
        guard let cookieStore = websiteDataStore.cookieStore else {
            return .failure(DataClearingWideEventError(description: "cookieStore not available"))
        }
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
        return .success(())
    }

    // WKWebView doesn't provide a way to remove the observations database, which contains domains that have been
    // visited by the user. This database is removed directly as a part of the Fire button process.
    private func removeResourceLoadStatisticsDatabase() async -> Result<Void, Error> {
        var firstError: Error?

        guard let bundleID = Bundle.main.bundleIdentifier,
              var libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            let error = DataClearingWideEventError(description: "Could not get bundle ID or library URL")
            return .failure(error)
        }

        libraryURL.appendPathComponent("WebKit/\(bundleID)/WebsiteData/ResourceLoadStatistics")

        var contentsOfDirectory: [URL] = []
        do {
            contentsOfDirectory = try FileManager.default.contentsOfDirectory(at: libraryURL, includingPropertiesForKeys: [.nameKey])
        } catch {
            firstError = firstError ?? error
        }

        let fileNames = contentsOfDirectory.compactMap(\.suggestedFilename)

        guard fileNames.contains("observations.db") else {
            // Database doesn't exist, nothing to clear
            if let error = firstError {
                return .failure(error)
            }
            return .success(())
        }

        // We've confirmed that the observations.db exists, now it can be cleaned out. We can't delete it entirely, as
        // WebKit won't recreate it until next app launch.

        let databasePath = libraryURL.appendingPathComponent("observations.db")

        guard let pool = try? DatabasePool(path: databasePath.absoluteString) else {
            let error = DataClearingWideEventError(description: "Could not open observations database")
            return .failure(firstError ?? error)
        }

        removeObservationsData(from: pool, firstError: &firstError)

        do {
            try await pool.vacuum()
        } catch {
            firstError = firstError ?? error
        }

        // For an unknown reason, domains may be still present in the database binary when running `strings` over it, despite SQL queries returning an
        // empty array, and despite vacuuming the database. Delete again to be safe.
        removeObservationsData(from: pool, firstError: &firstError)

        if let error = firstError {
            return .failure(error)
        }
        return .success(())
    }

    private func removeObservationsData(from pool: DatabasePool, firstError: inout Error?) {
        do {
            try pool.write { database in
                try database.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE);")

                let tables = try String.fetchAll(database, sql: "SELECT name FROM sqlite_master WHERE type='table'")

                for table in tables {
                    try database.execute(sql: "DELETE FROM \(table)")
                }
            }
        } catch {
            Logger.fire.error("Failed to clear observations database: \(error.localizedDescription)")
            firstError = firstError ?? error
        }
    }
}

extension WKHTTPCookieStore: HTTPCookieStore {}

extension WKWebsiteDataStore: WebsiteDataStore {

    var cookieStore: HTTPCookieStore? {
        httpCookieStore
    }

}
