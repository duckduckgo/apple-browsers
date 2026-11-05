//
//  SafariHistoryReader.swift
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
import History

protocol SafariHistoryReaderProtocol {
    func readVisits(fromHistoryJSON historyJSON: Data, since cutoff: Date) -> DataImportResult<HistoryImport.ParseResult>
}

/// Reads the `History.json` file of Safari's "Export Browsing Data" archive.
///
/// Safari exports one row per URL with the time of its latest visit, so each row becomes a single visit.
final class SafariHistoryReader: SafariHistoryReaderProtocol {
    struct ImportError: DataImportError {
        enum OperationType: Int {
            case decodeHistory
            case importVisits
        }

        var action: DataImportAction { .history }
        let type: OperationType
        let underlyingError: Error?

        var errorType: DataImport.ErrorType {
            switch type {
            case .decodeHistory: .dataCorrupted
            case .importVisits: .other
            }
        }
    }

    private struct HistoryExport: Decodable {
        let history: [HistoryEntry]
    }

    /// Decodes a damaged row as `nil` instead of failing the whole file.
    private struct HistoryEntry: Decodable {
        let row: Row?

        init(from decoder: Decoder) throws {
            row = try? Row(from: decoder)
        }
    }

    private struct Row: Decodable {
        enum CodingKeys: String, CodingKey {
            case url
            case title
            case timeUsec = "time_usec"
            case destinationURL = "destination_url"
            case latestVisitWasLoadFailure = "latest_visit_was_load_failure"
        }

        let url: String
        let title: String?
        let timeUsec: Double
        let destinationURL: String?
        let latestVisitWasLoadFailure: Bool?
    }

    func readVisits(fromHistoryJSON historyJSON: Data, since cutoff: Date) -> DataImportResult<HistoryImport.ParseResult> {
        let export: HistoryExport
        do {
            export = try JSONDecoder().decode(HistoryExport.self, from: historyJSON)
        } catch {
            return .failure(ImportError(type: .decodeHistory, underlyingError: error))
        }

        var visits = [HistoryImport.Visit]()
        var skipped = 0
        for entry in export.history {
            guard let row = entry.row, let visit = visit(from: row) else {
                skipped += 1
                continue
            }
            guard visit.date >= cutoff else { continue }
            visits.append(visit)
        }
        return .success(HistoryImport.ParseResult(visits: visits, skipped: skipped))
    }

    // MARK: - Private

    private func visit(from row: Row) -> HistoryImport.Visit? {
        // A row with a destination is a redirect hop, and a failed load isn't a page the user saw.
        guard row.destinationURL == nil,
              row.latestVisitWasLoadFailure != true,
              let url = URL(string: row.url),
              url.isHttp || url.isHttps else {
            return nil
        }

        return HistoryImport.Visit(url: url, title: row.title, date: date(fromMicroseconds: row.timeUsec))
    }

    private func date(fromMicroseconds microseconds: Double) -> Date {
        Date(timeIntervalSince1970: microseconds / 1_000_000)
    }
}
