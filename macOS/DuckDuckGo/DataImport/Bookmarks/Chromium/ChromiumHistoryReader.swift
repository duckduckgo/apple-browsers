//
//  ChromiumHistoryReader.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Foundation
import GRDB
import History

final class ChromiumHistoryReader {

    enum Constants {
        static let historyDatabaseName = "History"
    }

    struct ImportError: DataImportError {
        enum OperationType: Int {
            case copyTemporaryFile
            case dbOpen
            case fetchVisits
            case importVisits
        }

        var action: DataImportAction { .history }
        let type: OperationType
        let underlyingError: Error?

        var errorType: DataImport.ErrorType {
            switch type {
            case .copyTemporaryFile: .noData
            case .dbOpen, .fetchVisits: .dataCorrupted
            case .importVisits: .other
            }
        }
    }

    private let chromiumHistoryDatabaseURL: URL
    private var currentOperationType: ImportError.OperationType = .copyTemporaryFile

    init(chromiumDataDirectoryURL: URL) {
        self.chromiumHistoryDatabaseURL = chromiumDataDirectoryURL.appendingPathComponent(Constants.historyDatabaseName)
    }

    func readVisits(since cutoff: Date) -> DataImportResult<[ChromiumHistoryImporter.Row]> {
        do {
            currentOperationType = .copyTemporaryFile
            // Chrome keeps the database locked while running, so read a copy.
            return try chromiumHistoryDatabaseURL.withTemporaryFile { temporaryDatabaseURL in
                currentOperationType = .dbOpen
                let queue = try DatabaseQueue(path: temporaryDatabaseURL.path)

                currentOperationType = .fetchVisits
                let rows = try queue.read { database in
                    try Row.fetchAll(database, sql: """
                        SELECT urls.url, urls.title, visits.visit_time, visits.transition
                        FROM visits JOIN urls ON urls.id = visits.url
                        WHERE visits.visit_time >= ?
                        """, arguments: [ChromiumHistoryImporter.chromiumTime(for: cutoff)])
                    .compactMap { row -> ChromiumHistoryImporter.Row? in
                        guard let url: String = row["url"] else { return nil }
                        return ChromiumHistoryImporter.Row(url: url,
                                                           title: row["title"],
                                                           visitTime: row["visit_time"],
                                                           transition: row["transition"])
                    }
                }
                return .success(rows)
            }
        } catch {
            return .failure(ImportError(type: currentOperationType, underlyingError: error))
        }
    }

}
