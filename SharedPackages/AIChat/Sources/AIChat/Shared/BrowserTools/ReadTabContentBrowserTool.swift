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

import Foundation
import PrivacyConfig

public typealias BrowserToolPageLoader = @MainActor (JSONValue?, BrowserToolCallContext) async -> Result<AIChatPageContextData, BrowserToolFailure>

@MainActor
public final class ReadTabContentBrowserTool: BrowserTool {

    public let name = AIChatBrowserToolsSubfeature.readTabContent.rawValue
    public let permissionMode = BrowserToolPermissionMode.ask

    public let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": [
                "type": "string",
                "description": "Optional. Omit only for the tab hosting this chat ('this/current/this page'). For a named other tab, or after unavailable on a Duck.ai tab, pass a GUID from listOpenTabs (prefer isAttachable=true)."
            ]
        ]
    ]

    private let readPage: BrowserToolPageLoader

    public init(readPage: @escaping BrowserToolPageLoader) {
        self.readPage = readPage
    }

    public func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }

        switch arguments {
        case .none, .some(.null), .some(.object): break
        default:
            return .failure(.invalidArguments)
        }

        let pageContext: AIChatPageContextData
        switch await readPage(arguments?["tabId"], context) {
        case .failure(let failure): return .failure(failure)
        case .success(let page): pageContext = page
        }

        guard let payload = Self.jsonValue(for: pageContext) else {
            return .failure(.unavailable)
        }
        return .success(payload)
    }

    private static func jsonValue(for pageContext: AIChatPageContextData) -> JSONValue? {
        guard let data = try? JSONEncoder().encode(pageContext),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return try? JSONValue(jsonString: string)
    }

    public func clientToolResult(from value: JSONValue) -> BrowserToolResult {
        guard let tabID = value["tabId"]?.stringValue, let content = value["content"]?.stringValue else { return .failure(.unavailable) }
        // Documents (PDF) carry bytes, which the contract has no field for.
        if let mimeType = value["mimeType"]?.stringValue, mimeType != AIChatPageContextData.htmlMIMEType {
            return .failure(.unavailable)
        }
        let clippedContent = BrowserToolOutputLimits.clip(content, to: BrowserToolOutputLimits.content)
        let fullContentLength = value["fullContentLength"]?.intValue ?? 0
        let redactedURL = BrowserToolOutputLimits.redactedURL(value["url"]?.stringValue ?? "")
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

}
