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
import Common
import Foundation
import GRDB
import History

protocol ChromiumHistoryReaderProtocol {
    func readVisits(since cutoff: Date) -> DataImportResult<HistoryImport.ParseResult>
}

final class ChromiumHistoryReader: ChromiumHistoryReaderProtocol {
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

    /// Values from Chromium's `ui/base/page_transition_types.h`.
    private enum Transition {
        static let coreMask: Int64 = 0xFF
        static let autoSubframe: Int64 = 3
        static let manualSubframe: Int64 = 4
        static let chainEnd: Int64 = 0x20000000
    }

    /// Seconds between 1601-01-01, where Chromium times start, and 1970-01-01.
    private let chromiumEpochOffset: TimeInterval = 11_644_473_600

    private let chromiumHistoryDatabaseURL: URL
    private var currentOperationType: ImportError.OperationType = .copyTemporaryFile

    init(chromiumDataDirectoryURL: URL) {
        self.chromiumHistoryDatabaseURL = chromiumDataDirectoryURL.appendingPathComponent(Constants.historyDatabaseName)
    }

    func readVisits(since cutoff: Date) -> DataImportResult<HistoryImport.ParseResult> {
        currentOperationType = .copyTemporaryFile
        do {
            // Chromium keeps the database locked while it runs, so read a copy.
            return try chromiumHistoryDatabaseURL.withTemporaryFile { temporaryDatabaseURL in
                .success(try readVisits(from: temporaryDatabaseURL, since: cutoff))
            }
        } catch {
            return .failure(ImportError(type: currentOperationType, underlyingError: error))
        }
    }

    // MARK: - Private

    private func readVisits(from databaseURL: URL, since cutoff: Date) throws -> HistoryImport.ParseResult {
        currentOperationType = .dbOpen
        let queue = try DatabaseQueue(path: databaseURL.path)

        currentOperationType = .fetchVisits
        let rows = try queue.read { database in
            try Row.fetchAll(database, sql: """
                SELECT urls.url, urls.title, visits.visit_time, visits.transition
                FROM visits JOIN urls ON urls.id = visits.url
                WHERE visits.visit_time >= ?
                ORDER BY visits.visit_time
                """, arguments: [chromiumTime(for: cutoff)])
        }

        var visits = [HistoryImport.Visit]()
        var skipped = 0
        for row in rows {
            guard let visit = visit(from: row) else {
                skipped += 1
                continue
            }
            visits.append(visit)
        }
        return HistoryImport.ParseResult(visits: visits, skipped: skipped)
    }

    private func visit(from row: Row) -> HistoryImport.Visit? {
        guard let urlString: String = row["url"],
              let visitTime: Int64 = row["visit_time"],
              let transition: Int64 = row["transition"] else {
            return nil
        }

        let coreTransition = transition & Transition.coreMask
        // Subframe navigations aren't pages the user visited, and visits without
        // CHAIN_END are intermediate hops of a redirect chain.
        guard coreTransition != Transition.autoSubframe,
              coreTransition != Transition.manualSubframe,
              transition & Transition.chainEnd != 0,
              let url = URL(string: urlString),
              url.isHttp || url.isHttps else {
            return nil
        }

        return HistoryImport.Visit(url: url, title: row["title"], date: date(fromChromiumTime: visitTime))
    }

    private func chromiumTime(for date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 + chromiumEpochOffset) * 1_000_000)
    }

    private func date(fromChromiumTime time: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time) / 1_000_000 - chromiumEpochOffset)
    }
}
