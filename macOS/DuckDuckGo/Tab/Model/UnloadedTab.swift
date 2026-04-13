//
//  UnloadedTab.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppKit
import Foundation

/// Lightweight data-only representation of a tab that has not yet been materialized into a full `Tab`.
///
/// Created during state restoration for non-selected tabs. Stores only the display and
/// serialization data needed to render the tab bar item and re-encode the session.
/// When the user selects this tab (or the lazy loader reaches it), it is materialized
/// into a full `Tab` via ``materialize()``.
final class UnloadedTab: Identifiable {

    let uuid: TabIdentifier
    var id: TabIdentifier { uuid }
    var content: Tab.TabContent
    var title: String?
    var favicon: NSImage?
    var lastSelectedAt: Date?
    let burnerMode: BurnerMode
    let isPersistent: Bool
    let interactionStateData: Data?
    var isSuspended: Bool

    /// Pass-through from HistoryTabExtension — preserved so re-encoding doesn't lose extension state.
    var localHistoryIDs: [URL]?
    /// Pass-through from TabSnapshotExtension.
    let tabSnapshotIdentifier: String?

    init(uuid: TabIdentifier = UUID().uuidString,
         content: Tab.TabContent,
         title: String? = nil,
         favicon: NSImage? = nil,
         lastSelectedAt: Date? = nil,
         burnerMode: BurnerMode = .regular,
         interactionStateData: Data? = nil,
         localHistoryIDs: [URL]? = nil,
         tabSnapshotIdentifier: String? = nil,
         isSuspended: Bool = false) {
        self.uuid = uuid
        self.content = content
        self.title = title
        self.favicon = favicon
        self.lastSelectedAt = lastSelectedAt
        self.burnerMode = burnerMode
        self.isPersistent = !burnerMode.isBurner
        self.interactionStateData = interactionStateData
        self.localHistoryIDs = localHistoryIDs
        self.tabSnapshotIdentifier = tabSnapshotIdentifier
        self.isSuspended = isSuspended
    }

    init(from data: TabRestorationData) {
        self.uuid = data.uuid ?? UUID().uuidString
        self.content = data.content
        self.title = data.title
        self.favicon = data.favicon
        self.interactionStateData = data.interactionStateData
        self.lastSelectedAt = data.lastSelectedAt
        self.burnerMode = .regular  // Burner tabs are never persisted
        self.isPersistent = true    // Restored tabs always come from persistent storage
        self.localHistoryIDs = data.localHistoryIDs
        self.tabSnapshotIdentifier = data.tabSnapshotIdentifier
        self.isSuspended = false
    }

    func clearNavigationHistory(keepingCurrent: Bool) {
        if keepingCurrent, let currentHost = content.urlForWebView?.host {
            localHistoryIDs = localHistoryIDs?.filter { $0.host == currentHost }
        } else {
            localHistoryIDs = nil
        }
    }

    /// Creates a full `Tab` from this unloaded tab's stored data.
    ///
    /// The `Tab` convenience init resolves all other dependencies (privacy features,
    /// favicon management, etc.) from `AppDelegate` defaults.
    @MainActor
    func materialize(extensionsBuilder: TabExtensionsBuilderProtocol = TabExtensionsBuilder.default) -> Tab {
        let tab = Tab(uuid: uuid,
                      content: content,
                      extensionsBuilder: extensionsBuilder,
                      title: title,
                      favicon: favicon,
                      interactionStateData: interactionStateData,
                      burnerMode: burnerMode,
                      lastSelectedAt: lastSelectedAt)

        if let localHistoryIDs {
            tab.history?.restoreLocalHistoryIDs(localHistoryIDs)
        }
        if let snapshotIdString = tabSnapshotIdentifier,
           let snapshotId = UUID(uuidString: snapshotIdString) {
            tab.tabSnapshots?.setIdentifier(snapshotId)
        }

        if isSuspended {
            tab.tabSuspension?.lastSuspendedURL = content.urlForWebView
        }

        return tab
    }
}

// MARK: - Hashable (identity-based)

extension UnloadedTab: Hashable {
    static func == (lhs: UnloadedTab, rhs: UnloadedTab) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
