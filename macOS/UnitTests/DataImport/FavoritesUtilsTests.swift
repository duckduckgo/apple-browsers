//
//  FavoritesUtilsTests.swift
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

import Testing
@testable import DuckDuckGo_Privacy_Browser

struct FavoritesUtilsTests {

    @Test func testMergeBookmarksAndFavorites_ReturnsBookmarks_WhenFavoritesEmpty() {
        let bookmarks = createMockImportedBookmarks()
        let favorites: [ImportedBookmarks.BookmarkOrFolder] = []

        let result = FavoritesUtils.mergeBookmarksAndFavorites(bookmarks: bookmarks, favorites: favorites)

        #expect(result == bookmarks)
    }

    @Test func testMergeBookmarksAndFavorites_MarksExpectedBookmarksAsFavorites() throws {
        let bookmarks = createMockImportedBookmarks()
        let favorite = ImportedBookmarks.BookmarkOrFolder(name: "DuckDuckGo", type: .bookmark, urlString: "https://duckduckgo.com", children: nil)

        // Check initial state
        try #require(bookmarks.numberOfBookmarks == 2)
        let bookmarkBarBookmark = try #require(bookmarks.topLevelFolders.bookmarkBar?.children?.first)
        try #require(bookmarkBarBookmark.isDDGFavorite == false)

        let result = FavoritesUtils.mergeBookmarksAndFavorites(bookmarks: bookmarks, favorites: [favorite])

        #expect(result.numberOfBookmarks == 2)
        let bookmarkBarBookmarkResult = try #require(result.topLevelFolders.bookmarkBar?.children?.first)
        #expect(bookmarkBarBookmarkResult.isDDGFavorite == true)
    }

    @Test func testMergeBookmarksAndFavorites_AddsUniqueFavoritesToBookmarkBar() throws {
        let bookmarks = createMockImportedBookmarks()
        let favorite1 = ImportedBookmarks.BookmarkOrFolder(name: "DuckDuckGo", type: .bookmark, urlString: "https://duckduckgo.com", children: nil)
        let favorite2 = ImportedBookmarks.BookmarkOrFolder(name: "Duck.ai", type: .bookmark, urlString: "https://duck.ai", children: nil)

        // Check initial state
        try #require(bookmarks.numberOfBookmarks == 2)
        try #require(bookmarks.topLevelFolders.bookmarkBar?.children?.count == 2)

        let result = FavoritesUtils.mergeBookmarksAndFavorites(bookmarks: bookmarks, favorites: [favorite1, favorite2])

        #expect(result.numberOfBookmarks == 3)
        #expect(result.topLevelFolders.bookmarkBar?.children?.count == 3)
    }

    private func createMockImportedBookmarks() -> ImportedBookmarks {
        let bookmark1 = ImportedBookmarks.BookmarkOrFolder(name: "DuckDuckGo", type: .bookmark, urlString: "https://duckduckgo.com", children: nil)
        let bookmark2 = ImportedBookmarks.BookmarkOrFolder(name: "Duck", type: .bookmark, urlString: "https://duck.com", children: nil)
        let folder1 = ImportedBookmarks.BookmarkOrFolder(name: "Folder", type: .folder, urlString: nil, children: [bookmark2])

        let bookmarkBar = ImportedBookmarks.BookmarkOrFolder(name: "Bookmark Bar", type: .folder, urlString: nil, children: [bookmark1, folder1])
        let otherBookmarks = ImportedBookmarks.BookmarkOrFolder(name: "Other Bookmarks", type: .folder, urlString: nil, children: [])

        let topLevelFolders = ImportedBookmarks.TopLevelFolders(bookmarkBar: bookmarkBar, otherBookmarks: otherBookmarks, syncedBookmarks: nil)

        return ImportedBookmarks(topLevelFolders: topLevelFolders)
    }

}
