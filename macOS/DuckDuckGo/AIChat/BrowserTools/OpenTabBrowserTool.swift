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

@MainActor
final class OpenTabBrowserTool: BrowserTool {

    let name = "openTab"
    let permissionMode = BrowserToolPermissionMode.auto

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "url": ["type": "string", "description": "Absolute http or https URL to open in a new tab."]
        ],
        "required": ["url"]
    ]

    private let windowControllersManager: WindowControllersManagerProtocol

    init(windowControllersManager: WindowControllersManagerProtocol) {
        self.windowControllersManager = windowControllersManager
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        guard let url = Self.webURL(from: arguments?["url"]) else { return .failure(.invalidArguments) }
        guard let collection = targetCollection(for: context) else { return .failure(.unavailable) }

        let tab = Tab(content: .url(url, credential: nil, source: .link), shouldLoadInBackground: true, burnerMode: collection.burnerMode)
        collection.insertOrAppend(tab: tab, selected: false)
        guard collection.indexInAllTabs(of: tab) != nil else { return .failure(.unavailable) }

        return .success(["tabId": .string(tab.uuid)])
    }

    private func targetCollection(for context: BrowserToolCallContext) -> TabCollectionViewModel? {
        if context.isDetached,
           let collection = windowControllersManager.lastKeyMainWindowController(where: { !$0.mainViewController.isBurner })?
            .mainViewController.tabCollectionViewModel {
            return collection
        }
        guard let token = context.ownerWindowToken else { return nil }
        return AIChatTabPickerSource.tabCollectionViewModel(forWindowToken: token, in: windowControllersManager)
    }

    /// Only web pages: other schemes could reach local files, scripts or browser-internal pages.
    private static func webURL(from value: JSONValue?) -> URL? {
        guard let string = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty, BrowserToolOutputLimits.fits(string, within: BrowserToolOutputLimits.url),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else { return nil }
        return url
    }
}
