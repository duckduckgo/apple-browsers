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

/// Searches completed downloads by file name and source URL. Asks first: downloads are browsing
/// data. Never returns the local path, which would expose the username.
@MainActor
final class SearchDownloadsBrowserTool: BrowserTool {

    static let defaultLimit = 10
    static let maxLimit = 50
    static let maxFileNameLength = 256

    /// Matches `AIChatBrowserToolsSubfeature.searchDownloads`, which is how the catalog gates it.
    let name = "searchDownloads"
    let permissionMode = BrowserToolPermissionMode.ask
    let permissionReason = "Duck.ai wants to search your downloads."

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "Matched against file names and source URLs (case-insensitive)."],
            "limit": ["type": "integer", "minimum": 1, "maximum": 50, "description": "Maximum number of results to return (default 10)."]
        ],
        "required": ["query"]
    ]

    private let downloads: @MainActor () -> [DownloadListItem]

    /// - Parameter downloads: read on each call; the app's download list is created after this tool.
    init(downloads: @escaping @MainActor () -> [DownloadListItem] = { NSApp.delegateTyped.downloadListCoordinator.downloadListItems }) {
        self.downloads = downloads
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        guard let query = arguments?["query"]?.stringValue, !query.isEmpty,
              BrowserToolOutputLimits.fits(query, within: BrowserToolOutputLimits.query) else {
            return .failure(.invalidArguments)
        }
        var limit = Self.defaultLimit
        if let limitValue = arguments?["limit"] {
            guard let parsed = limitValue.intValue, (1...Self.maxLimit).contains(parsed) else { return .failure(.invalidArguments) }
            limit = parsed
        }

        let results = downloads()
            .filter { item in
                // Fire Window downloads belong to a private session; unfinished or failed ones were never downloaded.
                guard !item.isBurner, item.progress == nil, item.error == nil else { return false }
                return item.fileName.range(of: query, options: .caseInsensitive) != nil
                    || item.downloadURL.absoluteString.range(of: query, options: .caseInsensitive) != nil
            }
            .sorted { $0.added > $1.added }
            .prefix(limit)
            .map { item -> JSONValue in
                [
                    "fileName": .string(BrowserToolOutputLimits.clip(item.fileName, to: Self.maxFileNameLength)),
                    "url": .string(BrowserToolOutputLimits.clip(item.downloadURL.absoluteString, to: BrowserToolOutputLimits.url)),
                    "downloadedAt": .string(SearchHistoryBrowserTool.isoFormatter.string(from: item.added))
                ]
            }
        return .success(["results": .array(Array(results))])
    }
}
