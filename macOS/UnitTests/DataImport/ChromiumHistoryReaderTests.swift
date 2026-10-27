//
//  ChromiumHistoryReaderTests.swift
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

final class ChromiumHistoryReaderTests {
    private struct VisitRow {
        let url: String
        let title: String
        let date: Date
        let transition: DatabaseValueConvertible
    }

    private let link: Int64 = 0
    private let typed: Int64 = 1
    private let autoSubframe: Int64 = 3
    private let keywordGenerated: Int64 = 10
    private let chainStart: Int64 = 0x10000000
    private let chainEnd: Int64 = 0x20000000

    private let profileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    deinit {
        try? FileManager.default.removeItem(at: profileURL)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Check if only web pages the user visited since the cutoff are read from the Chromium history database", .timeLimit(.minutes(1)))
    func readingVisitsSinceCutoff() throws {
        let cutoff = wholeSecondsDate(daysAgo: 30)
        let visitDate = wholeSecondsDate(daysAgo: 1)
        try makeHistoryDatabase(rows: [
            VisitRow(url: "https://duckduckgo.com/", title: "DuckDuckGo", date: visitDate, transition: link | chainStart | chainEnd),
            VisitRow(url: "https://ads.example.com/frame", title: "", date: visitDate, transition: autoSubframe | chainStart | chainEnd),
            VisitRow(url: "http://example.com/", title: "", date: visitDate, transition: typed | chainStart),
            VisitRow(url: "http://wikipedia.org/", title: "", date: visitDate, transition: keywordGenerated | chainStart | chainEnd),
            VisitRow(url: "chrome://settings/", title: "Settings", date: visitDate, transition: typed | chainStart | chainEnd),
            VisitRow(url: "https://damaged.example.com/", title: "Damaged", date: visitDate, transition: "not a transition"),
            VisitRow(url: "https://old.example.com/", title: "Old", date: wholeSecondsDate(daysAgo: 40), transition: link | chainStart | chainEnd),
        ])

        let result = try ChromiumHistoryReader(chromiumDataDirectoryURL: profileURL).readVisits(since: cutoff).get()

        #expect(result.visits == [HistoryImport.Visit(url: URL(string: "https://duckduckgo.com/")!, title: "DuckDuckGo", date: visitDate)])
        #expect(result.skipped == 5)
    }

    private func wholeSecondsDate(daysAgo days: Int) -> Date {
        Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - TimeInterval(days * 24 * 60 * 60)).rounded())
    }

    /// Microseconds since 1601-01-01 UTC.
    private func chromiumTime(for date: Date) -> Int64 {
        (Int64(date.timeIntervalSince1970) + 11_644_473_600) * 1_000_000
    }

    private func makeHistoryDatabase(rows: [VisitRow]) throws {
        try FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: profileURL.appendingPathComponent("History").path)
        try queue.write { database in
            try database.execute(sql: """
                CREATE TABLE urls (id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR);
                CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER NOT NULL, visit_time INTEGER NOT NULL, transition INTEGER NOT NULL);
                """)
            for (index, row) in rows.enumerated() {
                try database.execute(sql: "INSERT INTO urls (id, url, title) VALUES (?, ?, ?)",
                                     arguments: [index, row.url, row.title])
                try database.execute(sql: "INSERT INTO visits (url, visit_time, transition) VALUES (?, ?, ?)",
                                     arguments: [index, chromiumTime(for: row.date), row.transition])
            }
        }
    }
}
