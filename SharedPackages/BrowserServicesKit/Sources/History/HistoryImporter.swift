//
//  HistoryImporter.swift
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
import FoundationExtensions

/// Adds visits read from another browser's history to the local history.
public enum HistoryImporter {

    public struct ImportedVisit: Equatable, Sendable {
        public let url: URL
        public let title: String?
        public let date: Date

        public init(url: URL, title: String?, date: Date) {
            self.url = url
            self.title = title
            self.date = date
        }
    }

    public struct ParseResult: Equatable, Sendable {
        public let visits: [ImportedVisit]
        /// Rows the browser reader could not turn into a visit, such as redirects, failed loads and non-web URLs.
        public let skipped: Int

        public init(visits: [ImportedVisit], skipped: Int) {
            self.visits = visits
            self.skipped = skipped
        }
    }

    public struct Summary: Equatable, Sendable {
        public var imported = 0
        public var alreadyInHistory = 0
        /// Older than the history retention window, so they would be deleted on the next cleanup.
        public var tooOld = 0
        public var skipped = 0
    }

    public enum ImportError: Error {
        case historyNotLoaded
    }

    /// Adds visits to history, skipping ones older than `cutoff` or already present.
    @MainActor
    public static func importVisits(
        _ parseResult: ParseResult,
        into historyCoordinator: HistoryCoordinator,
        cutoff: Date = .monthAgo
    ) throws -> Summary {
        guard let historyDictionary = historyCoordinator.historyDictionary else {
            throw ImportError.historyNotLoaded
        }

        var summary = Summary(skipped: parseResult.skipped)
        var knownVisits = Set<VisitKey>()
        for (url, entry) in historyDictionary {
            for visit in entry.visits {
                knownVisits.insert(VisitKey(url: url, date: visit.date))
            }
        }

        let newVisits = parseResult.visits.filter { visit in
            guard visit.date >= cutoff else {
                summary.tooOld += 1
                return false
            }
            guard knownVisits.insert(VisitKey(url: visit.url, date: visit.date)).inserted else {
                summary.alreadyInHistory += 1
                return false
            }
            return true
        }

        historyCoordinator.addImportedVisits(newVisits)
        summary.imported = newVisits.count
        return summary
    }

    private struct VisitKey: Hashable {
        let url: URL
        let date: Date
    }
}
