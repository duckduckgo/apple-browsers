//
//  SwitchToTabBrowserTool.swift
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
final class SwitchToTabBrowserTool: BrowserTool {

    let name = "switchToTab"
    let title = "Switch to tab"
    let description = "Switch to an open tab in the current window by tabId from listOpenTabs."
    let permissionMode = BrowserToolPermissionMode.auto

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string", "description": "Tab ID from listOpenTabs (GUID string)."]
        ],
        "required": ["tabId"]
    ]

    let outputSchema: JSONValue? = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string"],
            "title": ["type": "string"],
            "url": ["type": "string"]
        ],
        "required": ["tabId", "title", "url"]
    ]

    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: false,
                                                              destructiveHint: false,
                                                              idempotentHint: true,
                                                              openWorldHint: false)

    private let scopeProvider: BrowserToolScopeProvider

    init(scopeProvider: @escaping BrowserToolScopeProvider) {
        self.scopeProvider = scopeProvider
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard let scope = scopeProvider(context), scope.accepts(context) else { return .failure(.unavailable) }

        guard let targetTabID = arguments?["tabId"]?.stringValue, !targetTabID.isEmpty else {
            return .failure(.invalidArguments)
        }

        let tab: Tab
        switch scope.resolve(tabIDArgument: .string(targetTabID), context: context) {
        case .failure(let failure): return .failure(failure)
        case .resolved(let resolved): tab = resolved
        }
        guard tab.uid == targetTabID else { return .failure(.notFound) }
        guard scope.selectTab(tab), scope.contains(tab) else { return .failure(.unavailable) }

        return .success([
            "tabId": .string(targetTabID),
            "title": .string(tab.link?.displayTitle ?? ""),
            "url": .string(tab.link?.url.absoluteString ?? "")
        ])
    }
}
