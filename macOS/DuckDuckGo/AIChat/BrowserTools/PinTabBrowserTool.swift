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
                "description": "Optional. Tab IDs from listOpenTabs. Omit or leave empty to pin the current tab."
            ]
        ]
    ]

    private let windowControllersManager: WindowControllersManagerProtocol

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        guard let requestedIDs = Self.tabIDs(from: arguments) else { return .failure(.invalidArguments) }
        let tabIDs = requestedIDs.isEmpty ? [context.ownerTabID] : requestedIDs

        guard let token = context.ownerWindowToken,
              let collection = AIChatTabPickerSource.tabCollectionViewModel(forWindowToken: token, in: windowControllersManager),
              collection.pinnedTabsCollection != nil else {
            return .failure(.unavailable)
        }

        // Checked before pinning anything, so one bad id leaves every tab as it was.
        for tabID in tabIDs {
            guard let index = collection.indexInAllTabs(where: { $0.uuid == tabID }) else { return .failure(.notFound) }
            if case .unpinned(let item) = index, !collection.tabCollection.tabs[item].content.canBePinned {
                return .failure(.unavailable)
            }
        }

        let selectedTab = collection.selectedTabViewModel?.tab
        for tabID in tabIDs {
            guard case .unpinned(let item) = collection.indexInAllTabs(where: { $0.uuid == tabID }) else { continue }
            collection.pinTab(at: item)
        }
        // `pinTab(at:)` selects each tab it pins; keep the user on the tab they were looking at.
        if let selectedTab, let index = collection.indexInAllTabs(of: selectedTab) {
            collection.select(at: index)
        }

        guard tabIDs.allSatisfy({ tabID in collection.indexInAllTabs(where: { $0.uuid == tabID })?.isPinnedTab == true }) else {
            return .failure(.unavailable)
        }
        return .success(["tabs": .array(tabIDs.map { ["tabId": .string($0), "pinned": true] })])
    }

    /// The requested ids in order without duplicates, empty when omitted, or nil when malformed.
    private static func tabIDs(from arguments: JSONValue?) -> [TabIdentifier]? {
        guard let value = arguments?["tabIds"], value != .null else { return [] }
        guard let values = value.arrayValue, values.count <= maxTabIDs else { return nil }
        var tabIDs: [TabIdentifier] = []
        for value in values {
            guard let tabID = value.stringValue?.trimmingCharacters(in: .whitespaces), !tabID.isEmpty else { return nil }
            if !tabIDs.contains(tabID) { tabIDs.append(tabID) }
        }
        return tabIDs
    }
}
