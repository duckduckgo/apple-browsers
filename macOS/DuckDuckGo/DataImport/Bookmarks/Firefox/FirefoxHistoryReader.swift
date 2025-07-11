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

final class FirefoxHistoryReader {

    enum Constants {
        static let historyDatabaseName = "places.sqlite"
    }

    struct ImportError: DataImportError {
        enum OperationType: Int {
            case copyTemporaryFile
            case dbOpen
            case fetchTopSites
        }

        var action: DataImportAction { .favorites }
        let type: OperationType
        let underlyingError: Error?

        var errorType: DataImport.ErrorType {
            switch type {
            case .copyTemporaryFile: .noData
            case .dbOpen, .fetchTopSites: .dataCorrupted
            }
        }
    }

    final class FirefoxFrecentSite: FetchableRecord {
        let url: String
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

    private let firefoxHistoryDatabaseURL: URL
    private var currentOperationType: ImportError.OperationType = .copyTemporaryFile

    /// Set of search engine hostnames that Firefox uses as a filter
    private let searchHosts: Set<String> = ["google", "search.yahoo", "yahoo", "bing", "ask", "duckduckgo"]

    init(firefoxDataDirectoryURL: URL) {
        self.firefoxHistoryDatabaseURL = firefoxDataDirectoryURL.appendingPathComponent(Constants.historyDatabaseName)
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

    // MARK: - Private

    private func readFrecentSites(from databaseURL: URL) throws -> [FirefoxFrecentSite] {
        currentOperationType = .dbOpen
        let queue = try DatabaseQueue(path: databaseURL.path)

        currentOperationType = .fetchTopSites
        let frecentSites = try queue.read { database in
            try FirefoxFrecentSite.fetchAll(database, sql: allFrecentSitesQuery())
        }

        /// Remove invalid URLs
        let validFrecentSites = frecentSites.filter { site in
            guard let url = URL(string: site.url), let host = url.host else { return false }
            return (url.isHttps || url.isHttp) && !searchHosts.contains(where: { host.contains($0) })
        }
        return validFrecentSites
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
