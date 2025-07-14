//
//  FavoritesImportProcessor.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

enum FavoritesImportProcessor {

    /// Merges imported bookmarks with the provided array of favorites, marking bookmarks with matching URLs as favorites.
    /// Any favorites not matching existing bookmarks will be added to the bookmark bar.
    static func mergeBookmarksAndFavorites(bookmarks: inout ImportedBookmarks, favorites: [ImportedBookmarks.BookmarkOrFolder]) {
        guard !favorites.isEmpty else { return }

        let favoriteUrlIndices = favorites.reduce(into: [String: Int]()) { result, favorite in
            guard let urlString = favorite.url?.nakedString else { return }
            result[urlString] = favorite.favoritesIndex
        }
        guard !favoriteUrlIndices.isEmpty else { return }

        var foundFavoriteUrls: Set<String> = []

        // Recursively process bookmarks to mark matching URLs as favorites
        func processMaybeFolder(_ folder: inout ImportedBookmarks.BookmarkOrFolder?) {
            if folder != nil {
                processFolder(&folder!)
            }
        }
        func processFolder(_ folder: inout ImportedBookmarks.BookmarkOrFolder) {
            assert(folder.isFolder, "Folder must be passed")
            if folder.children != nil {
                processFolderChildren(&folder.children!)
            }
        }
        func processFolderChildren(_ items: inout [ImportedBookmarks.BookmarkOrFolder]) {
            for idx in items.indices {
                guard !items[idx].isFolder else {
                    processFolder(&items[idx])
                    continue
                }
                guard let urlString = items[idx].url?.nakedString else { continue }
                if let favoriteIndex = favoriteUrlIndices[urlString] {
                    items[idx].isDDGFavorite = true
                    items[idx].favoritesIndex = favoriteIndex
                    foundFavoriteUrls.insert(urlString)
                }
            }
        }
        processMaybeFolder(&bookmarks.topLevelFolders.bookmarkBar)
        processMaybeFolder(&bookmarks.topLevelFolders.otherBookmarks)
        processMaybeFolder(&bookmarks.topLevelFolders.syncedBookmarks)

        // Create bookmarks objects for favorite shortcuts that don't have matching bookmarks and add them to bookmark bar
        let uniqueShortcuts = favorites.filter { !foundFavoriteUrls.contains($0.url?.nakedString ?? "") }
        bookmarks.topLevelFolders.bookmarkBar?.children?.append(contentsOf: uniqueShortcuts) ?? {
            bookmarks.topLevelFolders.bookmarkBar = .folder(name: bookmarks.topLevelFolders.bookmarkBar?.name ?? "", children: uniqueShortcuts)
        }()
    }
}
