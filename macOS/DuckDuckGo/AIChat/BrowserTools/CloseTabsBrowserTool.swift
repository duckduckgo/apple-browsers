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
    let permissionReason = "It will close tabs in this window. Pinned tabs stay open."

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabIds": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Optional. 1 to 50 tab IDs from listOpenTabs. Omit to close the current tab."
            ]
        ]
    ]

    private let windowControllersManager: WindowControllersManagerProtocol
    private let afterReply: (@escaping @MainActor () -> Void) -> Void

    init(windowControllersManager: WindowControllersManagerProtocol,
         afterReply: @escaping (@escaping @MainActor () -> Void) -> Void = { work in DispatchQueue.main.asyncAfter(deadline: .now() + 1) { work() } }) {
        self.windowControllersManager = windowControllersManager
        self.afterReply = afterReply
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

        return .success(["tabs": .array(tabs.map { tab in
            ["tabId": .string(tab.uuid), "closed": .bool(close(tab.uuid, in: collection, ownerTabID: context.ownerTabID))]
        })])
    }

    /// Closing the chat's own tab closes the chat too, so it happens after the reply is sent.
    private func close(_ tabID: TabIdentifier, in collection: TabCollectionViewModel, ownerTabID: TabIdentifier) -> Bool {
        guard case .unpinned = collection.indexInAllTabs(where: { $0.uuid == tabID }) else { return false }
        guard tabID == ownerTabID else {
            Self.closeTab(withID: tabID, in: collection)
            return collection.indexInAllTabs(where: { $0.uuid == tabID }) == nil
        }
        afterReply { [weak collection] in
            guard let collection else { return }
            Self.closeTab(withID: tabID, in: collection)
        }
        return true
    }

    private static func closeTab(withID tabID: TabIdentifier, in collection: TabCollectionViewModel) {
        guard let index = collection.indexInAllTabs(where: { $0.uuid == tabID }), index.isUnpinnedTab else { return }
        collection.close(at: index)
    }
}
