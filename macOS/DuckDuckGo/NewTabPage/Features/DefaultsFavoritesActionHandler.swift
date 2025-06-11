//
//  DefaultsFavoritesActionHandler.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Combine
import NewTabPage

final class DefaultFavoritesActionsHandler: FavoritesActionsHandling {
    typealias Favorite = Bookmark

    let bookmarkManager: BookmarkManager

    init(bookmarkManager: BookmarkManager) {
        self.bookmarkManager = bookmarkManager
    }

    @MainActor
    func open(_ url: URL, sender: NewTabPage.LinkOpenSender, target: NewTabPage.LinkOpenTarget, in window: NSWindow?) {
        open(url, sender: sender, target: target, setBurner: nil, in: window)
    }

    @MainActor
    func open(_ url: URL, sender: LinkOpenSender, target: LinkOpenTarget, setBurner: Bool?, in window: NSWindow?) {
        NewTabPageLinkOpener.open(url, source: .bookmark, setBurner: setBurner, sender: sender, target: target, sourceWindow: window)
    }

    func copyLink(_ favorite: Bookmark) {
        favorite.copyUrlToPasteboard()
    }

    func removeFavorite(_ favorite: Bookmark) {
        favorite.isFavorite = false
        bookmarkManager.update(bookmark: favorite)
    }

    func deleteBookmark(for favorite: Bookmark) {
        bookmarkManager.remove(bookmark: favorite, undoManager: nil)
    }

    @MainActor
    func addNewFavorite(in window: NSWindow?) {
        guard let window else { return }
        BookmarksDialogViewFactory.makeAddFavoriteView(bookmarkManager: bookmarkManager).show(in: window)
    }

    @MainActor
    func edit(_ favorite: Bookmark, in window: NSWindow?) {
        guard let window else { return }
        BookmarksDialogViewFactory.makeEditBookmarkView(bookmark: favorite, bookmarkManager: bookmarkManager).show(in: window)
    }

    func move(_ bookmarkID: String, toIndex index: Int) {
        bookmarkManager.moveFavorites(with: [bookmarkID], toIndex: index) { _ in }
    }

}

extension Bookmark: NewTabPageFavorite {
    private enum Const {
        static let wwwPrefix = "www."
    }

    var etldPlusOne: String? {
        guard let domain = urlObject?.host else {
            return nil
        }
        return Application.appDelegate.tld.eTLDplus1(domain)?.dropping(prefix: Const.wwwPrefix)
    }
}
