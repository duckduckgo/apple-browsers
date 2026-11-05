//
//  HighlightInPageBrowserTool.swift
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

/// Paints text on a page through WebKit's own find. Never prompts: it reveals nothing the user has
/// not already consented to through `findInPage` or `readTabContent`.
@MainActor
final class HighlightInPageBrowserTool: BrowserTool {

    static let maxQuotes = 20
    static let maxQuoteLength = 2000

    /// Matches `AIChatBrowserToolsSubfeature.highlightInPage`, which is how the catalog gates it.
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

    private let windowControllersManager: WindowControllersManagerProtocol
    private let highlighter: BrowserToolPageHighlighting

    init(windowControllersManager: WindowControllersManagerProtocol, highlighter: BrowserToolPageHighlighting) {
        self.windowControllersManager = windowControllersManager
        self.highlighter = highlighter
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        guard let quotes = Self.quotes(from: arguments) else { return .failure(.invalidArguments) }

        let tab: Tab
        let tabID: TabIdentifier
        switch BrowserToolTargetTab.resolve(tabIDArgument: arguments?["tabId"], context: context, in: windowControllersManager) {
        case .failure(let failure): return .failure(failure)
        case .resolved(let resolvedID, let collection):
            guard let resolvedTab = BrowserToolTargetTab.attachableTab(withID: resolvedID, in: collection) else {
                return .failure(.unavailable)
            }
            tab = resolvedTab
            tabID = resolvedID
        }

        // The overlay is shared with Cmd+F; a search the user is in the middle of is not ours to take.
        guard !highlighter.isFindBarVisible(in: tab) else { return .failure(.unavailable) }

        // WebKit finds one string, so the first quote with a hit is painted; the rest are reported
        // through `truncated`.
        var highlightedCount = 0
        var truncated = false
        for (position, quote) in quotes.enumerated() {
            switch await highlighter.highlight(quote, in: tab) {
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

        return .success([
            "tabId": .string(tabID),
            "title": .string(tab.title ?? ""),
            "url": .string(tab.content.userEditableUrl?.absoluteString ?? ""),
            "highlightedCount": .int(highlightedCount),
            "truncated": .bool(truncated)
        ])
    }

    /// The quotes to paint, or nil when any argument breaks the contract.
    private static func quotes(from arguments: JSONValue?) -> [String]? {
        guard case .some(.object) = arguments,
              // macOS never issues reliable match indexes, so receiving them means the flag was ignored.
              arguments?["matchIndexes"] == nil,
              arguments?["caseSensitive"].map({ $0.boolValue != nil }) ?? true,
              arguments?["query"].map({ isValidQuery($0) }) ?? true,
              let quoteValues = arguments?["quotes"]?.arrayValue,
              (1...maxQuotes).contains(quoteValues.count) else { return nil }
        let quotes = quoteValues.compactMap { value -> String? in
            guard let quote = value.stringValue,
                  !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  BrowserToolOutputLimits.fits(quote, within: maxQuoteLength) else { return nil }
            return quote
        }
        return quotes.count == quoteValues.count ? quotes : nil
    }

    private static func isValidQuery(_ value: JSONValue) -> Bool {
        guard let query = value.stringValue else { return false }
        return !query.isEmpty && BrowserToolOutputLimits.fits(query, within: BrowserToolOutputLimits.query)
    }

    func clientToolResult(from value: JSONValue) -> BrowserToolResult {
        guard var fields = value.objectValue else { return .failure(.unavailable) }
        fields["title"] = nil
        fields["url"] = nil
        return .success(.object(fields))
    }
}
