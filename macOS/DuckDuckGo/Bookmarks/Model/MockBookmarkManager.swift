//
//  MockBookmarkManager.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
#if DEBUG
import Bookmarks
import BrowserServicesKit
import Foundation

final class MockBookmarkManager: BookmarkManager, URLFavoriteStatusProviding, RecentActivityFavoritesHandling {

    var bookmarksReturnedForSearch = [BaseBookmarkEntity]()
    var wasSearchByQueryCalled = false
    var isLoading = false

    init(bookmarksReturnedForSearch: [BaseBookmarkEntity] = [BaseBookmarkEntity](), wasSearchByQueryCalled: Bool = false, isUrlBookmarked: Bool = false, removeBookmarkCalled: Bool = false, removeFolderCalled: Bool = false, removeObjectsCalled: [String]? = nil, updateBookmarkCalled: Bookmark? = nil, moveObjectsCalled: MoveArgs? = nil, list: BookmarkList? = nil, sortMode: BookmarksSortMode = .manual) {
        self.bookmarksReturnedForSearch = bookmarksReturnedForSearch
        self.wasSearchByQueryCalled = wasSearchByQueryCalled
        self.isUrlBookmarked = isUrlBookmarked
        self.removeBookmarkCalled = removeBookmarkCalled
        self.removeFolderCalled = removeFolderCalled
        self.removeObjectsCalled = removeObjectsCalled
        self.updateBookmarkCalled = updateBookmarkCalled
        self.moveObjectsCalled = moveObjectsCalled
        self.list = list
        self.sortMode = sortMode
    }

    func isUrlFavorited(url: URL) -> Bool {
        return false
    }

    func getFavorite(for url: URL) -> Bookmark? {
        nil
    }

    func markAsFavorite(_ bookmark: Bookmark) {}
    func unmarkAsFavorite(_ bookmark: Bookmark) {}
    func addNewFavorite(for url: URL) {}

    var isUrlBookmarked = false
    func isUrlBookmarked(url: URL) -> Bool {
        return isUrlBookmarked
    }

    var isAnyUrlVariantBookmarked = false
    func isAnyUrlVariantBookmarked(url: URL) -> Bool {
        return isAnyUrlVariantBookmarked
    }

    func allHosts() -> Set<String> {
        return []
    }

    func getBookmark(for url: URL) -> Bookmark? {
        return nil
    }

    func getBookmark(forUrl url: String) -> Bookmark? {
        return nil
    }

    func getBookmark(forVariantUrl url: URL) -> Bookmark? {
        return nil
    }

    func getBookmarkFolder(withId id: String) -> BookmarkFolder? {
        return nil
    }

    func makeBookmark(for url: URL, title: String, isFavorite: Bool, index: Int?, parent: BookmarkFolder?) -> Bookmark? {
        return nil
    }

    func makeBookmarks(for websitesInfo: [WebsiteInfo], inNewFolderNamed folderName: String?, withinParentFolder parent: ParentFolderType) {}

    func makeFolder(named title: String, parent: BookmarkFolder?, completion: @escaping (Result<BookmarkFolder, Error>) -> Void) {}

    var removeBookmarkCalled = false
    func remove(bookmark: Bookmark, undoManager: UndoManager?) {
        removeBookmarkCalled = true
    }

    var removeFolderCalled = false
    func remove(folder: BookmarkFolder, undoManager: UndoManager?) {
        removeFolderCalled = true
    }

    var removeObjectsCalled: [String]?
    func remove(objectsWithUUIDs uuids: [String], undoManager: UndoManager?) {
        removeObjectsCalled = uuids
    }

    var updateBookmarkCalled: Bookmark?
    func update(bookmark: Bookmark) {
        updateBookmarkCalled = bookmark
    }

    func update(bookmark: Bookmark, withURL url: URL, title: String, isFavorite: Bool) {}

    func update(folder: BookmarkFolder) {}

    func update(folder: BookmarkFolder, andMoveToParent parent: ParentFolderType) {}

    func updateUrl(of bookmark: Bookmark, to newUrl: URL) -> Bookmark? {
        return nil
    }

    func add(bookmark: Bookmark, to parent: BookmarkFolder?, completion: @escaping (Error?) -> Void) {}

    func add(objectsWithUUIDs uuids: [String], to parent: BookmarkFolder?, completion: @escaping (Error?) -> Void) {}

    func update(objectsWithUUIDs uuids: [String], update: @escaping (BaseBookmarkEntity) -> Void, completion: @escaping (Error?) -> Void) {}

    func canMoveObjectWithUUID(objectUUID uuid: String, to parent: BookmarkFolder) -> Bool {
        return false
    }

    struct MoveArgs: Equatable {
        var objectUUIDs: [String] = []
        var toIndex: Int?
        var withinParentFolder: ParentFolderType
    }
    var moveObjectsCalled: MoveArgs?
    func move(objectUUIDs: [String], toIndex: Int?, withinParentFolder: ParentFolderType, completion: @escaping (Error?) -> Void) {
        moveObjectsCalled = .init(objectUUIDs: objectUUIDs, toIndex: toIndex, withinParentFolder: withinParentFolder)
    }

    func moveFavorites(with objectUUIDs: [String], toIndex: Int?, completion: @escaping (Error?) -> Void) {}

    func importBookmarks(_ bookmarks: ImportedBookmarks, source: BookmarkImportSource, markRootBookmarksAsFavoritesByDefault: Bool = true, maxFavoritesCount: Int?) -> BookmarksImportSummary {
        BookmarksImportSummary(successful: 0, duplicates: 0, failed: 0)
    }

    func handleFavoritesAfterDisablingSync() {}

    @Published var list: BookmarkList?

    var listPublisher: Published<BookmarkList?>.Publisher { $list }

    func requestSync() {
    }

    func search(by query: String) -> [BaseBookmarkEntity] {
        wasSearchByQueryCalled = true
        return bookmarksReturnedForSearch
    }

    var sortModePublisher: Published<BookmarksSortMode>.Publisher { $sortMode }

    @Published var sortMode: BookmarksSortMode = .manual

    func restore(_ entities: [RestorableBookmarkEntity], undoManager: UndoManager) {}

    func resetBookmarks(completion: @escaping () -> Void) {}
}

extension MockBookmarkManager: HistoryViewBookmarksHandling {
    func addNewBookmarks(for websiteInfos: [WebsiteInfo]) {
        makeBookmarks(for: websiteInfos, inNewFolderNamed: nil, withinParentFolder: .root)
    }

    func addNewFavorite(for url: URL, title: String) {
        makeBookmark(for: url, title: title, isFavorite: true)
    }
}
#endif
