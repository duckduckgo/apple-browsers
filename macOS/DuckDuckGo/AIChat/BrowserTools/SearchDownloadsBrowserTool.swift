//
//  SearchDownloadsBrowserTool.swift
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
import AppKit
import Foundation

@MainActor
final class SearchDownloadsBrowserTool: BrowserTool {

    static let defaultLimit = 10
    static let maxLimit = 50
    static let maxFileNameLength = 256

    let name = "searchDownloads"
    let permissionMode = BrowserToolPermissionMode.ask
    let permissionReason = "It will see the names and source addresses of files you've downloaded."

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "Optional. Matched against file names and source URLs (case-insensitive). Omit or leave empty to return the most recent downloads."],
            "limit": ["type": "integer", "minimum": 1, "maximum": 50, "description": "Maximum number of results to return (default 10)."]
        ]
    ]

    private let downloads: @MainActor () -> [DownloadListItem]

    init(downloads: @escaping @MainActor () -> [DownloadListItem] = { NSApp.delegateTyped.downloadListCoordinator.downloadListItems }) {
        self.downloads = downloads
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        var query: String?
        if let value = arguments?["query"], value != .null {
            guard let text = value.stringValue, BrowserToolOutputLimits.fits(text, within: BrowserToolOutputLimits.query) else {
                return .failure(.invalidArguments)
            }
            query = text.isEmpty ? nil : text
        }
        var limit = Self.defaultLimit
        if let limitValue = arguments?["limit"], limitValue != .null {
            guard let parsed = limitValue.intValue, (1...Self.maxLimit).contains(parsed) else { return .failure(.invalidArguments) }
            limit = parsed
        }

        let results = downloads()
            .filter { !$0.isBurner && $0.progress == nil && $0.error == nil }
            .sorted { $0.modified > $1.modified }
            .map { item -> (fileName: String, url: String, downloadedAt: Date) in
                // A data: or blob: address can hold the file itself, so only web addresses are returned.
                let url = item.downloadURL.isHttpOrHttps ? BrowserToolOutputLimits.redactedURL(item.downloadURL.absoluteString) : ""
                return (BrowserToolOutputLimits.clip(item.fileName, to: Self.maxFileNameLength), url, item.modified)
            }
            // Matches only what Duck.ai sees, so a query string cannot be confirmed by guessing it.
            .filter { result in
                guard let query else { return true }
                return result.fileName.range(of: query, options: .caseInsensitive) != nil || result.url.range(of: query, options: .caseInsensitive) != nil
            }
            .prefix(limit)
            .map { result -> JSONValue in
                [
                    "fileName": .string(result.fileName),
                    "url": .string(result.url),
                    "downloadedAt": .string(SearchHistoryBrowserTool.isoFormatter.string(from: result.downloadedAt))
                ]
            }
        return .success(["results": .array(Array(results))])
    }
}
