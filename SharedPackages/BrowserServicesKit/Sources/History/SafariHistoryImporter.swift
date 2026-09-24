//
//  SafariHistoryImporter.swift
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

/// Imports the `History.json` file from Safari's "Export Browsing Data" archive.
///
/// Safari exports one row per URL with the time of its latest visit, so each row becomes a single visit.
public enum SafariHistoryImporter {

    public struct ImportedVisit: Equatable, Sendable {
        public let url: URL
        public let title: String?
        public let date: Date
    }

    public struct ParseResult: Equatable, Sendable {
        public let visits: [ImportedVisit]
        /// Redirect hops, failed loads and non-web URLs.
        public let skipped: Int
    }

    public struct Summary: Equatable, Sendable {
        public var imported = 0
        public var alreadyInHistory = 0
        /// Older than the history retention window, so they would be deleted on the next cleanup.
        public var tooOld = 0
        public var skipped = 0
    }

    public enum ImportError: Error {
        case notSafariHistory
        case historyNotLoaded
    }

    private enum Constants {
        static let yieldInterval = 200
    }

    public static func parse(_ data: Data) throws -> ParseResult {
        let export = try JSONDecoder().decode(HistoryExport.self, from: data)
        guard export.metadata?.dataType == "history" else {
            throw ImportError.notSafariHistory
        }

        var visits = [ImportedVisit]()
        var skipped = 0
        for row in export.history {
            guard row.destinationURL == nil,
                  row.latestVisitWasLoadFailure != true,
                  let timeUsec = row.timeUsec,
                  let url = URL(string: row.url),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                skipped += 1
                continue
            }
            visits.append(ImportedVisit(url: url,
                                        title: row.title,
                                        date: Date(timeIntervalSince1970: timeUsec / 1_000_000.0)))
        }
        return ParseResult(visits: visits, skipped: skipped)
    }

    /// Adds visits to history, skipping ones older than `cutoff` or already present.
    @MainActor
    public static func importVisits(_ parseResult: ParseResult,
                                    into historyCoordinator: HistoryCoordinating,
                                    cutoff: Date = .monthAgo) async throws -> Summary {
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

        // Newest first, so every saved copy of an entry already carries its latest visit date,
        // even if the per-visit saves land out of order.
        let visits = parseResult.visits.sorted { $0.date > $1.date }
        for (index, visit) in visits.enumerated() {
            if index > 0, index.isMultiple(of: Constants.yieldInterval) {
                await Task.yield()
            }
            guard visit.date >= cutoff else {
                summary.tooOld += 1
                continue
            }
            guard knownVisits.insert(VisitKey(url: visit.url, date: visit.date)).inserted else {
                summary.alreadyInHistory += 1
                continue
            }
            guard historyCoordinator.addVisit(of: visit.url, at: visit.date) != nil else {
                throw ImportError.historyNotLoaded
            }
            if let title = visit.title, !title.isEmpty {
                historyCoordinator.updateTitleIfNeeded(title: title, url: visit.url)
                historyCoordinator.commitChanges(url: visit.url)
            }
            summary.imported += 1
        }
        return summary
    }

    private struct VisitKey: Hashable {
        let url: URL
        let date: Date
    }

    private struct HistoryExport: Decodable {
        let metadata: Metadata?
        let history: [Row]

        struct Metadata: Decodable {
            let dataType: String?

            enum CodingKeys: String, CodingKey {
                case dataType = "data_type"
            }
        }

        struct Row: Decodable {
            let url: String
            let title: String?
            let timeUsec: Double?
            let destinationURL: String?
            let latestVisitWasLoadFailure: Bool?

            enum CodingKeys: String, CodingKey {
                case url
                case title
                case timeUsec = "time_usec"
                case destinationURL = "destination_url"
                case latestVisitWasLoadFailure = "latest_visit_was_load_failure"
            }
        }
    }
}
