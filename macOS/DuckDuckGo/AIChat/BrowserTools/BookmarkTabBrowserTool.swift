//
//  BookmarkTabBrowserTool.swift
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
import Bookmarks
import Foundation

/// Bookmarks a tab of the chat's window into a folder path, creating the folders it lacks. A page
/// has at most one bookmark, so one saved elsewhere is moved into the folder rather than duplicated.
@MainActor
final class BookmarkTabBrowserTool: BrowserTool {

    static let maxFolderDepth = 10
    static let maxFolderNameLength = 256

    /// Matches `AIChatBrowserToolsSubfeature.bookmarkTab`, which is how the catalog gates it.
    let name = "bookmarkTab"
    let permissionMode = BrowserToolPermissionMode.auto

    let inputSchema: JSONValue = [
        "type": "object",
        "properties": [
            "tabId": ["type": "string", "description": "Optional. Tab ID from listOpenTabs. Omit for the current tab."],
            "folder": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Optional. Folder names from the top level, e.g. [\"Travel\", \"Paris\"]. Missing folders are created. Omit for the default location."
            ]
        ]
    ]

    private struct Failure: Error {}

    private let windowControllersManager: WindowControllersManagerProtocol
    private let bookmarkManager: BookmarkManager

    init(windowControllersManager: WindowControllersManagerProtocol, bookmarkManager: BookmarkManager) {
        self.windowControllersManager = windowControllersManager
        self.bookmarkManager = bookmarkManager
    }

    func execute(arguments: JSONValue?, context: BrowserToolCallContext) async -> BrowserToolResult {
        guard !context.isBurner else { return .failure(.unavailable) }
        guard let folderPath = Self.folderPath(from: arguments) else { return .failure(.invalidArguments) }

        let tab: AnyTab
        switch BrowserToolTargetTab.resolve(tabIDArgument: arguments?["tabId"], context: context, in: windowControllersManager) {
        case .failure(let failure): return .failure(failure)
        case .resolved(let tabID, let collection):
            guard let resolvedTab = Self.tab(withID: tabID, in: collection) else { return .failure(.notFound) }
            tab = resolvedTab
        }
        guard tab.content.canBeBookmarked, let url = tab.content.userEditableUrl,
              let list = bookmarkManager.list else {
            return .failure(.unavailable)
        }

        do {
            let (folder, folderCreated) = try await folder(at: folderPath, in: list)
            let alreadyBookmarked = try await save(url, title: tab.title ?? url.host ?? url.absoluteString, in: folder)
            return .success([
                "tabId": .string(tab.uuid),
                "alreadyBookmarked": .bool(alreadyBookmarked),
                "folderCreated": .bool(folderCreated)
            ])
        } catch {
            return .failure(.unavailable)
        }
    }

    /// Whether the page was already bookmarked in `folder`; otherwise it ends up there.
    private func save(_ url: URL, title: String, in folder: BookmarkFolder?) async throws -> Bool {
        guard let existing = bookmarkManager.getBookmark(for: url) else {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let bookmark = bookmarkManager.makeBookmark(for: url, title: title, isFavorite: false, index: nil, parent: folder) { error in
                    continuation.resume(with: error.map { .failure($0) } ?? .success(()))
                }
                if bookmark == nil { continuation.resume(throwing: Failure()) }
            }
            return false
        }
        let rootID = BookmarkEntity.Constants.rootFolderID
        guard (existing.parentFolderUUID ?? rootID) != (folder?.id ?? rootID) else { return true }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            bookmarkManager.move(objectUUIDs: [existing.id], toIndex: nil,
                                 withinParentFolder: folder.map { .parent(uuid: $0.id) } ?? .root) { error in
                continuation.resume(with: error.map { .failure($0) } ?? .success(()))
            }
        }
        return false
    }

    /// The folder at `path`, nil for the top level, and whether any part of it had to be created.
    private func folder(at path: [String], in list: BookmarkList) async throws -> (BookmarkFolder?, Bool) {
        var folder: BookmarkFolder?
        var siblings = list.topLevelEntities.compactMap { $0 as? BookmarkFolder }
        var created = false
        for name in path {
            if let existing = siblings.first(where: { $0.title == name }) {
                folder = existing
                siblings = existing.childFolders
                continue
            }
            let parent = folder
            folder = try await withCheckedThrowingContinuation { continuation in
                bookmarkManager.makeFolder(named: name, parent: parent) { continuation.resume(with: $0) }
            }
            siblings = []
            created = true
        }
        return (folder, created)
    }

    private static func tab(withID tabID: TabIdentifier, in collection: TabCollectionViewModel) -> AnyTab? {
        switch collection.indexInAllTabs(where: { $0.uuid == tabID }) {
        case .pinned(let index): collection.pinnedTabsCollection?.tabs[safe: index]
        case .unpinned(let index): collection.tabCollection.tabs[safe: index]
        case .none: nil
        }
    }

    /// The folder names, empty when omitted, or nil when malformed.
    private static func folderPath(from arguments: JSONValue?) -> [String]? {
        guard let value = arguments?["folder"] else { return [] }
        guard let values = value.arrayValue, (1...maxFolderDepth).contains(values.count) else { return nil }
        let names = values.compactMap { value -> String? in
            guard let name = value.stringValue, (1...maxFolderNameLength).contains(name.unicodeScalars.count) else { return nil }
            return name
        }
        return names.count == values.count ? names : nil
    }
}
