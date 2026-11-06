//
//  PinTabBrowserTool.swift
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

/// Pins tabs in the window the chat belongs to, or the chat's own tab when no ids are given.
@MainActor
final class PinTabBrowserTool: BrowserTool {

    static let maxTabIDs = 50

    /// Matches `AIChatBrowserToolsSubfeature.pinTab`, which is how the catalog gates it.
    let name = "pinTab"
    let permissionMode = BrowserToolPermissionMode.auto

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabIds": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Optional. 1 to 50 tab IDs from listOpenTabs. Omit to pin the current tab."
            ]
        ]
    ]

    private let windowControllersManager: WindowControllersManagerProtocol

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        let requestedIDs: [TabIdentifier]?
        switch BrowserToolTargetTab.tabIDs(from: arguments, maxCount: Self.maxTabIDs) {
        case .absent: requestedIDs = nil
        case .ids(let ids): requestedIDs = ids
        case .invalid: return .failure(.invalidArguments)
        }

        guard let token = context.ownerWindowToken,
              let collection = AIChatTabPickerSource.tabCollectionViewModel(forWindowToken: token, in: windowControllersManager) else {
            return .failure(.unavailable)
        }
        guard let tabs = BrowserToolTargetTab.actionableTabs(withIDs: requestedIDs, ownerTabID: context.ownerTabID, in: collection) else {
            return .failure(.notFound)
        }

        let selectedTab = collection.selectedTabViewModel?.tab
        let results: [JSONValue] = tabs.map { tab in
            ["tabId": .string(tab.uuid), "pinned": .bool(pin(tab.uuid, in: collection))]
        }
        // `pinTab(at:)` selects each tab it pins; keep the user on the tab they were looking at.
        if let selectedTab, let index = collection.indexInAllTabs(of: selectedTab) {
            collection.select(at: index)
        }
        return .success(["tabs": .array(results)])
    }

    /// Whether the tab ends up pinned. Only web pages can be pinned, as on other platforms.
    private func pin(_ tabID: TabIdentifier, in collection: TabCollectionViewModel) -> Bool {
        switch collection.indexInAllTabs(where: { $0.uuid == tabID }) {
        case .pinned: return true
        case .unpinned(let item):
            let content = collection.tabCollection.tabs[item].content
            guard collection.pinnedTabsCollection != nil, content.canBePinned, content.urlForWebView?.isHttpOrHttps == true else { return false }
            collection.pinTab(at: item)
            return collection.indexInAllTabs(where: { $0.uuid == tabID })?.isPinnedTab == true
        case .none: return false
        }
    }
}
