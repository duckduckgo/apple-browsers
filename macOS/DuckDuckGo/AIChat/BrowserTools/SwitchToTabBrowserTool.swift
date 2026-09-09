//
//  SwitchToTabBrowserTool.swift
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

/// Switches to another tab in the window the chat belongs to.
///
/// `auto`, so it never prompts: it exposes nothing the user cannot already see, and only moves the
/// selection they are looking at. `readOnlyHint` is still false because it does mutate UI state.
@MainActor
final class SwitchToTabBrowserTool: BrowserTool {

    /// Matches `AIChatBrowserToolsSubfeature.switchToTab`, which is how the catalog gates it.
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

    private let windowControllersManager: WindowControllersManagerProtocol

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        // Belt and braces behind the invoker's own check, so calling a tool directly cannot skip it.
        guard !context.isBurner else { return .failure(.unavailable) }

        guard let targetTabID = arguments?["tabId"]?.stringValue, !targetTabID.isEmpty else {
            return .failure(.invalidArguments)
        }

        // Scoped to the window the chat lives in, mirroring the tool's own description. A tab in
        // another window is reported as missing rather than switched to, so a chat cannot move the
        // user's attention to a window they were not working in.
        guard let ownerCollection = AIChatTabPickerSource.tabCollectionViewModel(containingTabWithID: context.ownerTabID,
                                                                                in: windowControllersManager),
              ownerCollection.indexInAllTabs(where: { $0.uuid == targetTabID }) != nil else {
            return .failure(.notFound)
        }

        guard let tab = windowControllersManager.focusTab(byUUID: targetTabID) else {
            return .failure(.notFound)
        }

        return .success([
            "tabId": .string(targetTabID),
            "title": .string(tab.title ?? ""),
            "url": .string(tab.content.userEditableUrl?.absoluteString ?? "")
        ])
    }
}
