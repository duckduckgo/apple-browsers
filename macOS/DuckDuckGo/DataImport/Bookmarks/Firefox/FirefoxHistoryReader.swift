//
//  FirefoxHistoryReader.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import GRDB
import BrowserServicesKit
import Common
import FoundationExtensions
import History

final class FirefoxHistoryReader {

    enum Constants {
        static let historyDatabaseName = "places.sqlite"
    }

    struct ImportError: DataImportError {
        enum OperationType: Int {
            case copyTemporaryFile
            case dbOpen
            case fetchTopSites
            case fetchVisits
            case importVisits
        }

        var action: DataImportAction = .favorites
        let type: OperationType
        let underlyingError: Error?

        var errorType: DataImport.ErrorType {
            switch type {
            case .copyTemporaryFile: .noData
            case .dbOpen, .fetchTopSites, .fetchVisits: .dataCorrupted
            case .importVisits: .other
            }
        }
    }

    final class FirefoxFrecentSite: FetchableRecord {
        var url: String
        let title: String?
        let frecency: Int
        let lastVisitDate: Int

        init(row: Row) throws {
            url = try row["url"] ?? { throw FetchableRecordError<FirefoxFrecentSite>(column: 0) }()
            title = try row["title"] ?? { throw FetchableRecordError<FirefoxFrecentSite>(column: 1) }()
            frecency = try row["frecency"] ?? { throw FetchableRecordError<FirefoxFrecentSite>(column: 2) }()
            lastVisitDate = try row["last_visit_date"] ?? { throw FetchableRecordError<FirefoxFrecentSite>(column: 3) }()
        }
    }

    private let tld: TLD
    private let firefoxHistoryDatabaseURL: URL
    private var currentOperationType: ImportError.OperationType = .copyTemporaryFile

    /// Set of search engine hostnames that Firefox uses as a filter
    private let searchHosts: Set<String> = ["google", "search.yahoo", "yahoo", "bing", "ask", "duckduckgo"]

    /// When frecent sites are from one of these search sites, the Firefox shortcut uses the provided URL
    private let searchShortcuts = ["amazon": "https://amazon.com", "baidu": "https://baidu.com", "google": "https://google.com", "yandex": "https://yandex.com"]

    init(firefoxDataDirectoryURL: URL, tld: TLD) {
        self.firefoxHistoryDatabaseURL = firefoxDataDirectoryURL.appendingPathComponent(Constants.historyDatabaseName)
        self.tld = tld
    }

    /// Returns a list of the most frequently, recently visited ("frecent") sites from the Firefox history database.
    func readFrecentSites() -> DataImportResult<[FirefoxFrecentSite]> {
        currentOperationType = .copyTemporaryFile
        do {
            return try firefoxHistoryDatabaseURL.withTemporaryFile { temporaryDatabaseURL in
                let frecentSites: [FirefoxFrecentSite] = try readFrecentSites(from: temporaryDatabaseURL)
                return .success(frecentSites)
            }
        } catch let error as ImportError {
            return .failure(error)
        } catch {
            return .failure(ImportError(type: currentOperationType, underlyingError: error))
        }
    }

    /// Returns the visits made since `cutoff` from the Firefox history database.
    func readVisits(since cutoff: Date) -> DataImportResult<[FirefoxHistoryImporter.Row]> {
        currentOperationType = .copyTemporaryFile
        do {
            return try withTemporaryCopyIncludingWriteAheadLog { temporaryDatabaseURL in
                currentOperationType = .dbOpen
                let queue = try DatabaseQueue(path: temporaryDatabaseURL.path)

                currentOperationType = .fetchVisits
                let rows = try queue.read { database in
                    try Row.fetchAll(database, sql: """
                        SELECT moz_places.url, moz_places.title, moz_places.hidden,
                               moz_historyvisits.visit_date, moz_historyvisits.visit_type
                        FROM moz_historyvisits JOIN moz_places ON moz_places.id = moz_historyvisits.place_id
                        WHERE moz_historyvisits.visit_date >= ?
                        """, arguments: [FirefoxHistoryImporter.firefoxTime(for: cutoff)])
                    .compactMap { row -> FirefoxHistoryImporter.Row? in
                        guard let url: String = row["url"] else { return nil }
                        return FirefoxHistoryImporter.Row(url: url,
                                                          title: row["title"],
                                                          visitDate: row["visit_date"],
                                                          visitType: row["visit_type"],
                                                          hidden: (row["hidden"] as Int? ?? 0) != 0)
                    }
                }
                return .success(rows)
            }
        } catch {
            return .failure(ImportError(action: .history, type: currentOperationType, underlyingError: error))
        }
    }

