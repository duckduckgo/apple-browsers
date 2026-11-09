//
//  SearchBookmarksBrowserTool.swift
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

/// Searches bookmarks by title, URL and folder name, optionally within a folder path and its
/// subfolders, in bookmark order. Asks first: bookmarks are the user's own data.
@MainActor
final class SearchBookmarksBrowserTool: BrowserTool {

    static let defaultLimit = 10
    static let maxLimit = 50

    /// Matches `AIChatBrowserToolsSubfeature.searchBookmarks`, which is how the catalog gates it.
    let name = "searchBookmarks"
    let permissionMode = BrowserToolPermissionMode.ask
    let permissionReason = "It will see the titles, addresses and folders of your bookmarks."

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "Optional. Matched against bookmark titles, URLs and folder names (case-insensitive)."],
            "folder": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Optional. Folder names from the top level, e.g. [\"Travel\", \"Disney\"]. Limits results to that folder and its subfolders."
            ],
            "limit": ["type": "integer", "minimum": 1, "maximum": 50, "description": "Maximum number of results to return (default 10)."]
        ]
    ]

    private struct Result {
        let title: String
        let url: String
        let folder: [String]
    }

    private let bookmarkManager: BookmarkManager

    init(bookmarkManager: BookmarkManager) {
        self.bookmarkManager = bookmarkManager
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }

        var query: String?
        if let value = arguments?["query"] {
            guard let text = value.stringValue, BrowserToolOutputLimits.fits(text, within: BrowserToolOutputLimits.query) else {
                return .failure(.invalidArguments)
            }
            query = text.isEmpty ? nil : text
        }
        guard let folderPath = BookmarkTabBrowserTool.folderPath(from: arguments) else { return .failure(.invalidArguments) }
        var limit = Self.defaultLimit
        if let limitValue = arguments?["limit"] {
            guard let parsed = limitValue.intValue, (1...Self.maxLimit).contains(parsed) else { return .failure(.invalidArguments) }
            limit = parsed
        }
        guard let list = bookmarkManager.list else { return .failure(.unavailable) }

        // A folder that does not exist yields no results rather than an error.
        guard let folder = Self.contents(of: folderPath, in: list) else { return .success(["results": []]) }
        var results: [Result] = []
        Self.collect(folder.entities, path: folder.path, into: &results)

        let matches = results
            // Matches only what Duck.ai sees, so a query string cannot be confirmed by guessing it.
            .filter { result in
                guard let query else { return true }
                return ([result.title, result.url] + result.folder).contains { $0.range(of: query, options: .caseInsensitive) != nil }
            }
            .prefix(limit)
            .map { result -> JSONValue in
                ["title": .string(result.title), "url": .string(result.url), "folder": .array(result.folder.map(JSONValue.string))]
            }
        return .success(["results": .array(Array(matches))])
    }

    /// The children of the folder at `path` and that path's names, or nil when it does not exist.
    /// Names match exactly; the first folder with a name wins, as in `bookmarkTab`.
    private static func contents(of path: [String], in list: BookmarkList) -> (entities: [BaseBookmarkEntity], path: [String])? {
        var entities = list.topLevelEntities
        for name in path {
            guard let folder = entities.lazy.compactMap({ $0 as? BookmarkFolder }).first(where: { $0.title == name }) else { return nil }
            entities = folder.children
        }
        return (entities, path.map { BrowserToolOutputLimits.clip($0, to: BookmarkTabBrowserTool.maxFolderNameLength) })
    }

    /// Bookmarks in tree order. Only web pages, and none deeper than the contract's folder depth.
    private static func collect(_ entities: [BaseBookmarkEntity], path: [String], into results: inout [Result]) {
        for entity in entities {
            if let folder = entity as? BookmarkFolder {
                guard path.count < BookmarkTabBrowserTool.maxFolderDepth else { continue }
                collect(folder.children, path: path + [BrowserToolOutputLimits.clip(folder.title, to: BookmarkTabBrowserTool.maxFolderNameLength)],
                        into: &results)
            } else if let bookmark = entity as? Bookmark, let url = bookmark.urlObject, url.isHttpOrHttps {
                results.append(Result(title: BrowserToolOutputLimits.clip(bookmark.title, to: BrowserToolOutputLimits.title),
                                      url: BrowserToolOutputLimits.urlWithoutQueryOrFragment(url.absoluteString),
                                      folder: path))
            }
        }
    }
}
