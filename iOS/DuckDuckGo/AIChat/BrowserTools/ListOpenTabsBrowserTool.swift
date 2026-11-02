//
//  ListOpenTabsBrowserTool.swift
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
final class ListOpenTabsBrowserTool: BrowserTool {

    static let defaultLimit = 50
    static let maxLimit = 50

    let name = "listOpenTabs"
    let title = "List open tabs"
    let description = "List open tabs in the current window (title and URL only)."
    let permissionMode = BrowserToolPermissionMode.ask
    let permissionReason = "Duck.ai wants to see your open tabs."

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "limit": ["type": "integer", "minimum": 1, "maximum": 50]
        ]
    ]

    let outputSchema: JSONValue? = [
        "type": "object",
        "properties": [
            "tabs": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "tabId": ["type": "string"],
                        "title": ["type": "string"],
                        "url": ["type": "string"],
                        "isCurrentTab": ["type": "boolean"],
                        "isAttachable": ["type": "boolean"]
                    ],
                    "required": ["tabId", "title", "url", "isCurrentTab", "isAttachable"]
                ]
            ]
        ],
        "required": ["tabs"]
    ]

    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: true,
                                                              destructiveHint: false,
                                                              idempotentHint: true,
                                                              openWorldHint: false)

    private let scopeProvider: BrowserToolScopeProvider

    init(scopeProvider: @escaping BrowserToolScopeProvider) {
        self.scopeProvider = scopeProvider
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard let scope = scopeProvider(context), scope.accepts(context) else { return .failure(.unavailable) }

        switch arguments {
        case .none, .some(.null), .some(.object): break
        default: return .failure(.invalidArguments)
        }

        var limit = Self.defaultLimit
        if let limitValue = arguments?["limit"] {
            guard let parsed = limitValue.intValue else { return .failure(.invalidArguments) }
            limit = parsed
        }
        guard (1...Self.maxLimit).contains(limit) else { return .failure(.invalidArguments) }

        let selectedTabID = scope.selectedTabID()
        let pages: [JSONValue] = scope.tabs.compactMap { tab in
            guard let link = tab.link, !scope.isChatURL(link.url) else { return nil }
            return [
                "tabId": .string(tab.uid),
                "title": .string(link.displayTitle),
                "url": .string(link.url.absoluteString),
                "isCurrentTab": .bool(tab.uid == selectedTabID),
                "isAttachable": .bool(scope.isAttachableURL(link.url))
            ]
        }

        return .success(["tabs": .array(Array(pages.prefix(limit)))])
    }
}
