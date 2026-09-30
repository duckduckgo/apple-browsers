//
//  FindInPageBrowserTool.swift
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

/// Finds text in a tab's extracted page text. There is no DOM search on macOS, so match indexes
/// are never reliable and the front end must highlight by `quotes`.
@MainActor
final class FindInPageBrowserTool: BrowserTool {

    static let defaultMaxMatches = 10
    static let maxMaxMatches = 50

    /// Matches `AIChatBrowserToolsSubfeature.findInPage`, which is how the catalog gates it.
    let name = "findInPage"
    let title = "Find in page"
    let description = "Find text in the current page and report match count and current match index."
    let permissionMode = BrowserToolPermissionMode.ask
    let permissionReason = "Duck.ai wants to find text on this page."

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "query": [
                "type": "string",
                "description": "Exact text to find (e.g. performance). Required."
            ],
            "tabId": [
                "type": "string",
                "description": "Optional. Omit for 'this/current/this page' (sidebar host). Only pass a GUID from listOpenTabs when the user names another tab, or after omit-tabId returned unavailable."
            ],
            "caseSensitive": [
                "type": "boolean",
                "description": "When true, match case exactly. Default false."
            ],
            "maxMatches": [
                "type": "integer",
                "minimum": 1,
                "maximum": 50,
                "description": "Maximum number of snippets to return (default 10). matchCount still reports the total."
            ]
        ],
        "required": ["query"]
    ]

    let outputSchema: JSONValue? = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string"],
            "title": ["type": "string"],
            "url": ["type": "string"],
            "query": ["type": "string"],
            "matchCount": ["type": "integer"],
            "matches": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "snippet": ["type": "string"],
                        "matchIndex": ["type": "integer"]
                    ],
                    "required": ["snippet", "matchIndex"]
                ]
            ],
            "truncated": ["type": "boolean"],
            "contentTruncated": ["type": "boolean"],
            "matchIndexesReliable": [
                "type": "boolean",
                "description": "When false, matchIndex values are from page-context text fallback and must not be passed to highlightInPage — use quotes instead."
            ]
        ],
        "required": ["tabId", "title", "url", "query", "matchCount", "matches", "truncated", "contentTruncated", "matchIndexesReliable"]
    ]

    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: true,
                                                              destructiveHint: false,
                                                              idempotentHint: true,
                                                              openWorldHint: false)

    private let windowControllersManager: WindowControllersManagerProtocol
    private let reader: BrowserToolPageContentReading

    init(windowControllersManager: WindowControllersManagerProtocol, reader: BrowserToolPageContentReading) {
        self.windowControllersManager = windowControllersManager
        self.reader = reader
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }

        guard case .some(.object) = arguments,
              let query = arguments?["query"]?.stringValue,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidArguments)
        }

        var caseSensitive = false
        if let value = arguments?["caseSensitive"] {
            guard let flag = value.boolValue else { return .failure(.invalidArguments) }
            caseSensitive = flag
        }

        var maxMatches = Self.defaultMaxMatches
        if let value = arguments?["maxMatches"] {
            guard let parsed = value.intValue, (1...Self.maxMaxMatches).contains(parsed) else { return .failure(.invalidArguments) }
            maxMatches = parsed
        }

        let tabID: TabIdentifier
        let collection: TabCollectionViewModel
        switch BrowserToolTargetTab.resolve(tabIDArgument: arguments?["tabId"], context: context, in: windowControllersManager) {
        case .failure(let failure): return .failure(failure)
        case .resolved(let resolvedID, let resolvedCollection):
            tabID = resolvedID
            collection = resolvedCollection
        }

        guard let pageContext = await reader.pageContext(forTabID: tabID, in: collection) else {
            return .failure(.unavailable)
        }

        let found = Self.search(content: pageContext.content, query: query, caseSensitive: caseSensitive, maxMatches: maxMatches)
        return .success([
            "tabId": .string(tabID),
            "title": .string(pageContext.title),
            "url": .string(pageContext.url),
            "query": .string(query),
            "matchCount": .int(found.matchCount),
            "matches": .array(found.matches.map { ["snippet": .string($0.snippet), "matchIndex": .int($0.matchIndex)] }),
            "truncated": .bool(found.matchCount > found.matches.count),
            "contentTruncated": .bool(pageContext.truncated),
            "matchIndexesReliable": .bool(false)
        ])
    }

    // MARK: - Text search

    static let snippetRadius = 40

    struct Match: Equatable {
        let snippet: String
        let matchIndex: Int
    }

    /// Non-overlapping ordinal scan. `matchIndex` counts hits in order; only the first `maxMatches`
    /// get a snippet, but `matchCount` is the total.
    static func search(content: String, query: String, caseSensitive: Bool, maxMatches: Int) -> (matchCount: Int, matches: [Match]) {
        guard !content.isEmpty, !query.isEmpty else { return (0, []) }
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var matches: [Match] = []
        var matchCount = 0
        var searchStart = content.startIndex
        while searchStart < content.endIndex,
              let range = content.range(of: query, options: options, range: searchStart..<content.endIndex) {
            if matches.count < maxMatches {
                matches.append(Match(snippet: snippet(in: content, around: range), matchIndex: matchCount))
            }
            matchCount += 1
            searchStart = range.upperBound
        }
        return (matchCount, matches)
    }

    static func snippet(in content: String, around range: Range<String.Index>) -> String {
        let start = content.index(range.lowerBound, offsetBy: -snippetRadius, limitedBy: content.startIndex) ?? content.startIndex
        let end = content.index(range.upperBound, offsetBy: snippetRadius, limitedBy: content.endIndex) ?? content.endIndex
        return content[start..<end]
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
