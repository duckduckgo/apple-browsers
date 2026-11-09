//
//  ListOpenTabsBrowserTool.swift
//  DuckDuckGo
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
import PrivacyConfig

@MainActor
final class ListOpenTabsBrowserTool: BrowserTool {

    static let defaultLimit = 50
    static let maxLimit = 50

    let name = AIChatBrowserToolsSubfeature.listOpenTabs.rawValue
    let permissionMode = BrowserToolPermissionMode.ask
    let permissionReason = "Duck.ai wants to see your open tabs."

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "limit": ["type": "integer", "minimum": 1, "maximum": 50]
        ]
    ]

    private let scopeProvider: BrowserToolScopeProvider

    init(scopeProvider: @escaping BrowserToolScopeProvider) {
        self.scopeProvider = scopeProvider
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }

        var limit = Self.defaultLimit
        if let limitValue = arguments?["limit"] {
            guard let parsed = limitValue.intValue else { return .failure(.invalidArguments) }
            limit = parsed
        }
        guard (1...Self.maxLimit).contains(limit) else { return .failure(.invalidArguments) }

        guard let scope = scopeProvider(context), scope.accepts(context) else { return .failure(.unavailable) }

        let tabs = scope.source.tabsProvider()
        let selectedTabID = scope.selectedTabID()
        let pages: [JSONValue] = tabs.compactMap { tab in
            guard tab.mode == .normal, let link = tab.link, !link.url.isDuckAIURL else { return nil }
            return [
                "tabId": .string(tab.uid),
                "title": .string(link.displayTitle),
                "url": .string(link.url.absoluteString),
                "isCurrentTab": .bool(tab.uid == selectedTabID),
                "isAttachable": .bool(!AIChatTabMetadata.shouldExcludeFromTabPicker(link.url))
            ]
        }
        return .success(["tabs": .array(Array(pages.prefix(limit)))])
    }

    func clientToolResult(from value: JSONValue) -> BrowserToolResult {
        guard let tabs = value["tabs"]?.arrayValue else { return .failure(.unavailable) }
        return .success(["tabs": .array(tabs.map { tab in
            var fields = tab.objectValue ?? [:]
            fields["title"] = BrowserToolOutputLimits.clip(fields["title"], to: BrowserToolOutputLimits.title)
            fields["url"] = BrowserToolOutputLimits.clip(fields["url"], to: BrowserToolOutputLimits.url)
            return .object(fields)
        })])
    }
}
