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

enum FavoritesImportProcessor {

    /// Merges imported bookmarks with the provided array of favorites, marking bookmarks with matching URLs as favorites.
    /// Any favorites not matching existing bookmarks will be added to the bookmark bar.
    static func mergeBookmarksAndFavorites(bookmarks: ImportedBookmarks, favorites: [ImportedBookmarks.BookmarkOrFolder]) -> ImportedBookmarks {
        guard !favorites.isEmpty else {
            return bookmarks
        }

        // Recursively process bookmarks to mark matching URLs as favorites
        func processBookmarkOrFolder(_ item: ImportedBookmarks.BookmarkOrFolder) -> ImportedBookmarks.BookmarkOrFolder {
            var updatedItem = item

            if !item.isFolder, let shortcut = favorites.first(where: { $0.urlString == item.urlString }) {
                updatedItem.isDDGFavorite = true
                updatedItem.favoritesIndex = shortcut.favoritesIndex
            }

            if item.isFolder, let children = item.children {
                let updatedChildren = children.map(processBookmarkOrFolder)
                updatedItem = ImportedBookmarks.BookmarkOrFolder.folder(
                    name: item.name,
                    children: updatedChildren
                )
            }

            return updatedItem
        }

        let updatedBookmarkBar = bookmarks.topLevelFolders.bookmarkBar.map(processBookmarkOrFolder)
        let updatedOtherBookmarks = bookmarks.topLevelFolders.otherBookmarks.map(processBookmarkOrFolder)
        let updatedSyncedBookmarks = bookmarks.topLevelFolders.syncedBookmarks.map(processBookmarkOrFolder)

        // Find favorites that don't have matching bookmarks and add them to bookmark bar
        let existingBookmarkURLs = collectAllBookmarkURLs(from: bookmarks)
        let uniqueShortcuts = favorites.filter { shortcut in
            guard let urlString = shortcut.urlString else {
                return false
            }
            return !existingBookmarkURLs.contains(urlString)
        }
        let mergedBookmarkBar: ImportedBookmarks.BookmarkOrFolder? = {
            guard !uniqueShortcuts.isEmpty else {
                return updatedBookmarkBar
            }
            let existingChildren = updatedBookmarkBar?.children ?? []
            let newChildren = existingChildren + uniqueShortcuts
            return ImportedBookmarks.BookmarkOrFolder.folder(name: updatedBookmarkBar?.name ?? "",
                                                             children: newChildren)
        }()

        let updatedTopLevelFolders = ImportedBookmarks.TopLevelFolders(
            bookmarkBar: mergedBookmarkBar,
            otherBookmarks: updatedOtherBookmarks,
            syncedBookmarks: updatedSyncedBookmarks
        )

        return ImportedBookmarks(topLevelFolders: updatedTopLevelFolders)
    }

    private static func collectAllBookmarkURLs(from bookmarks: ImportedBookmarks) -> Set<String> {
        var urls = Set<String>()

        func collectFromFolder(_ folder: ImportedBookmarks.BookmarkOrFolder) {
            if let urlString = folder.urlString {
                urls.insert(urlString)
            }

            folder.children?.forEach(collectFromFolder)
        }

        bookmarks.topLevelFolders.bookmarkBar.map(collectFromFolder)
        bookmarks.topLevelFolders.otherBookmarks.map(collectFromFolder)
        bookmarks.topLevelFolders.syncedBookmarks.map(collectFromFolder)

        return urls
    }
}
