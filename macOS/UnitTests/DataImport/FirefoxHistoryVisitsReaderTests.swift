//
//  FirefoxHistoryVisitsReaderTests.swift
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

import Foundation
import GRDB
import History
import Testing

@testable import DuckDuckGo_Privacy_Browser

final class FirefoxHistoryVisitsReaderTests {
    private struct VisitRow {
        let url: String
        let date: Date
        let visitType: DatabaseValueConvertible
        var title = ""
        var hidden = false
        var fromVisit: Int?
    }

    private let link: Int64 = 1
    private let typed: Int64 = 2
    private let embed: Int64 = 4
    private let redirectPermanent: Int64 = 5
    private let download: Int64 = 7
    private let framedLink: Int64 = 8

    private let profileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    /// Kept open while reading, like Firefox keeps its connection, so the rows stay in `places.sqlite-wal`.
    private var writerQueue: DatabaseQueue?

    deinit {
        writerQueue = nil
        try? FileManager.default.removeItem(at: profileURL)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check if only web pages the user visited since the cutoff are read from the Firefox places database, including its write-ahead log", .timeLimit(.minutes(1)))
    func readingVisitsSinceCutoff() throws {
        let cutoff = wholeSecondsDate(daysAgo: 30)
        let visitDate = wholeSecondsDate(daysAgo: 2)
        let redirectDate = wholeSecondsDate(daysAgo: 1)
        try makePlacesDatabase(rows: [
            VisitRow(url: "https://duckduckgo.com/", date: visitDate, visitType: link, title: "DuckDuckGo"),
            VisitRow(url: "https://ads.example.com/embed", date: visitDate, visitType: embed),
            VisitRow(url: "https://ads.example.com/frame", date: visitDate, visitType: framedLink),
            VisitRow(url: "https://example.com/file.zip", date: visitDate, visitType: download),
            VisitRow(url: "https://hidden.example.com/", date: visitDate, visitType: link, hidden: true),
            VisitRow(url: "http://example.com/", date: redirectDate, visitType: typed),
            VisitRow(url: "https://example.com/", date: redirectDate, visitType: redirectPermanent, title: "Example", fromVisit: 6),
            VisitRow(url: "about:preferences", date: visitDate, visitType: typed),
            VisitRow(url: "https://damaged.example.com/", date: visitDate, visitType: "not a visit type"),
            VisitRow(url: "https://old.example.com/", date: wholeSecondsDate(daysAgo: 40), visitType: link),
        ])

        let result = try FirefoxHistoryVisitsReader(firefoxDataDirectoryURL: profileURL).readVisits(since: cutoff).get()

        #expect(result.visits == [
            HistoryImport.Visit(url: URL(string: "https://duckduckgo.com/")!, title: "DuckDuckGo", date: visitDate),
            HistoryImport.Visit(url: URL(string: "https://example.com/")!, title: "Example", date: redirectDate),
        ])
        #expect(result.skipped == 7)
    }

    private func wholeSecondsDate(daysAgo days: Int) -> Date {
        Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - TimeInterval(days * 24 * 60 * 60)).rounded())
    }

    /// Microseconds since 1970-01-01 UTC.
    private func firefoxTime(for date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970) * 1_000_000
    }

    /// Rows get ids from 1 in order, so `fromVisit` refers to a row by its position plus one.
    private func makePlacesDatabase(rows: [VisitRow]) throws {
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: profileURL.appendingPathComponent("places.sqlite").path)
        try queue.writeWithoutTransaction { database in
            try database.execute(sql: "PRAGMA journal_mode = WAL; PRAGMA wal_autocheckpoint = 0")
        }
        try queue.write { database in
            try database.execute(sql: """
                CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR, hidden INTEGER DEFAULT 0 NOT NULL);
                CREATE TABLE moz_historyvisits (id INTEGER PRIMARY KEY, from_visit INTEGER, place_id INTEGER, visit_date INTEGER, visit_type INTEGER);
                """)
            for (index, row) in rows.enumerated() {
                try database.execute(sql: "INSERT INTO moz_places (id, url, title, hidden) VALUES (?, ?, ?, ?)",
                                     arguments: [index + 1, row.url, row.title, row.hidden])
                try database.execute(sql: "INSERT INTO moz_historyvisits (id, from_visit, place_id, visit_date, visit_type) VALUES (?, ?, ?, ?, ?)",
                                     arguments: [index + 1, row.fromVisit, index + 1, firefoxTime(for: row.date), row.visitType])
            }
        }
        writerQueue = queue
    }
}
