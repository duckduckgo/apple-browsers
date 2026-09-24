//
//  ChromiumHistoryImporter.swift
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

/// Maps rows from a Chromium `History` database (`visits` joined with `urls`) to visits
/// that `SafariHistoryImporter.importVisits` can add to history.
public enum ChromiumHistoryImporter {

    public struct Row: Equatable {
        public let url: String
        public let title: String?
        /// Microseconds since 1601-01-01 UTC.
        public let visitTime: Int64
        public let transition: Int64

        public init(url: String, title: String?, visitTime: Int64, transition: Int64) {
            self.url = url
            self.title = title
            self.visitTime = visitTime
            self.transition = transition
        }
    }

    /// Values from Chromium's `ui/base/page_transition_types.h`.
    private enum Transition {
        static let coreMask: Int64 = 0xFF
        static let autoSubframe: Int64 = 3
        static let manualSubframe: Int64 = 4
        static let chainEnd: Int64 = 0x20000000
    }

    /// Seconds between 1601-01-01 and 1970-01-01.
    private static let epochOffset: TimeInterval = 11_644_473_600

    public static func chromiumTime(for date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 + epochOffset) * 1_000_000)
    }

    public static func date(fromChromiumTime time: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time) / 1_000_000 - epochOffset)
    }

    public static func parse(_ rows: [Row]) -> SafariHistoryImporter.ParseResult {
        var visits = [SafariHistoryImporter.ImportedVisit]()
        var skipped = 0
        for row in rows {
            let coreType = row.transition & Transition.coreMask
            // Subframe navigations aren't pages the user visited, and visits without
            // CHAIN_END are intermediate hops of a redirect chain.
            guard coreType != Transition.autoSubframe,
                  coreType != Transition.manualSubframe,
                  row.transition & Transition.chainEnd != 0,
                  let url = URL(string: row.url),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                skipped += 1
                continue
            }
            visits.append(.init(url: url, title: row.title, date: date(fromChromiumTime: row.visitTime)))
        }
        return .init(visits: visits, skipped: skipped)
    }
}
