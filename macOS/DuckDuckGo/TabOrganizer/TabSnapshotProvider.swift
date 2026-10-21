//
//  TabSnapshotProvider.swift
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
import AppKit
import Foundation

/// Same tab rules as `ListOpenTabsBrowserTool`: pinned and normal tabs with a URL, never Duck.ai itself.
@MainActor
enum TabSnapshotProvider {

    static let maxPathLength = 60

    static func snapshots(in collection: TabCollectionViewModel) -> [TabSnapshot] {
        let pinnedTabs = collection.pinnedTabsCollection?.tabs ?? []
        let pinnedIDs = Set(pinnedTabs.map(\.uuid))
        let selectedTabID = collection.selectedTabViewModel?.tab.uuid

        return (pinnedTabs + collection.tabCollection.tabs).compactMap { tab in
            guard case .url(let url, _, _) = tab.content, !url.isDuckAIURL else { return nil }
            return TabSnapshot(id: tab.uuid,
                               title: tab.title ?? url.host ?? "",
                               host: url.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? "",
                               path: String(url.path.prefix(maxPathLength)),
                               isPinned: pinnedIDs.contains(tab.uuid),
                               isCurrent: tab.uuid == selectedTabID,
                               lastSelectedAt: tab.lastSelectedAt)
        }
    }

    /// Adds page type and the first `excerptLength` characters of each page, using the same
    /// extraction as the tab content attachment. Loads tabs that were never loaded.
    static func addingContent(to snapshots: [TabSnapshot],
                              in collection: TabCollectionViewModel,
                              excerptLength: Int,
                              windowControllersManager: WindowControllersManagerProtocol = NSApp.delegateTyped.windowControllersManager) async -> [TabSnapshot] {
        guard excerptLength > 0 else { return snapshots }
        var result = snapshots
        for index in result.indices {
            guard let context = await AIChatUserScriptHandler.extractPageContext(forTabId: result[index].id,
                                                                                 origin: collection,
                                                                                 in: windowControllersManager) else { continue }
            let signals = context.pageTypeSignals
            result[index].pageType = signals?.ogType ?? signals?.jsonLdType.first
            let excerpt = context.content
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            result[index].excerpt = excerpt.isEmpty ? nil : String(excerpt.prefix(excerptLength))
        }
        return result
    }
}
