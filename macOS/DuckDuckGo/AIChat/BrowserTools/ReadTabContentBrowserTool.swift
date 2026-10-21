//
//  ReadTabContentBrowserTool.swift
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

/// Returns a tab's extracted text, the same payload the sidebar's `@` picker attaches.
@MainActor
final class ReadTabContentBrowserTool: BrowserTool {

    /// Matches `AIChatBrowserToolsSubfeature.readTabContent`, which is how the catalog gates it.
    let name = "readTabContent"
    let title = "Read tab content"
    let description = "Read the text content of an open tab."
    let permissionMode = BrowserToolPermissionMode.ask
    let permissionReason = "Duck.ai wants to read this tab's content."

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": [
                "type": "string",
                "description": "Optional. Omit only for the sidebar host page ('this/current/this page'). For a named other tab, or after unavailable on a Duck.ai host, pass a GUID from listOpenTabs (prefer isAttachable=true)."
            ]
        ]
    ]

    let outputSchema: JSONValue? = [
        "type": "object",
        "properties": [
            "title": ["type": "string"],
            "url": ["type": "string"],
            "content": ["type": "string"],
            "truncated": ["type": "boolean"],
            "fullContentLength": ["type": "integer"],
            "tabId": ["type": "string"],
            "favicon": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "href": ["type": "string"],
                        "rel": ["type": "string"]
                    ]
                ]
            ],
            "contentScope": ["type": "string"],
            "pageTypeSignals": ["type": "object"],
            "attached": ["type": "boolean"],
            "attachable": ["type": "boolean"]
        ],
        "required": ["title", "url", "truncated", "fullContentLength", "tabId"]
    ]

    let annotations: MCPToolAnnotations? = MCPToolAnnotations(readOnlyHint: true,
                                                              destructiveHint: false,
                                                              idempotentHint: true,
                                                              openWorldHint: false)

    private let windowControllersManager: WindowControllersManagerProtocol
    private let reader: BrowserToolPageContentReading

    init(windowControllersManager: WindowControllersManagerProtocol, reader: BrowserToolPageContentReading) {
        self.windowControllersManager = windowControllersManager
        self.reader = reader
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }

        switch arguments {
        case .none, .some(.null), .some(.object): break
        default: return .failure(.invalidArguments)
        }

        let tabID: TabIdentifier
        let collection: TabCollectionViewModel
        switch BrowserToolTargetTab.resolve(tabIDArgument: arguments?["tabId"], context: context, in: windowControllersManager) {
        case .failure(let failure): return .failure(failure)
        case .resolved(let resolvedID, let resolvedCollection):
            tabID = resolvedID
            collection = resolvedCollection
        }

        guard let pageContext = await reader.pageContext(forTabID: tabID, in: collection) else {
            return .failure(.unavailable)
        }
        guard let payload = Self.jsonValue(for: pageContext.withTabId(tabID)) else {
            return .failure(.unavailable)
        }
        return .success(payload)
    }

    static func jsonValue(for pageContext: AIChatPageContextData) -> JSONValue? {
        guard let data = try? JSONEncoder().encode(pageContext),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return try? JSONValue(jsonString: string)
    }
}
