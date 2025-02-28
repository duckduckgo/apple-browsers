//
//  BookmarksModel.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

import CoreData
import Combine

public protocol BookmarkStoring {

    var externalUpdates: AnyPublisher<Void, Never> { get }

    var localUpdates: AnyPublisher<Void, Never> { get }

    func reloadData()
}

public protocol BookmarkListInteracting: BookmarkStoring, AnyObject {

    var favoritesDisplayMode: FavoritesDisplayMode { get set }

    var currentFolder: BookmarkEntity? { get }
    var bookmarks: [BookmarkEntity] { get }
    var totalBookmarksCount: Int { get }

    func bookmark(at index: Int) -> BookmarkEntity?

    func bookmark(with id: NSManagedObjectID) -> BookmarkEntity?

    func toggleFavorite(_ bookmark: BookmarkEntity)

    func softDeleteBookmark(_ bookmark: BookmarkEntity)

    func moveBookmark(_ bookmark: BookmarkEntity,
                      fromIndex: Int,
                      toIndex: Int)

    func countBookmarksForDomain(_ domain: String) -> Int

    func createBookmark(title: String, url: String, folder: BookmarkEntity, folderIndex: Int, favoritesFoldersAndIndexes: [BookmarkEntity: Int])

    func bookmark(for url: URL) -> BookmarkEntity?

}

public protocol FavoritesListInteracting: BookmarkStoring, AnyObject {

    var favoritesDisplayMode: FavoritesDisplayMode { get set }

    var favorites: [BookmarkEntity] { get }

    func favorite(at index: Int) -> BookmarkEntity?

    func removeFavorite(_ favorite: BookmarkEntity)

    func moveFavorite(_ favorite: BookmarkEntity,
                      fromIndex: Int,
                      toIndex: Int)
}

public protocol MenuBookmarksInteracting {

    var favoritesDisplayMode: FavoritesDisplayMode { get set }

    func createOrToggleFavorite(title: String, url: URL)

    func createBookmark(title: String, url: URL)

    func favorite(for url: URL) -> BookmarkEntity?
    func bookmark(for url: URL) -> BookmarkEntity?
}
