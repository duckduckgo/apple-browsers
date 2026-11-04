//
//  SafariHistoryReaderTests.swift
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
import History
import Testing

@testable import DuckDuckGo_Privacy_Browser

struct SafariHistoryReaderTests {
    @available(iOS 16, macOS 13, *)
    @Test("Check if only web pages the user saw since the cutoff are read from Safari's History.json", .timeLimit(.minutes(1)))
    func readingVisitsSinceCutoff() throws {
        let cutoff = wholeSecondsDate(daysAgo: 30)
        let visitDate = wholeSecondsDate(daysAgo: 1)
        let historyJSON = try makeHistoryJSON(rows: [
            row(url: "https://duckduckgo.com/", title: "DuckDuckGo", date: visitDate),
            row(url: "http://duckduckgo.com/", date: visitDate, extra: ["destination_url": "https://duckduckgo.com/"]),
            row(url: "https://broken.example.com/", date: visitDate, extra: ["latest_visit_was_load_failure": true]),
            row(url: "file:///Users/user/page.html", date: visitDate),
            ["url": "https://damaged.example.com/", "time_usec": "not a time"],
            row(url: "https://old.example.com/", date: wholeSecondsDate(daysAgo: 40)),
        ])

        let result = try SafariHistoryReader().readVisits(fromHistoryJSON: historyJSON, since: cutoff).get()

        #expect(result.visits == [HistoryImport.Visit(url: URL(string: "https://duckduckgo.com/")!, title: "DuckDuckGo", date: visitDate)])
        #expect(result.skipped == 4)
    }

    private func wholeSecondsDate(daysAgo days: Int) -> Date {
        Date(timeIntervalSince1970: (Date().timeIntervalSince1970 - TimeInterval(days * 24 * 60 * 60)).rounded())
    }

    private func row(url: String, title: String? = nil, date: Date, extra: [String: Any] = [:]) -> [String: Any] {
        var row: [String: Any] = ["url": url, "time_usec": Int64(date.timeIntervalSince1970) * 1_000_000, "visit_count": 1]
        row["title"] = title
        return row.merging(extra) { _, new in new }
    }

    private func makeHistoryJSON(rows: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "metadata": ["browser_name": "Safari", "data_type": "history", "schema_version": 1],
            "history": rows,
        ])
    }
}
