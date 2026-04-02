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
    let interactionStateData: Data?

    /// Pass-through from HistoryTabExtension — preserved so re-encoding doesn't lose extension state.
    let visitedDomainURLs: [URL]?
    /// Pass-through from TabSnapshotExtension.
    let tabSnapshotIdentifier: String?

    init(uuid: TabIdentifier = UUID().uuidString,
         content: Tab.TabContent,
         title: String? = nil,
         favicon: NSImage? = nil,
         lastSelectedAt: Date? = nil,
         interactionStateData: Data? = nil,
         visitedDomainURLs: [URL]? = nil,
         tabSnapshotIdentifier: String? = nil) {
        self.uuid = uuid
        self.content = content
        self.title = title
        self.favicon = favicon
        self.lastSelectedAt = lastSelectedAt
        self.burnerMode = .regular
        self.interactionStateData = interactionStateData
        self.visitedDomainURLs = visitedDomainURLs
        self.tabSnapshotIdentifier = tabSnapshotIdentifier
    }

    init(from data: TabRestorationData) {
        self.uuid = data.uuid ?? UUID().uuidString
        self.content = data.content
        self.title = data.title
        self.favicon = data.favicon
        self.interactionStateData = data.interactionStateData
        self.lastSelectedAt = data.lastSelectedAt
        self.burnerMode = .regular  // Burner tabs are never persisted
        self.visitedDomainURLs = data.visitedDomainURLs
        self.tabSnapshotIdentifier = data.tabSnapshotIdentifier
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

        if let visitedDomainURLs {
            tab.history?.restoreVisitedDomainURLs(visitedDomainURLs)
        }
        if let snapshotIdString = tabSnapshotIdentifier,
           let snapshotId = UUID(uuidString: snapshotIdString) {
            tab.tabSnapshots?.setIdentifier(snapshotId)
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
