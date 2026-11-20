//
//  BrowserToolsPixel.swift
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
import PixelKit

/// Duck.ai browser tools. Parameters carry fixed values only: never URLs, titles, page text, search terms or IDs.
enum BrowserToolsPixel: PixelKit.Event {

    /// Event Trigger: A browser tool call finished, whatever its result. `tool` is a slug from `toolSlugs`.
    case call(tool: String, result: ClientToolError?, permissionPath: BrowserToolPermissionPath, duration: TimeInterval?)

    /// Event Trigger: A browser tool call succeeded. Fired daily.
    case used

    /// Event Trigger: A call to this tool succeeded. Fired daily. `tool` is a slug from `toolSlugs`.
    case usedTool(String)

    /// Catalog names to pixel slugs. Any other name came from the page and is never sent.
    static let toolSlugs = [
        "listOpenTabs": "list_open_tabs",
        "readTabContent": "read_tab_content",
        "searchHistory": "search_history",
        "findInPage": "find_in_page",
        "highlightInPage": "highlight_in_page",
        "switchToTab": "switch_to_tab",
        "pinTab": "pin_tab",
        "openTab": "open_tab",
        "bookmarkTab": "bookmark_tab",
        "closeTabs": "close_tabs",
        "searchDownloads": "search_downloads",
        "searchBookmarks": "search_bookmarks"
    ]

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .call: "aichat_tools_call_macos"
        case .used: "aichat_tools_used_macos"
        case .usedTool(let tool): "aichat_tools_used_\(tool)_macos"
        }
    }

    var parameters: [String: String]? {
        guard case .call(let tool, let result, let permissionPath, let duration) = self else { return nil }
        var parameters = ["tool": tool, "result": result?.rawValue ?? "success", "permission_path": permissionPath.rawValue]
        parameters["duration"] = duration.map(Self.durationBucket)
        return parameters
    }

    var standardParameters: [PixelKitStandardParameter]? { [.pixelSource] }

    static func durationBucket(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<0.1: "lt_100ms"
        case ..<0.5: "lt_500ms"
        case ..<2: "lt_2s"
        case ..<10: "lt_10s"
        default: "gte_10s"
        }
    }
}

struct BrowserToolsPixelInstrumentation: BrowserToolsInstrumentation {
    let pixelFiring: PixelFiring?

    func toolCallDidFinish(tool: String, response: ExecuteClientToolResponse, trace: BrowserToolCallTrace) {
        guard let slug = BrowserToolsPixel.toolSlugs[tool] else { return }
        let error: ClientToolError? = if case .failure(_, let error) = response { error } else { nil }
        pixelFiring?.fire(BrowserToolsPixel.call(tool: slug, result: error, permissionPath: trace.permissionPath,
                                                 duration: trace.executionDuration))
        guard error == nil else { return }
        pixelFiring?.fire(BrowserToolsPixel.used, frequency: .daily)
        pixelFiring?.fire(BrowserToolsPixel.usedTool(slug), frequency: .daily)
    }
}
