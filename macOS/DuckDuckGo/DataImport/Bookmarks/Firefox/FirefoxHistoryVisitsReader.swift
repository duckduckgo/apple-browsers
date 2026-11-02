//
//  FirefoxHistoryVisitsReader.swift
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

protocol FirefoxHistoryVisitsReaderProtocol {
    func readVisits(since cutoff: Date) -> DataImportResult<HistoryImport.ParseResult>
}

final class FirefoxHistoryVisitsReader: FirefoxHistoryVisitsReaderProtocol {
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

    /// Values of `nsINavHistoryService.TRANSITION_*`.
    private enum VisitType {
        static let embed: Int64 = 4
        static let redirectPermanent: Int64 = 5
        static let redirectTemporary: Int64 = 6
        static let download: Int64 = 7
        static let framedLink: Int64 = 8
    }

    private let firefoxHistoryDatabaseURL: URL
    private var currentOperationType: ImportError.OperationType = .copyTemporaryFile

    init(firefoxDataDirectoryURL: URL) {
        self.firefoxHistoryDatabaseURL = firefoxDataDirectoryURL.appendingPathComponent(FirefoxHistoryReader.Constants.historyDatabaseName)
    }

    func readVisits(since cutoff: Date) -> DataImportResult<HistoryImport.ParseResult> {
        currentOperationType = .copyTemporaryFile
        do {
            // Firefox keeps the database locked while it runs, so read a copy.
            return try withTemporaryCopyIncludingWriteAheadLog { temporaryDatabaseURL in
                .success(try readVisits(from: temporaryDatabaseURL, since: cutoff))
            }
        } catch {
            return .failure(ImportError(type: currentOperationType, underlyingError: error))
        }
    }

    // MARK: - Private

    /// Firefox uses WAL mode, so recent visits may still be in `places.sqlite-wal`.
    /// It's copied alongside the database under the matching name so SQLite applies it.
    private func withTemporaryCopyIncludingWriteAheadLog<T>(_ body: (URL) throws -> T) throws -> T {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directoryURL) }

        let databaseCopyURL = directoryURL.appendingPathComponent(firefoxHistoryDatabaseURL.lastPathComponent)
        try fileManager.copyItem(at: firefoxHistoryDatabaseURL, to: databaseCopyURL)
        let writeAheadLogURL = URL(fileURLWithPath: firefoxHistoryDatabaseURL.path + "-wal")
        if fileManager.fileExists(atPath: writeAheadLogURL.path) {
            try fileManager.copyItem(at: writeAheadLogURL, to: URL(fileURLWithPath: databaseCopyURL.path + "-wal"))
        }
        return try body(databaseCopyURL)
    }

    private func readVisits(from databaseURL: URL, since cutoff: Date) throws -> HistoryImport.ParseResult {
        currentOperationType = .dbOpen
        let queue = try DatabaseQueue(path: databaseURL.path)

        currentOperationType = .fetchVisits
        let rows = try queue.read { database in
            try Row.fetchAll(database, sql: """
                SELECT moz_places.url, moz_places.title, moz_places.hidden,
                       moz_historyvisits.visit_date, moz_historyvisits.visit_type,
                       EXISTS (
                           SELECT 1 FROM moz_historyvisits AS redirects
                           WHERE redirects.from_visit = moz_historyvisits.id AND redirects.visit_type IN (?, ?)
                       ) AS is_redirect_source
                FROM moz_historyvisits JOIN moz_places ON moz_places.id = moz_historyvisits.place_id
                WHERE moz_historyvisits.visit_date >= ?
                ORDER BY moz_historyvisits.visit_date
                """, arguments: [VisitType.redirectPermanent, VisitType.redirectTemporary, firefoxTime(for: cutoff)])
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
        // Typed row subscripts crash on a value of the wrong type, so a damaged row is converted leniently and skipped.
        guard let urlString = String.fromDatabaseValue(row["url"]),
              let visitDate = Int64.fromDatabaseValue(row["visit_date"]),
              let visitType = Int64.fromDatabaseValue(row["visit_type"]),
              let hidden = Int64.fromDatabaseValue(row["hidden"]),
              let isRedirectSource = Bool.fromDatabaseValue(row["is_redirect_source"]) else {
            return nil
        }

        // Embeds, framed links and downloads aren't pages the user visited, and Firefox hides
        // redirect sources and other places that shouldn't show up in its history.
        guard visitType != VisitType.embed,
              visitType != VisitType.framedLink,
              visitType != VisitType.download,
              hidden == 0,
              !isRedirectSource,
              let url = URL(string: urlString),
              url.isHttp || url.isHttps else {
            return nil
        }

        return HistoryImport.Visit(url: url, title: String.fromDatabaseValue(row["title"]), date: date(fromFirefoxTime: visitDate))
    }

    /// Microseconds since 1970-01-01 UTC.
    private func firefoxTime(for date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000_000)
    }

    private func date(fromFirefoxTime time: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time) / 1_000_000)
    }
}
