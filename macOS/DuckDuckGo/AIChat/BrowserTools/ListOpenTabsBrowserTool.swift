//
//  ListOpenTabsBrowserTool.swift
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

/// Lists the tabs of the window the chat belongs to. Asks first: titles and URLs are browsing data
/// the page has no other way to see.
@MainActor
final class ListOpenTabsBrowserTool: BrowserTool {

    static let defaultLimit = 50
    static let maxLimit = 50

    /// Matches `AIChatBrowserToolsSubfeature.listOpenTabs`, which is how the catalog gates it.
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

    private let windowControllersManager: WindowControllersManagerProtocol

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }

        var limit = Self.defaultLimit
        if let limitValue = arguments?["limit"] {
            guard let parsed = limitValue.intValue else { return .failure(.invalidArguments) }
            limit = parsed
        }
        guard (1...Self.maxLimit).contains(limit) else { return .failure(.invalidArguments) }

        guard let token = context.ownerWindowToken,
              let collection = AIChatTabPickerSource.tabCollectionViewModel(forWindowToken: token,
                                                                           in: windowControllersManager) else {
            return .failure(.unavailable)
        }

        let tabs = (collection.pinnedTabsCollection?.tabs ?? []) + collection.tabCollection.tabs
        // The window's selection, not the chat's owner: a sidebar's host tab may be backgrounded.
        let selectedTabID = collection.selectedTabViewModel?.tab.uuid
        // Only pages with a URL are listed, and never Duck.ai itself.
        let pages: [JSONValue] = tabs.compactMap { tab in
            guard case .url(let url, _, _) = tab.content, !url.isDuckAIURL else { return nil }
            return [
                "tabId": .string(tab.uuid),
                "title": .string(tab.title ?? url.host ?? ""),
                "url": .string(url.absoluteString),
                "isCurrentTab": .bool(tab.uuid == selectedTabID),
                "isAttachable": .bool(!AIChatTabMetadata.shouldExcludeFromTabPicker(url))
            ]
        }

        return .success(["tabs": .array(Array(pages.prefix(limit)))])
    }
}
