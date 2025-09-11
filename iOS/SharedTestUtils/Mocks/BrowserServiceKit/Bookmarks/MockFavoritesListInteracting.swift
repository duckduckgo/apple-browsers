//
//  MockFavoritesListInteracting.swift
//  DuckDuckGo
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

import Bookmarks
import Combine
import Core
import Persistence
import BrowserServicesKit

class MockFavoritesListInteracting: FavoritesListInteracting {
    var favoritesDisplayMode: Bookmarks.FavoritesDisplayMode = .displayNative(.mobile)
    var favorites: [Bookmarks.BookmarkEntity] = []
    func favorite(at index: Int) -> Bookmarks.BookmarkEntity? {
        return nil
    }
    func removeFavorite(_ favorite: Bookmarks.BookmarkEntity) {}
    func moveFavorite(_ favorite: Bookmarks.BookmarkEntity, fromIndex: Int, toIndex: Int) {    }
    var externalUpdates: AnyPublisher<Void, Never> = Empty<Void, Never>().eraseToAnyPublisher()
    var localUpdates: AnyPublisher<Void, Never> = Empty<Void, Never>().eraseToAnyPublisher()
    func reloadData() {}
}
