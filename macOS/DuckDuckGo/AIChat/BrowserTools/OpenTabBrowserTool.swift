//
//  OpenTabBrowserTool.swift
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

/// Opens a web page in a background tab of the chat's window and waits for it to settle. The tab
/// is recorded as Duck.ai's, so `closeTab` may close it and `readTabContent` may read it unprompted.
@MainActor
final class OpenTabBrowserTool: BrowserTool {

    /// Once a chat has this many tabs open, its oldest one makes room for the next. That keeps a
    /// read-and-move-on loop working even when the model never calls `closeTab`.
    static let maxOpenTabsPerChat = 5

    /// Matches `AIChatBrowserToolsSubfeature.openTab`, which is how the catalog gates it.
    let name = "openTab"
    let title = "Open tab"
    let description = "Open an http(s) URL in a new background tab and wait for the page to load. Read it with readTabContent, then close it with closeTab."
    let permissionMode = BrowserToolPermissionMode.auto

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "url": ["type": "string", "description": "The http(s) URL to open."]
        ],
        "required": ["url"]
    ]

    let outputSchema: JSONValue? = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string"],
            "url": ["type": "string", "description": "The final URL, after redirects."],
            "title": ["type": "string"],
            "status": ["type": "string", "enum": ["loaded", "timeout"]]
        ],
        "required": ["tabId", "url", "title", "status"]
    ]

    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: false,
                                                              destructiveHint: false,
                                                              idempotentHint: false,
                                                              openWorldHint: true)

    private let windowControllersManager: WindowControllersManagerProtocol
    private let openedTabs: BrowserToolOpenedTabs
    private let loadWaiter: BrowserToolPageLoadWaiting

    init(windowControllersManager: WindowControllersManagerProtocol,
         openedTabs: BrowserToolOpenedTabs,
         loadWaiter: BrowserToolPageLoadWaiting) {
        self.windowControllersManager = windowControllersManager
        self.openedTabs = openedTabs
        self.loadWaiter = loadWaiter
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        guard let url = Self.webURL(from: arguments?["url"]) else { return .failure(.invalidArguments) }
        guard let token = context.ownerWindowToken,
              let collection = AIChatTabPickerSource.tabCollectionViewModel(forWindowToken: token, in: windowControllersManager),
              !collection.isBurner else {
            return .failure(.unavailable)
        }

        makeRoom(forOwnerTabID: context.ownerTabID, in: collection)

        // `.url` rather than `contentFromURL`, which would switch to an open Duck.ai tab instead.
        let tab = Tab(content: .url(url, source: .link), shouldLoadInBackground: true, burnerMode: collection.burnerMode)
        // Recorded before it is shown, so the tab bar marks it from the first frame.
        openedTabs.add(tab.uuid, ownerTabID: context.ownerTabID)
        // `append` rather than `insert(_:selected:)`, which selects a tab without a parent anyway.
        guard collection.append(tab: tab, selected: false) != nil else {
            openedTabs.remove(tab.uuid)
            return .failure(.unavailable)
        }

        let outcome: BrowserToolPageLoadOutcome
        do {
            outcome = try await loadWaiter.waitUntilSettled(tab)
        } catch {
            close(tab)
            return .failure(.cancelled)
        }

        // Closed while it loaded: by the user, by `closeTab`, or to make room for a newer one.
        guard openedTabs.contains(tab.uuid, ownerTabID: context.ownerTabID) else { return .failure(.unavailable) }

        switch outcome {
        case .blocked:
            // A failure carries no tabId, so Duck.ai could never close a tab left open here.
            close(tab)
            return .failure(.blocked)
        case .loaded, .timeout:
            return .success([
                "tabId": .string(tab.uuid),
                "url": .string((tab.webView.url ?? url).absoluteString),
                "title": .string(tab.title ?? ""),
                "status": .string(outcome == .loaded ? "loaded" : "timeout")
            ])
        }
    }

    static func webURL(from argument: JSONValue?) -> URL? {
        guard let string = argument?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    /// The tab the user is looking at is never the one that goes.
    private func makeRoom(forOwnerTabID ownerTabID: String, in collection: TabCollectionViewModel) {
        let tabIDs = openedTabs.tabIDs(ownerTabID: ownerTabID)
        guard tabIDs.count >= Self.maxOpenTabsPerChat else { return }
        let selectedTabID = collection.selectedTabViewModel?.tab.uuid
        guard let oldest = tabIDs.first(where: { $0 != selectedTabID }) else { return }
        openedTabs.remove(oldest)
        BrowserToolTargetTab.closeUnpinnedTab(withID: oldest, in: windowControllersManager)
    }

    private func close(_ tab: Tab) {
        openedTabs.remove(tab.uuid)
        BrowserToolTargetTab.closeUnpinnedTab(withID: tab.uuid, in: windowControllersManager)
    }
}
