//
//  ChromiumTopSitesReader.swift
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

final class ChromiumTopSitesReader {

    enum Constants {
        static let topSitesDatabaseName = "Top Sites"
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

    final class ChromiumTopSite: FetchableRecord {
        let url: String
        let title: String
        let urlRank: Int

        init(row: Row) throws {
            url = try row["url"] ?? { throw FetchableRecordError<ChromiumTopSite>(column: 0) }()
            title = try row["title"] ?? { throw FetchableRecordError<ChromiumTopSite>(column: 1) }()
            urlRank = try row["url_rank"] ?? { throw FetchableRecordError<ChromiumTopSite>(column: 2) }()
        }
    }

    private let chromiumTopSitesDatabaseURL: URL
    private var currentOperationType: ImportError.OperationType = .copyTemporaryFile

    init(chromiumDataDirectoryURL: URL) {
        self.chromiumTopSitesDatabaseURL = chromiumDataDirectoryURL.appendingPathComponent(Constants.topSitesDatabaseName)
    }

    func readTopSites() -> DataImportResult<[ChromiumTopSite]> {
        currentOperationType = .copyTemporaryFile
        do {
            return try chromiumTopSitesDatabaseURL.withTemporaryFile { temporaryDatabaseURL in
                let topSites: [ChromiumTopSite] = try readTopSites(from: temporaryDatabaseURL)
                return .success(topSites)
            }
        } catch let error as ImportError {
            return .failure(error)
        } catch {
            return .failure(ImportError(type: currentOperationType, underlyingError: error))
        }
    }

    // MARK: - Private

    private func readTopSites(from databaseURL: URL) throws -> [ChromiumTopSite] {
        currentOperationType = .dbOpen
        let queue = try DatabaseQueue(path: databaseURL.path)

        currentOperationType = .fetchTopSites
        let topSites = try queue.read { database in
            try ChromiumTopSite.fetchAll(database, sql: allTopSitesQuery())
        }

        /// Remove invalid URLs
        let validTopSites = topSites.filter { site in
            !site.url.isEmpty && URL(string: site.url) != nil
        }

        return validTopSites
    }

    // MARK: - Database Queries

    private func allTopSitesQuery() -> String {
        return """
        SELECT
            url, title, url_rank
        FROM
            top_sites
        ORDER BY
            url_rank ASC
        """
    }
}
