//
//  FirefoxHistoryImporter.swift
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

/// Maps rows from a Firefox `places.sqlite` database (`moz_historyvisits` joined with `moz_places`)
/// to visits that `SafariHistoryImporter.importVisits` can add to history.
public enum FirefoxHistoryImporter {

    public struct Row: Equatable {
        public let url: String
        public let title: String?
        /// Microseconds since 1970-01-01 UTC.
        public let visitDate: Int64
        public let visitType: Int64
        /// Firefox hides redirect sources and other places that shouldn't show up in history.
        public let hidden: Bool

        public init(url: String, title: String?, visitDate: Int64, visitType: Int64, hidden: Bool) {
            self.url = url
            self.title = title
            self.visitDate = visitDate
            self.visitType = visitType
            self.hidden = hidden
        }
    }

    /// Values of `nsINavHistoryService.TRANSITION_*` that aren't page visits.
    private enum VisitType {
        static let embed: Int64 = 4
        static let download: Int64 = 7
        static let framedLink: Int64 = 8
    }

    public static func firefoxTime(for date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1_000_000)
    }

    public static func parse(_ rows: [Row]) -> SafariHistoryImporter.ParseResult {
        var visits = [SafariHistoryImporter.ImportedVisit]()
        var skipped = 0
        for row in rows {
            guard !row.hidden,
                  row.visitType != VisitType.embed,
                  row.visitType != VisitType.download,
                  row.visitType != VisitType.framedLink,
                  let url = URL(string: row.url),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                skipped += 1
                continue
            }
            visits.append(.init(url: url,
                                title: row.title,
                                date: Date(timeIntervalSince1970: TimeInterval(row.visitDate) / 1_000_000)))
        }
        return .init(visits: visits, skipped: skipped)
    }
}
