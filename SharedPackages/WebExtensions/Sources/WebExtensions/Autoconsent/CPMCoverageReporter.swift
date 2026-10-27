//
//  CPMCoverageReporter.swift
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

/// Turns the counts of one `autoconsent_summary` pixel into Event Hub native events for the daily CPM coverage
/// telemetry. Only counts leave this type: no URLs, domains or rule names.
public enum CPMCoverageReporter {

    /// Event Hub native event types. They must match the `source` of the counters in the remote `eventHub` telemetry;
    /// without that definition Event Hub ignores them.
    public enum EventType {
        public static let unhandled = "autoconsent_unhandled"
        public static let unhandledTop10k = "autoconsent_unhandled_top10k"
        public static let page = "autoconsent_page"
        public static let pageTop10k = "autoconsent_page_top10k"
    }

    /// Summary keys, as sent in the `autoconsent_summary` pixel.
    enum SummaryKey {
        static let pages = "init"
        static let detectedByPatterns = "detected-by-patterns"
        static let detectedByBoth = "detected-by-both"
    }

    /// Popups the heuristic saw that no rule handled.
    static func unhandledCount(in summary: [String: Int]) -> Int {
        max(0, (summary[SummaryKey.detectedByPatterns] ?? 0) - (summary[SummaryKey.detectedByBoth] ?? 0))
    }

    /// - Parameter handleNativeEvent: called once per counted unit, since an Event Hub counter adds one per event.
    public static func report(summary: [String: Int], siteRank: CPMSiteRank?, handleNativeEvent: (String) -> Void) {
        let unhandled = unhandledCount(in: summary)
        let pages = max(0, summary[SummaryKey.pages] ?? 0)
        let isTop10k = siteRank == .top10k

        for _ in 0..<unhandled {
            handleNativeEvent(EventType.unhandled)
            if isTop10k { handleNativeEvent(EventType.unhandledTop10k) }
        }
        for _ in 0..<pages {
            handleNativeEvent(EventType.page)
            if isTop10k { handleNativeEvent(EventType.pageTop10k) }
        }
    }
}
