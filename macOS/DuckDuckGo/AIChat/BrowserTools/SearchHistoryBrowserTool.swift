//
//  SearchHistoryBrowserTool.swift
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

import AIChat
import Foundation
import History

/// Searches local history by title and URL. Asks first: history is browsing data.
@MainActor
final class SearchHistoryBrowserTool: BrowserTool {

    static let defaultLimit = 10
    static let maxLimit = 50

    /// Matches `AIChatBrowserToolsSubfeature.searchHistory`, which is how the catalog gates it.
    let name = "searchHistory"
    let title = "Search history"
    let description = "Search local browser history by term (omit query for most recent visits). Optionally narrow with inclusive startDate/endDate (YYYY-MM-DD or ISO-8601). Each result has title, url, and visitedAt (ISO-8601 UTC); prefer title for display when it is non-empty."
    let permissionMode = BrowserToolPermissionMode.ask
    let permissionReason = "Duck.ai wants to search your browsing history."

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "query": [
                "type": "string",
                "description": "Search term matched against history titles and URLs (case-insensitive). Omit or leave empty to return the most recent visits."
            ],
            "startDate": [
                "type": "string",
                "description": "Inclusive range start as YYYY-MM-DD or ISO-8601 datetime. Date-only is treated as 00:00:00 UTC."
            ],
            "endDate": [
                "type": "string",
                "description": "Inclusive range end as YYYY-MM-DD or ISO-8601 datetime. Date-only is treated as 23:59:59.9999999 UTC."
            ],
            "limit": [
                "type": "integer",
                "minimum": 1,
                "maximum": 50,
                "description": "Maximum number of results to return (default 10)."
            ]
        ]
    ]

    let outputSchema: JSONValue? = [
        "type": "object",
        "properties": [
            "results": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "url": ["type": "string"],
                        "visitedAt": ["type": "string"]
                    ],
                    "required": ["title", "url", "visitedAt"]
                ]
            ]
        ],
        "required": ["results"]
    ]

    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: true,
                                                              destructiveHint: false,
                                                              idempotentHint: true,
                                                              openWorldHint: false)

    private let historyCoordinator: HistoryCoordinating

    init(historyCoordinator: HistoryCoordinating) {
        self.historyCoordinator = historyCoordinator
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }

        switch arguments {
        case .none, .some(.null), .some(.object): break
        default: return .failure(.invalidArguments)
        }

        var query: String?
        switch arguments?["query"] {
        case .none, .some(.null): break
        case .some(.string(let value)): query = value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
        default: return .failure(.invalidArguments)
        }

        var limit = Self.defaultLimit
        if let limitValue = arguments?["limit"] {
            guard let parsed = limitValue.intValue, (1...Self.maxLimit).contains(parsed) else { return .failure(.invalidArguments) }
            limit = parsed
        }

        guard case .some(let start) = Self.dateBound(from: arguments?["startDate"], isEnd: false),
              case .some(let end) = Self.dateBound(from: arguments?["endDate"], isEnd: true) else {
            return .failure(.invalidArguments)
        }
        if let start, let end, start > end { return .failure(.invalidArguments) }

        let results = Self.search(visits: historyCoordinator.allHistoryVisits ?? [], query: query, start: start, end: end, limit: limit)
        return .success(["results": .array(results.map { result in
            [
                "title": .string(result.title),
                "url": .string(result.url),
                "visitedAt": .string(Self.isoFormatter.string(from: result.visitedAt))
            ]
        })])
    }

    // MARK: - Search

    struct Result: Equatable {
        let title: String
        let url: String
        let visitedAt: Date
    }

    /// Newest first, one row per visit, filtered by term and inclusive date range.
    static func search(visits: [Visit], query: String?, start: Date?, end: Date?, limit: Int) -> [Result] {
        let term = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        return visits
            .lazy
            .filter { visit in
                if let start, visit.date < start { return false }
                if let end, visit.date > end { return false }
                return true
            }
            .compactMap { visit -> (Visit, HistoryEntry)? in
                guard let entry = visit.historyEntry else { return nil }
                return (visit, entry)
            }
            .filter { _, entry in
                guard let term, !term.isEmpty else { return true }
                return (entry.title ?? "").range(of: term, options: .caseInsensitive) != nil
                    || entry.url.absoluteString.range(of: term, options: .caseInsensitive) != nil
            }
            .sorted { $0.0.date > $1.0.date }
            .prefix(limit)
            .map { visit, entry in
                Result(title: displayTitle(title: entry.title, url: entry.url), url: entry.url.absoluteString, visitedAt: visit.date)
            }
    }

    /// A blank title falls back to host, plus path unless it is just "/".
    static func displayTitle(title: String?, url: URL) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        let host = url.host ?? ""
        let path = url.path
        return path.isEmpty || path == "/" ? host : host + path
    }

    // MARK: - Dates

    /// `.some(nil)` is "no bound"; `nil` is unparseable. Date-only values are whole UTC days.
    static func dateBound(from value: JSONValue?, isEnd: Bool) -> Date?? {
        switch value {
        case .none, .some(.null):
            return .some(nil)
        case .some(.string(let raw)):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return .some(nil) }
            if let day = dayFormatter.date(from: trimmed) {
                return .some(isEnd ? day.addingTimeInterval(24 * 60 * 60 - 0.001) : day)
            }
            if let instant = isoFormatter.date(from: trimmed) ?? isoFormatterWithoutFraction.date(from: trimmed) {
                return .some(instant)
            }
            return nil
        default:
            return nil
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterWithoutFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
