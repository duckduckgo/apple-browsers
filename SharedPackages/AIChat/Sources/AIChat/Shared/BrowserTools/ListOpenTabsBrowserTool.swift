//
//  ListOpenTabsBrowserTool.swift
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

import Foundation
import PrivacyConfig

@MainActor
public final class ListOpenTabsBrowserTool: BrowserTool {

    static let defaultLimit = 50
    static let maxLimit = 50

    public let name = AIChatBrowserToolsSubfeature.listOpenTabs.rawValue
    public let permissionMode = BrowserToolPermissionMode.ask

    public let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "limit": ["type": "integer", "minimum": 1, "maximum": 50]
        ]
    ]

    public struct TabEntry {
        let id: String
        let title: String
        let url: URL

        public init(id: String, title: String, url: URL) {
            self.id = id
            self.title = title
            self.url = url
        }
    }

    /// Returns the platform's eligible tabs and selected tab ID, or `nil` if the call's scope is unavailable.
    private let openTabs: @MainActor (BrowserToolCallContext) -> (tabs: [TabEntry], selectedTabID: String?)?

    public init(openTabs: @escaping @MainActor (BrowserToolCallContext) -> (tabs: [TabEntry], selectedTabID: String?)?) {
        self.openTabs = openTabs
    }

    public func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }

        var limit = Self.defaultLimit
        if let limitValue = arguments?["limit"] {
            guard let parsed = limitValue.intValue else { return .failure(.invalidArguments) }
            limit = parsed
        }
        guard (1...Self.maxLimit).contains(limit) else { return .failure(.invalidArguments) }

        guard let (tabs, selectedTabID) = openTabs(context) else { return .failure(.unavailable) }
        let httpsTabs = tabs.filter { $0.url.scheme?.lowercased() == "https" }
        let pages: [JSONValue] = httpsTabs.prefix(limit).map { tab in
            [
                "tabId": .string(tab.id),
                "title": .string(tab.title),
                "url": .string(tab.url.absoluteString),
                "isCurrentTab": .bool(tab.id == selectedTabID),
                "isAttachable": .bool(!AIChatTabMetadata.shouldExcludeFromTabPicker(tab.url))
            ]
        }
        return .success(["tabs": .array(pages)])
    }

    public func clientToolResult(from value: JSONValue) -> BrowserToolResult {
        guard let tabs = value["tabs"]?.arrayValue else { return .failure(.unavailable) }
        return .success(["tabs": .array(tabs.map { tab in
            var fields = tab.objectValue ?? [:]
            fields["title"] = BrowserToolOutputLimits.clip(fields["title"], to: BrowserToolOutputLimits.title)
            fields["url"] = BrowserToolOutputLimits.redactedURL(fields["url"])
            return .object(fields)
        })])
    }

    public func resultCount(of value: JSONValue) -> Int? { value["tabs"]?.arrayValue?.count }
}
