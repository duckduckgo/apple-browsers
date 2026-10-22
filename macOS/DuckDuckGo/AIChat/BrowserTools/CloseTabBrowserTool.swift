//
//  CloseTabBrowserTool.swift
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

/// Closes a tab this chat opened with `openTab`. Never prompts, because it cannot reach any other tab.
@MainActor
final class CloseTabBrowserTool: BrowserTool {

    /// Matches `AIChatBrowserToolsSubfeature.closeTab`, which is how the catalog gates it.
    let name = "closeTab"
    let title = "Close tab"
    let description = "Close a tab that openTab opened. Other tabs cannot be closed."
    let permissionMode = BrowserToolPermissionMode.auto

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string", "description": "A tabId returned by openTab."]
        ],
        "required": ["tabId"]
    ]

    let outputSchema: JSONValue? = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string"],
            "closed": ["type": "boolean"]
        ],
        "required": ["tabId", "closed"]
    ]

    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: false,
                                                              destructiveHint: false,
                                                              idempotentHint: true,
                                                              openWorldHint: false)

    private let windowControllersManager: WindowControllersManagerProtocol
    private let openedTabs: BrowserToolOpenedTabs

    init(windowControllersManager: WindowControllersManagerProtocol, openedTabs: BrowserToolOpenedTabs) {
        self.windowControllersManager = windowControllersManager
        self.openedTabs = openedTabs
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        guard let tabID = arguments?["tabId"]?.stringValue?.trimmingCharacters(in: .whitespaces), !tabID.isEmpty else {
            return .failure(.invalidArguments)
        }

        // The user's tabs and other chats' tabs answer exactly like tabs that do not exist.
        guard openedTabs.contains(tabID, ownerTabID: context.ownerTabID) else { return .failure(.notFound) }

        openedTabs.remove(tabID)
        guard BrowserToolTargetTab.closeUnpinnedTab(withID: tabID, in: windowControllersManager) else {
            return .failure(.notFound)
        }
        return .success([
            "tabId": .string(tabID),
            "closed": true
        ])
    }
}
