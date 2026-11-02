//
//  HighlightInPageBrowserTool.swift
//  DuckDuckGo
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

@MainActor
final class HighlightInPageBrowserTool: BrowserTool {

    let name = "highlightInPage"
    let title = "Highlight in page"
    let description = "Highlight text ranges on the current page."
    let permissionMode = BrowserToolPermissionMode.auto

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": [
                "type": "string",
                "description": "Optional. Omit for the same tab as a prior findInPage on 'this/current page'."
            ],
            "query": [
                "type": "string",
                "description": "Required with matchIndexes: the same query used in findInPage."
            ],
            "matchIndexes": [
                "type": "array",
                "items": ["type": "integer", "minimum": 0],
                "description": "0-based matchIndex values from findInPage to paint. Only use when findInPage returned matchIndexesReliable=true. Prefer this after filtering snippets."
            ],
            "caseSensitive": [
                "type": "boolean",
                "description": "Must match the findInPage caseSensitive used with matchIndexes. Default false."
            ],
            "quotes": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Exact page substrings to paint (case-sensitive). Required when findInPage returned matchIndexesReliable=false, or when you have concrete quotes rather than findInPage indexes. Provide matchIndexes or quotes, not both."
            ]
        ]
    ]

    let outputSchema: JSONValue? = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string"],
            "title": ["type": "string"],
            "url": ["type": "string"],
            "highlightedCount": ["type": "integer"],
            "truncated": ["type": "boolean"]
        ],
        "required": ["tabId", "title", "url", "highlightedCount", "truncated"]
    ]

    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: false,
                                                              destructiveHint: false,
                                                              idempotentHint: true,
                                                              openWorldHint: false)

    private let scopeProvider: BrowserToolScopeProvider
    private let highlighter: BrowserToolPageHighlighting

    init(scopeProvider: @escaping BrowserToolScopeProvider, highlighter: BrowserToolPageHighlighting) {
        self.scopeProvider = scopeProvider
        self.highlighter = highlighter
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard let scope = scopeProvider(context), scope.accepts(context) else { return .failure(.unavailable) }
        guard case .some(.object) = arguments else { return .failure(.invalidArguments) }

        if let indexes = arguments?["matchIndexes"]?.arrayValue, !indexes.isEmpty {
            return .failure(.invalidArguments)
        }
        guard let quotes = Self.quotes(from: arguments?["quotes"]) else { return .failure(.invalidArguments) }

        let tab: Tab
        switch scope.resolve(tabIDArgument: arguments?["tabId"], context: context) {
        case .failure(let failure): return .failure(failure)
        case .resolved(let resolved): tab = resolved
        }
        guard let lease = BrowserToolPageLease(scope: scope, tab: tab) else { return .failure(.unavailable) }
        defer { lease.release() }
        guard let ready = await lease.ready() else { return .failure(.unavailable) }
        let tabID = tab.uid
        let identity = ready.identity

        guard !highlighter.isFindBarVisible(in: tab, scope: scope) else { return .failure(.unavailable) }

        // WebKit finds one string, so the first quote with a hit is painted; the rest are reported
        // through `truncated`.
        var highlightedCount = 0
        var truncated = false
        for (position, quote) in quotes.enumerated() {
            switch await highlighter.highlight(quote, in: tab, scope: scope) {
            case .notFound:
                continue
            case .cancelled:
                return .failure(.unavailable)
            case .painted(let count):
                highlightedCount = Int(count ?? 1)
                truncated = count == nil || position < quotes.count - 1
            }
            break
        }

        guard scope.accepts(context), scope.contains(tab), !Task.isCancelled,
              lease.isValid(), let current = lease.page.state(), current.identity == identity,
              !current.isLoading, !current.hasTerminatedProcess else { return .failure(.unavailable) }
        return .success([
            "tabId": .string(tabID),
            "title": .string(tab.link?.displayTitle ?? ""),
            "url": .string(tab.link?.url.absoluteString ?? ""),
            "highlightedCount": .int(highlightedCount),
            "truncated": .bool(truncated)
        ])
    }

    private static func quotes(from value: JSONValue?) -> [String]? {
        guard let values = value?.arrayValue, !values.isEmpty else { return nil }
        var quotes: [String] = []
        for value in values {
            guard let quote = value.stringValue, !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            quotes.append(quote)
        }
        return quotes
    }

}
