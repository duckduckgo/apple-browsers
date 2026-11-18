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

/// Counts of one summary window that feed the daily CPM coverage telemetry.
public struct CPMCoverageCounts: Equatable, Sendable {

    /// Above any bucket in the telemetry definition, and bounds the work a malformed message can cause.
    static let maxCount = 10_000

    /// Popups the heuristic saw that no rule handled.
    public let unhandled: Int
    /// Pages where Cookie Popup Management ran.
    public let pages: Int

    public init(unhandled: Int, pages: Int) {
        self.unhandled = Self.clamp(unhandled)
        self.pages = Self.clamp(pages)
    }

    /// For summaries that native builds itself (the legacy path); the extension sends the counts directly.
    public init(summary: [String: Int]) {
        let patterns = Self.clamp(summary[CPMCoverageReporter.SummaryKey.detectedByPatterns] ?? 0)
        let both = Self.clamp(summary[CPMCoverageReporter.SummaryKey.detectedByBoth] ?? 0)
        self.init(unhandled: max(0, patterns - both), pages: summary[CPMCoverageReporter.SummaryKey.pages] ?? 0)
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(0, value), maxCount)
    }
}

/// Turns the counts of one summary window into Event Hub native events for the daily CPM coverage telemetry.
/// Only counts leave this type: no URLs, domains or rule names.
public enum CPMCoverageReporter {

    /// Event Hub native event types. They must match the `source` of the counters in the remote `eventHub` telemetry;
    /// without that definition Event Hub ignores them.
    public enum EventType {
        public static let unhandled = "autoconsent_unhandled"
        public static let unhandledTop10k = "autoconsent_unhandled_top10k"
        public static let pages = "autoconsent_pages"
        public static let pagesTop10k = "autoconsent_pages_top10k"
    }

    /// Summary keys, as sent in the `autoconsent_summary` pixel.
    enum SummaryKey {
        static let pages = "init"
        static let detectedByPatterns = "detected-by-patterns"
        static let detectedByBoth = "detected-by-both"
    }

    /// - Parameter handleNativeEvent: called once per counted unit, since an Event Hub counter adds one per event.
    public static func report(counts: CPMCoverageCounts, siteRank: CPMSiteRank?, handleNativeEvent: (String) -> Void) {
        let isTop10k = siteRank == .top10k

        for _ in 0..<counts.unhandled {
            handleNativeEvent(EventType.unhandled)
            if isTop10k { handleNativeEvent(EventType.unhandledTop10k) }
        }
        for _ in 0..<counts.pages {
            handleNativeEvent(EventType.pages)
            if isTop10k { handleNativeEvent(EventType.pagesTop10k) }
        }
    }
}
