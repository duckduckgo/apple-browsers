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
    let permissionMode = BrowserToolPermissionMode.ask

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": [
                "type": "string",
                "description": "Optional. Omit only for the sidebar host page ('this/current/this page'). For a named other tab, or after unavailable on a Duck.ai host, pass a GUID from listOpenTabs (prefer isAttachable=true)."
            ]
        ]
    ]

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

    /// Only the contract's fields. Content is cut here, at the browser-tools boundary, so page
    /// attachments keep their own longer limit. Reading never attaches the page.
    func clientToolResult(from value: JSONValue) -> BrowserToolResult {
        guard let tabID = value["tabId"]?.stringValue, let content = value["content"]?.stringValue else { return .failure(.unavailable) }
        // Documents (PDF) carry bytes, which the contract has no field for.
        if let mimeType = value["mimeType"]?.stringValue, mimeType != AIChatPageContextData.htmlMIMEType {
            return .failure(.unavailable)
        }
        let clippedContent = BrowserToolOutputLimits.clip(content, to: BrowserToolOutputLimits.content)
        let fullContentLength = value["fullContentLength"]?.intValue ?? 0
        return .success([
            "title": .string(BrowserToolOutputLimits.clip(value["title"]?.stringValue ?? "", to: BrowserToolOutputLimits.title)),
            "url": .string(BrowserToolOutputLimits.redactedURL(value["url"]?.stringValue ?? "")),
            "content": .string(clippedContent),
            "truncated": .bool(value["truncated"]?.boolValue == true || clippedContent != content),
            "fullContentLength": .int(max(fullContentLength, content.unicodeScalars.count)),
            "tabId": .string(tabID),
            "attachable": .bool(value["attachable"]?.boolValue ?? true),
            "attached": .bool(false)
        ])
    }
}