    // MARK: - Private

    /// Firefox uses WAL mode, so recent visits may still be in `places.sqlite-wal`.
    /// It's copied alongside the database under the matching name so SQLite applies it.
    private func withTemporaryCopyIncludingWriteAheadLog<T>(_ body: (URL) throws -> T) throws -> T {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let databaseCopy = directory.appendingPathComponent(firefoxHistoryDatabaseURL.lastPathComponent)
        try fileManager.copyItem(at: firefoxHistoryDatabaseURL, to: databaseCopy)
        let writeAheadLogURL = URL(fileURLWithPath: firefoxHistoryDatabaseURL.path + "-wal")
        if fileManager.fileExists(atPath: writeAheadLogURL.path) {
            try fileManager.copyItem(at: writeAheadLogURL, to: URL(fileURLWithPath: databaseCopy.path + "-wal"))
        }
        return try body(databaseCopy)
    }

    private func readFrecentSites(from databaseURL: URL) throws -> [FirefoxFrecentSite] {
        currentOperationType = .dbOpen
        let queue = try DatabaseQueue(path: databaseURL.path)

        currentOperationType = .fetchTopSites
        let frecentSites = try queue.read { database in
            try FirefoxFrecentSite.fetchAll(database, sql: allFrecentSitesQuery())
        }

        let validFrecentSites = frecentSites
            .filter { site in
                // Remove invalid URLs and match Firefox filtering (only HTTP/HTTPS URLs and not search engine hosts).
                guard let url = URL(string: site.url), let host = url.host else { return false }
                return (url.isHttps || url.isHttp) && !searchHosts.contains(where: { host.droppingWwwPrefix().hasPrefix("\($0).") })
            }.map { site in
                // If the site URL matches a search shortcut host, replace it with the corresponding shortcut URL.
                if let shortcutURL = extractSearchShortcutURL(for: site.url) {
                    site.url = shortcutURL
                }
                return site
            }
        return validFrecentSites
    }

    /// Returns the search shortcut URL for a given URL string, if applicable.
    ///
    /// Search site URLs with common subdomains (`www`, `wwwN`, `m`, `mobile`) or different eTLDs are consolidated to a single shortcut:
    /// - `www.amazon.com`, `m.amazon.de`, `amazon.co.uk` → `https://amazon.com`
    ///
    /// URLs from other sites or search sites with other subdomains are not consolidated and return `nil`:
    /// - `photos.google.com`, `smile.amazon.com` → `nil`
    private func extractSearchShortcutURL(for urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host,
              let eTLD = tld.eTLD(forStringURL: urlString) else {
            return nil
        }
        // Remove common subdomains ("www", "wwwN", "m", and "mobile") and eTLD to get the short hostname.
        let shortHostname = host.replacing(regex: #"^(m|mobile|www\d*)\."#, with: "").dropping(suffix: ".\(eTLD)")
        return searchShortcuts[shortHostname]
    }

    // MARK: - Database Queries

    private func allFrecentSitesQuery() -> String {
        return """
        SELECT
            url, title, frecency, last_visit_date
        FROM
            moz_places
        WHERE
            frecency >= 150 AND last_visit_date > 0 AND hidden = 0
        ORDER BY
            frecency DESC, last_visit_date DESC
        LIMIT
            240
        """
    }
}
