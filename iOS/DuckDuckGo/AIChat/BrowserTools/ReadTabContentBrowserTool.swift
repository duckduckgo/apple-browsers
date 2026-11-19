//
//  ReadTabContentBrowserTool.swift
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
import FoundationExtensions

@MainActor
final class ReadTabContentBrowserTool: BrowserTool {

    let name = "readTabContent"
    let permissionMode = BrowserToolPermissionMode.ask

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": [
                "type": "string",
                "description": "Optional. Omit only for the tab hosting this chat ('this/current/this page'). For a named other tab, or after unavailable on a Duck.ai tab, pass a GUID from listOpenTabs (prefer isAttachable=true)."
            ]
        ]
    ]

    private let scopeProvider: BrowserToolScopeProvider
    private let reader: BrowserToolPageContentReading

    init(scopeProvider: @escaping BrowserToolScopeProvider, reader: BrowserToolPageContentReading) {
        self.scopeProvider = scopeProvider
        self.reader = reader
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }

        switch arguments {
        case .none, .some(.null), .some(.object): break
        default:
            return .failure(.invalidArguments)
        }

        guard let scope = scopeProvider(context), scope.accepts(context) else { return .failure(.unavailable) }
        let tab: Tab
        switch BrowserToolTargetTab.resolve(tabIDArgument: arguments?["tabId"], context: context, scope: scope) {
        case .failure(let failure):
            return .failure(failure)
        case .resolved(let target): tab = target
        }
        guard !Task.isCancelled, scope.canRead(tab) else { return .failure(.unavailable) }
        let tabID = tab.uid

        guard let pageContext = await reader.pageContext(for: tab, in: scope) else {
            return .failure(.unavailable)
        }
        guard !Task.isCancelled, scope.accepts(context), scope.canRead(tab) else {
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

    func clientToolResult(from value: JSONValue) -> BrowserToolResult {
        guard let tabID = value["tabId"]?.stringValue, let content = value["content"]?.stringValue else { return .failure(.unavailable) }
        // Documents (PDF) carry bytes, which the contract has no field for.
        if let mimeType = value["mimeType"]?.stringValue, mimeType != AIChatPageContextData.htmlMIMEType {
            return .failure(.unavailable)
        }
        let clippedContent = BrowserToolOutputLimits.clip(content, to: BrowserToolOutputLimits.content)
        let fullContentLength = value["fullContentLength"]?.intValue ?? 0
        let redactedURL = Self.redactedURL(value["url"]?.stringValue ?? "")
        return .success([
            "title": .string(BrowserToolOutputLimits.clip(value["title"]?.stringValue ?? "", to: BrowserToolOutputLimits.title)),
            "url": .string(redactedURL),
            "content": .string(clippedContent),
            "truncated": .bool(value["truncated"]?.boolValue == true || clippedContent != content),
            "fullContentLength": .int(max(fullContentLength, content.unicodeScalars.count)),
            "tabId": .string(tabID),
            "attachable": .bool(value["attachable"]?.boolValue ?? true),
            "attached": .bool(false)
        ])
    }

    static func redactedURL(_ url: String) -> String {
        var redacted = String(url[..<(url.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? url.endIndex)])
        if let scheme = redacted.range(of: "://") {
            let authorityEnd = redacted[scheme.upperBound...].firstIndex(of: "/") ?? redacted.endIndex
            if let at = redacted[scheme.upperBound..<authorityEnd].lastIndex(of: "@") {
                redacted.removeSubrange(scheme.upperBound...at)
            }
        }
        return BrowserToolOutputLimits.clip(redacted, to: BrowserToolOutputLimits.url)
    }
}
