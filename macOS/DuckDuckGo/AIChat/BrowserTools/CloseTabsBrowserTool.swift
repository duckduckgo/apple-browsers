//
//  CloseTabsBrowserTool.swift
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
final class CloseTabsBrowserTool: BrowserTool {

    static let maxTabIDs = 50

    let name = "closeTabs"
    let permissionMode = BrowserToolPermissionMode.ask

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabIds": [
                "type": "array",
                "items": ["type": "string"],
                "description": "1 to 50 tab IDs from listOpenTabs. Never the chat's own tab: a call that names it closes nothing."
            ]
        ],
        "required": ["tabIds"]
    ]

    private let windowControllersManager: WindowControllersManagerProtocol

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        guard case .ids(let requestedIDs) = BrowserToolTargetTab.tabIDs(from: arguments, maxCount: Self.maxTabIDs) else {
            return .failure(.invalidArguments)
        }

        guard let token = context.ownerWindowToken,
              let collection = AIChatTabPickerSource.tabCollectionViewModel(forWindowToken: token, in: windowControllersManager) else {
            return .failure(.unavailable)
        }
        guard let tabs = BrowserToolTargetTab.actionableTabs(withIDs: requestedIDs, ownerTabID: context.ownerTabID, in: collection) else {
            return .failure(.notFound)
        }
        // Closing the chat's own tab would close the chat, so a call that names it closes nothing.
        guard !tabs.contains(where: { $0.uuid == context.ownerTabID }) else { return .failure(.unavailable) }

        return .success(["tabs": .array(tabs.map { tab in
            ["tabId": .string(tab.uuid), "closed": .bool(close(tab.uuid, in: collection))]
        })])
    }

    /// Pinned tabs stay open.
    private func close(_ tabID: TabIdentifier, in collection: TabCollectionViewModel) -> Bool {
        guard let index = collection.indexInAllTabs(where: { $0.uuid == tabID }), index.isUnpinnedTab else { return false }
        collection.close(at: index)
        return collection.indexInAllTabs(where: { $0.uuid == tabID }) == nil
    }
}
