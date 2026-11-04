//
//  MainMenuBookmarksSection.swift
//  DuckDuckGo
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

import UIKit

extension UIMenu.Identifier {
    static let bookmarks = UIMenu.Identifier("com.duckduckgo.bookmarks")
    static let bookmarksFavorites = UIMenu.Identifier("com.duckduckgo.bookmarks.favorites")
    static let bookmarksTree = UIMenu.Identifier("com.duckduckgo.bookmarks.tree")
}

/// The Bookmarks menu, with the favorites from the context and a placeholder for `BookmarksMenuTree`.
struct BookmarksMenuSection: MainMenuSection {
    var favicon: (URL) -> UIImage? = BookmarksMenuTree.loadFavicon

    func menu(in context: MainMenuSpec.Context) -> MainMenuSpec.Menu? {
        let favoriteItems = context.favorites.enumerated().map { index, favorite in
            var item = MainMenuSpec.item(.openBookmark, favorite.title, index < 9 ? String(index + 1) : nil, [.alternate, .command])
            item.argument = BookmarksMenuTree.argument(for: favorite, in: .bookmarksFavorites)
            return item
        }
        return MainMenuSpec.Menu(identifier: .bookmarks, items: [], placement: .insert(sibling: .window, position: .before), submenus: [
            MainMenuSpec.group("bookmarks.show", [MainMenuSpec.item(.showBookmarks, UserText.menuShowBookmarks, "k", [.shift, .command])]),
            MainMenuSpec.group("bookmarks.add", [MainMenuSpec.item(.addBookmark, UserText.keyCommandAddBookmark, "d", .command),
                                                 MainMenuSpec.item(.addFavorite, UserText.keyCommandAddFavorite, "d", [.control, .command])]),
            MainMenuSpec.group("bookmarks.files", [MainMenuSpec.item(.importBookmarks, UserText.menuImportBookmarks),
                                                   MainMenuSpec.item(.exportBookmarks, UserText.menuExportBookmarks)]),
            MainMenuSpec.Menu(identifier: .bookmarksFavorites, items: favoriteItems, title: UserText.menuFavorites),
            MainMenuSpec.Menu(identifier: .bookmarksTree, items: [], deferredContent: .bookmarksTree)
        ], title: UserText.menuBookmarks)
    }

    /// Adds favicons to the favorites, which only menu building needs.
    func children(of elements: [UIMenuElement], systemElements: [UIMenuElement]) -> [UIMenuElement] {
        elements.map { element in
            guard let menu = element as? UIMenu, menu.identifier == .bookmarksFavorites else { return element }
            return menu.replacingChildren(menu.children.map { child in
                if let command = child as? UICommand {
                    command.image = BookmarksMenuTree.bookmarkURL(from: command).flatMap(favicon)
                }
                return child
            })
        }
    }
}

/// Fills the Bookmarks menu with the bookmarks tree, loading each folder when it opens.
struct BookmarksMenuTree: MainMenuDeferredContent {
    /// Children of the folder with the given ID, or of the root folder when the ID is `nil`.
    let children: (String?) -> [MainMenuBookmarkEntry]
    var favicon: (URL) -> UIImage? = Self.loadFavicon

    func makeElement() -> UIDeferredMenuElement {
        makeFolder(withID: nil)
    }

    private func makeFolder(withID folderID: String?) -> UIDeferredMenuElement {
        UIDeferredMenuElement.uncached { completion in
            DispatchQueue.main.async {
                completion(children(folderID).map { entry -> UIMenuElement in
                    switch entry {
                    case .bookmark(let bookmark):
                        return UICommand(title: bookmark.title, image: favicon(bookmark.url),
                                         action: MainMenuCommand.openBookmark.action,
                                         propertyList: Self.argument(for: bookmark, in: .bookmarksTree))
                    case .folder(let title, let id):
                        return UIMenu(title: title, children: [makeFolder(withID: id)])
                    }
                })
            }
        }
    }

    static func loadFavicon(for url: URL) -> UIImage? {
        FaviconsHelper.loadFaviconSync(forDomain: url.host, usingCache: .fireproof, useFakeFavicon: true).image
    }

    /// Identifies a bookmark command uniquely across menus, since UIKit rejects commands sharing an action and property list.
    static func argument(for bookmark: MainMenuBookmark, in menu: UIMenu.Identifier) -> String {
        [menu.rawValue, bookmark.id, bookmark.url.absoluteString].joined(separator: " ")
    }

    /// The URL of a command made with `argument(for:in:)`.
    static func bookmarkURL(from command: UICommand) -> URL? {
        // An absolute URL string never contains a space, so it is everything after the second one.
        guard let argument = command.propertyList as? String else { return nil }
        let parts = argument.split(separator: " ", maxSplits: 2)
        return parts.count == 3 ? URL(string: String(parts[2])) : nil
    }
}
