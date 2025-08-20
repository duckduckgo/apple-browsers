//
//  FavoritesImportProcessorTests.swift
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

struct FavoritesImportProcessorTests {

    @Test("Check if mergeBookmarksAndFavorites returns the provided bookmarks when no favorites are provided")
    func mergeBookmarksAndFavorites_ReturnsBookmarks_WhenFavoritesEmpty() {
        let initialBookmarks = createMockImportedBookmarks()
        var bookmarks = initialBookmarks

        FavoritesImportProcessor.mergeBookmarksAndFavorites(bookmarks: &bookmarks, favorites: [])

        #expect(initialBookmarks == bookmarks)
    }

    @Test("Check if mergeBookmarksAndFavorites marks the expected bookmarks as favorites")
    func mergeBookmarksAndFavorites_MarksExpectedBookmarksAsFavorites() throws {
        var bookmarks = createMockImportedBookmarks()
        let favorite = ImportedBookmarks.BookmarkOrFolder(name: "DuckDuckGo", type: .bookmark, urlString: "https://duckduckgo.com", children: nil, isDDGFavorite: true, favoritesIndex: 0)

        // Check initial state
        try #require(bookmarks.numberOfBookmarks == 3)
        let bookmarkBarBookmark = try #require(bookmarks.topLevelFolders.bookmarkBar?.children?.first)
        try #require(bookmarkBarBookmark.isDDGFavorite == false)

        FavoritesImportProcessor.mergeBookmarksAndFavorites(bookmarks: &bookmarks, favorites: [favorite])

        #expect(bookmarks.numberOfBookmarks == 3)
        let mergedBookmarkBarBookmark = try #require(bookmarks.topLevelFolders.bookmarkBar?.children?.first)
        #expect(mergedBookmarkBarBookmark.isDDGFavorite == true)
        let mergedOtherBookmarksBookmark = try #require(bookmarks.topLevelFolders.otherBookmarks?.children?.first)
        #expect(mergedOtherBookmarksBookmark.isDDGFavorite == false)
    }

    @Test("Check if mergeBookmarksAndFavorites adds unique favorites to the bookmark bar")
    func mergeBookmarksAndFavorites_AddsUniqueFavoritesToBookmarkBar() throws {
        var bookmarks = createMockImportedBookmarks()
        let exactDuplicateFavorite = ImportedBookmarks.BookmarkOrFolder(name: "DuckDuckGo", type: .bookmark, urlString: "https://duckduckgo.com", children: nil, isDDGFavorite: true, favoritesIndex: 0)
        let approxDuplicateFavorite = ImportedBookmarks.BookmarkOrFolder(name: "Duck", type: .bookmark, urlString: "http://www.duck.com/", children: nil, isDDGFavorite: true, favoritesIndex: 1)
        let uniqueFavorite = ImportedBookmarks.BookmarkOrFolder(name: "Duck.ai", type: .bookmark, urlString: "https://duck.ai", children: nil, isDDGFavorite: true, favoritesIndex: 2)

        // Check initial state
        try #require(bookmarks.numberOfBookmarks == 3)
        try #require(bookmarks.topLevelFolders.bookmarkBar?.children?.count == 2)

        FavoritesImportProcessor.mergeBookmarksAndFavorites(bookmarks: &bookmarks, favorites: [exactDuplicateFavorite, approxDuplicateFavorite, uniqueFavorite])

        #expect(bookmarks.numberOfBookmarks == 4)
        let bookmarkBarChildren = try #require(bookmarks.topLevelFolders.bookmarkBar?.children)
        #expect(bookmarkBarChildren.count == 3)
        #expect(bookmarkBarChildren.contains(approxDuplicateFavorite) == false)
        #expect(bookmarkBarChildren.contains(uniqueFavorite) == true)
    }

    private func createMockImportedBookmarks() -> ImportedBookmarks {
        let bookmark1 = ImportedBookmarks.BookmarkOrFolder(name: "DuckDuckGo", type: .bookmark, urlString: "https://duckduckgo.com", children: nil)
        let bookmark2 = ImportedBookmarks.BookmarkOrFolder(name: "Duck", type: .bookmark, urlString: "https://duck.com", children: nil)
        let folder1 = ImportedBookmarks.BookmarkOrFolder(name: "Folder", type: .folder, urlString: nil, children: [bookmark2])

        let bookmarkBar = ImportedBookmarks.BookmarkOrFolder(name: "Bookmark Bar", type: .folder, urlString: nil, children: [bookmark1, folder1])
        let otherBookmarks = ImportedBookmarks.BookmarkOrFolder(name: "Other Bookmarks", type: .folder, urlString: nil, children: [bookmark1])

        let topLevelFolders = ImportedBookmarks.TopLevelFolders(bookmarkBar: bookmarkBar, otherBookmarks: otherBookmarks, syncedBookmarks: nil)

        return ImportedBookmarks(topLevelFolders: topLevelFolders)
    }

}
