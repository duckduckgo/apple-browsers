//
//  TabRestorationData.swift
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

/// Lightweight container for tab state decoded from NSSecureCoding archives.
///
/// Uses the **same flat NSCoder keys** as `Tab.encode(with:)` and `Tab.init?(coder:)`,
/// plus the extension keys (`visitedDomains`, `TabSnapshotIdentifier`) that tab extensions
/// encode separately.
///
/// Shared by:
/// - `Tab.init?(coder:)` — decodes through this type, then constructs a full `Tab`
/// - `UnloadedTab.init(from:)` — creates a lightweight unloaded tab from these fields
/// - Encoding path (Phase 2b) — converts `AnyTab` back to this type for archiving
final class TabRestorationData: NSObject, NSSecureCoding {

    // MARK: - Coding Keys

    // Same keys as Tab+NSSecureCoding
    private enum NSSecureCodingKeys {
        static let uuid = "uuid"
        static let url = "url"
        // Decode-only: old builds stored Duck Player as a separate content type (.duckPlayer = 5)
        // with explicit videoID/videoTimestamp fields. Newer builds encode Duck Player as a regular
        // .url with a duck://player/VIDEO_ID URL, so these fields are never written — but the
        // decode path still reads them to restore archives from older versions.
        static let videoID = "videoID"
        static let videoTimestamp = "videoTimestamp"
        static let title = "title"
        static let sessionStateData = "ssdata"
        static let interactionStateData = "interactionStateData"
        static let favicon = "icon"
        static let tabType = "tabType"
        static let preferencePane = "preferencePane"
        static let historyPane = "historyPane"
        static let lastSelectedAt = "lastSelectedAt"
    }

    // Extension keys (flat, same coder namespace)
    private enum ExtensionCodingKeys {
        static let visitedDomains = "visitedDomains"
        static let tabSnapshotIdentifier = "TabSnapshotIdentifier"
    }

    // MARK: - Stored Properties

    let uuid: TabIdentifier?
    let content: Tab.TabContent
    let title: String?
    let favicon: NSImage?
    let interactionStateData: Data?
    let lastSelectedAt: Date?

    /// Pass-through from HistoryTabExtension (coding key: "visitedDomains").
    /// Preserved through suspend/materialize cycle so extension state isn't lost on re-encode.
    let localHistoryIDs: [URL]?

    /// Pass-through from TabSnapshotExtension (coding key: "TabSnapshotIdentifier").
    let tabSnapshotIdentifier: String?

    // MARK: - NSSecureCoding

    static var supportsSecureCoding: Bool { true }

    required init?(coder decoder: NSCoder) {
        let uuid: TabIdentifier? = decoder.decodeIfPresent(at: NSSecureCodingKeys.uuid)
        let url: URL? = decoder.decodeIfPresent(at: NSSecureCodingKeys.url)
        let videoID: String? = decoder.decodeIfPresent(at: NSSecureCodingKeys.videoID)
        let videoTimestamp: String? = decoder.decodeIfPresent(at: NSSecureCodingKeys.videoTimestamp)
        let preferencePane = decoder.decodeIfPresent(at: NSSecureCodingKeys.preferencePane)
            .flatMap(PreferencePaneIdentifier.init(rawValue:))
        let historyPane = decoder.decodeIfPresent(at: NSSecureCodingKeys.historyPane)
            .flatMap(HistoryPaneIdentifier.init(rawValue:))

        guard let tabTypeRawValue: Int = decoder.decodeIfPresent(at: NSSecureCodingKeys.tabType),
              let tabType = Tab.TabContent.ContentType(rawValue: tabTypeRawValue),
              let content = Tab.TabContent(type: tabType, url: url, videoID: videoID, timestamp: videoTimestamp, preferencePane: preferencePane, historyPane: historyPane)
        else { return nil }

        let interactionStateData: Data? = decoder.decodeIfPresent(at: NSSecureCodingKeys.interactionStateData)
            ?? decoder.decodeIfPresent(at: NSSecureCodingKeys.sessionStateData)

        self.uuid = uuid
        self.content = content
        self.title = decoder.decodeIfPresent(at: NSSecureCodingKeys.title)
        self.favicon = decoder.decodeIfPresent(at: NSSecureCodingKeys.favicon)
        self.interactionStateData = interactionStateData
        self.lastSelectedAt = decoder.decodeIfPresent(at: NSSecureCodingKeys.lastSelectedAt)

        // Extension pass-through fields
        self.localHistoryIDs = decoder.decodeObject(of: [NSArray.self, NSURL.self],
                                                      forKey: ExtensionCodingKeys.visitedDomains) as? [URL]
        self.tabSnapshotIdentifier = decoder.decodeObject(of: NSString.self,
                                                          forKey: ExtensionCodingKeys.tabSnapshotIdentifier) as? String

        super.init()
    }

    /// Memberwise initializer for creating from a loaded Tab's current state (used in encoding path).
    init(uuid: TabIdentifier?,
         content: Tab.TabContent,
         title: String?,
         favicon: NSImage?,
         interactionStateData: Data?,
         lastSelectedAt: Date?,
         localHistoryIDs: [URL]?,
         tabSnapshotIdentifier: String?) {

        self.uuid = uuid
        self.content = content
        self.title = title
        self.favicon = favicon
        self.interactionStateData = interactionStateData
        self.lastSelectedAt = lastSelectedAt
        self.localHistoryIDs = localHistoryIDs
        self.tabSnapshotIdentifier = tabSnapshotIdentifier
        super.init()
    }

    func encode(with coder: NSCoder) {
        uuid.map(coder.encode(forKey: NSSecureCodingKeys.uuid))
        content.urlForWebView.map(coder.encode(forKey: NSSecureCodingKeys.url))
        title.map(coder.encode(forKey: NSSecureCodingKeys.title))
        favicon.map(coder.encode(forKey: NSSecureCodingKeys.favicon))
        interactionStateData.map(coder.encode(forKey: NSSecureCodingKeys.interactionStateData))

        coder.encode(content.type.rawValue, forKey: NSSecureCodingKeys.tabType)
        lastSelectedAt.map(coder.encode(forKey: NSSecureCodingKeys.lastSelectedAt))

        if let pane = content.preferencePane {
            coder.encode(pane.rawValue, forKey: NSSecureCodingKeys.preferencePane)
        } else if let pane = content.historyPane {
            coder.encode(pane.rawValue, forKey: NSSecureCodingKeys.historyPane)
        }

        // Extension pass-through fields
        if let localHistoryIDs {
            coder.encode(localHistoryIDs, forKey: ExtensionCodingKeys.visitedDomains)
        }
        if let tabSnapshotIdentifier {
            coder.encode(tabSnapshotIdentifier, forKey: ExtensionCodingKeys.tabSnapshotIdentifier)
        }
    }

}
