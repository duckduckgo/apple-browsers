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

import Foundation

@MainActor
public final class SearchBookmarksBrowserTool: BrowserTool {

    static let defaultLimit = 10
    static let maxLimit = 50

    public let name = ClientToolCapability.searchBookmarks.name
    public let permissionMode = BrowserToolPermissionMode.ask

    public let inputSchema: JSONValue = [
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

    private let search: @MainActor (Search, BrowserToolCallContext) async -> [Search.Match]?

    public init(search: @escaping @MainActor (Search, BrowserToolCallContext) async -> [Search.Match]?) {
        self.search = search
    }

    public func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        guard !Task.isCancelled else { return .failure(.cancelled) }

        var query: String?
        if let value = arguments?["query"], value != .null {
            guard let text = value.stringValue, BrowserToolOutputLimits.fits(text, within: BrowserToolOutputLimits.query) else {
                return .failure(.invalidArguments)
            }
            query = text.isEmpty ? nil : text
        }
        guard let folderPath = BrowserToolBookmarkFolder.folderPath(from: arguments) else { return .failure(.invalidArguments) }
        var limit = Self.defaultLimit
        if let limitValue = arguments?["limit"], limitValue != .null {
            guard let parsed = limitValue.intValue, (1...Self.maxLimit).contains(parsed) else { return .failure(.invalidArguments) }
            limit = parsed
        }
        let matches = await search(Search(folderPath: folderPath, query: query, limit: limit), context)
        guard !Task.isCancelled else { return .failure(.cancelled) }
        guard let matches else { return .failure(.unavailable) }

        let results = matches.map { match -> JSONValue in
            ["title": .string(match.title), "url": .string(match.url), "folder": .array(match.folder.map(JSONValue.string))]
        }
        return .success(["results": .array(results)])
    }

    public func resultCount(of value: JSONValue) -> Int? { value["results"]?.arrayValue?.count }

    public struct Search: Sendable {
        public struct Match: Sendable {
            let title: String
            let url: String
            let folder: [String]

            func matches(_ query: String?) -> Bool {
                guard let query else { return true }
                return ([title, url] + folder).contains { $0.range(of: query, options: .caseInsensitive) != nil }
            }
        }

        let folderPath: [String]
        let query: String?
        let limit: Int

        public nonisolated func matches<Node>(in root: [Node],
                                              folder: (Node) -> (title: String, children: () -> [Node])?,
                                              bookmark: (Node) -> (title: String, url: URL)?) -> [Match] {
            let contents = BrowserToolBookmarkFolder.contents(of: folderPath, in: root) { node, name in
                guard let folder = folder(node), folder.title == name else { return nil }
                return folder.children()
            }
            var matches: [Match] = []

            func collect(_ nodes: [Node], path: [String]) {
                for node in nodes {
                    guard matches.count < limit else { return }
                    if let folder = folder(node) {
                        guard path.count < BrowserToolBookmarkFolder.maxDepth else { continue }
                        let title = BrowserToolOutputLimits.clip(folder.title, to: BrowserToolBookmarkFolder.maxNameLength)
                        collect(folder.children(), path: path + [title])
                    } else if let bookmark = bookmark(node) {
                        let match = Match(title: BrowserToolOutputLimits.clip(bookmark.title, to: BrowserToolOutputLimits.title),
                                          url: BrowserToolOutputLimits.redactedURL(bookmark.url.absoluteString),
                                          folder: path)
                        if match.matches(query) {
                            matches.append(match)
                        }
                    }
                }
            }

            collect(contents, path: folderPath)
            return matches
        }
    }
}
