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

import Foundation
import PrivacyConfig

@MainActor
public final class OpenTabBrowserTool: BrowserTool {

    public let name = AIChatBrowserToolsSubfeature.openTab.rawValue
    public let permissionMode = BrowserToolPermissionMode.ask
    public let asksEveryTime = true
    public let requiresPermissionTarget = true
    public let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "url": ["type": "string", "description": "Absolute http or https URL to open in a new tab."]
        ],
        "required": ["url"]
    ]

    private let openTab: @MainActor (URL, BrowserToolCallContext) -> String?

    public init(openTab: @escaping @MainActor (URL, BrowserToolCallContext) -> String?) {
        self.openTab = openTab
    }

    public func permissionTarget(arguments: JSONValue?, context: BrowserToolCallContext) -> String? {
        Self.webURL(from: arguments?["url"])?.absoluteString
    }

    public func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        guard let url = Self.webURL(from: arguments?["url"]) else { return .failure(.invalidArguments) }
        guard !Task.isCancelled else { return .failure(.cancelled) }
        guard let tabID = openTab(url, context) else { return .failure(.unavailable) }
        return .success(["tabId": .string(tabID)])
    }

    private static func webURL(from value: JSONValue?) -> URL? {
        guard let string = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty, BrowserToolOutputLimits.fits(string, within: BrowserToolOutputLimits.url),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false, !url.isDuckAIURL else { return nil }
        return url
    }
}
