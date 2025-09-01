//
//  FavoritesViewModel.swift
//  DuckDuckGo
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

import Foundation
import Bookmarks
import Combine
import SwiftUI
import Core
import WidgetKit

protocol NewTabPageFavoriteDataSource {
    var externalUpdates: AnyPublisher<Void, Never> { get }
    var favorites: [Favorite] { get }

    func moveFavorite(_ favorite: Favorite,
                      fromIndex: Int,
                      toIndex: Int)

    func bookmarkEntity(for favorite: Favorite) -> BookmarkEntity?
    func favorite(at index: Int) throws -> Favorite?
    func removeFavorite(_ favorite: Favorite)
}

protocol FavoritesFaviconCaching {
    func populateFavicon(for domain: String, intoCache: FaviconsCacheType, fromCache: FaviconsCacheType?)
}

class FavoritesViewModel: ObservableObject {

    @Published private(set) var allFavorites: [Favorite] = []
    @Published var canEditFavorites = true

    // In memory only so that when settings is dismissed we can show the prompt.
    //  Missing icons will trigger the prompt from elsewhere too so we don't need to persist this.
    private(set) var hasMissingIcons = false

    private(set) var faviconLoader: FavoritesFaviconLoading?

    private var cancellables = Set<AnyCancellable>()

    private let favoriteDataSource: NewTabPageFavoriteDataSource
    private let faviconsCache: FavoritesFaviconCaching
    private let pixelFiring: PixelFiring.Type
    private let dailyPixelFiring: DailyPixelFiring.Type
   
    var isEmpty: Bool {
        allFavorites.isEmpty
    }

    init(favoriteDataSource: NewTabPageFavoriteDataSource,
         faviconLoader: FavoritesFaviconLoading,
         faviconsCache: FavoritesFaviconCaching = Favicons.shared,
         pixelFiring: PixelFiring.Type = Pixel.self,
         dailyPixelFiring: DailyPixelFiring.Type = DailyPixel.self) {
        self.favoriteDataSource = favoriteDataSource
        self.pixelFiring = pixelFiring
        self.dailyPixelFiring = dailyPixelFiring
        self.faviconsCache = faviconsCache

        self.faviconLoader = MissingFaviconWrapper(loader: faviconLoader, onFaviconMissing: { [weak self] in
            guard let self else { return }

            await MainActor.run {
                self.faviconMissing()
            }
        })
        
        favoriteDataSource.externalUpdates.sink { [weak self] _ in
            self?.updateData()
        }.store(in: &cancellables)

        updateData()
    }

    // MARK: - External actions

    var onFaviconMissing: () -> Void = {}
    func faviconMissing() {
        hasMissingIcons = true
        onFaviconMissing()
    }

    var onFavoriteURLSelected: ((BookmarkEntity) -> Void)?
    func favoriteSelected(_ favorite: Favorite) {
        guard let url = favorite.urlObject else { return }

        pixelFiring.fire(.favoriteLaunchedNTP, withAdditionalParameters: [:])
        dailyPixelFiring.fireDaily(.favoriteLaunchedNTPDaily)
        if let host = url.host {
            faviconsCache.populateFavicon(for: host, intoCache: .fireproof, fromCache: .tabs)
        }

        guard let entity = favoriteDataSource.bookmarkEntity(for: favorite) else {
            return
        }

        onFavoriteURLSelected?(entity)
    }

    var onFavoriteDeleted: ((BookmarkEntity) -> Void)?
    func deleteFavorite(_ favorite: Favorite) {
        guard let entity = favoriteDataSource.bookmarkEntity(for: favorite) else { return }

        pixelFiring.fire(.homeScreenDeleteFavorite, withAdditionalParameters: [:])

        favoriteDataSource.removeFavorite(favorite)

        WidgetCenter.shared.reloadAllTimelines()
        updateData()

        onFavoriteDeleted?(entity)
    }

    var onFavoriteEdit: ((BookmarkEntity) -> Void)?
    func editFavorite(_ favorite: Favorite) {
        guard let entity = favoriteDataSource.bookmarkEntity(for: favorite) else { return }

        pixelFiring.fire(.homeScreenEditFavorite, withAdditionalParameters: [:])

        onFavoriteEdit?(entity)
    }

    func moveFavorites(from indexSet: IndexSet, to index: Int) {
        guard indexSet.count == 1,
              let fromIndex = indexSet.first else { return }

        let favorite = allFavorites[fromIndex]

        favoriteDataSource.moveFavorite(favorite, fromIndex: fromIndex, toIndex: index)
        allFavorites.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: index)
    }

    // MARK: -

    private func updateData() {
        allFavorites = favoriteDataSource.favorites
    }
}

enum FavoriteMappingError: Error {
    case missingUUID
}

private final class MissingFaviconWrapper: FavoritesFaviconLoading {
    let loader: FavoritesFaviconLoading

    private(set) var onFaviconMissing: (() async -> Void)

    init(loader: FavoritesFaviconLoading, onFaviconMissing: @escaping (() async -> Void)) {
        self.onFaviconMissing = onFaviconMissing
        self.loader = loader
    }

    func loadFavicon(for favorite: Favorite, size: CGFloat) async -> Favicon? {
        let favicon = await loader.loadFavicon(for: favorite, size: size)

        if favicon == nil {
            await onFaviconMissing()
        }

        return favicon
    }

    func fakeFavicon(for favorite: Favorite, size: CGFloat) -> Favicon {
        loader.fakeFavicon(for: favorite, size: size)
    }

    func existingFavicon(for favorite: Favorite, size: CGFloat) -> Favicon? {
        loader.existingFavicon(for: favorite, size: size)
    }
}

extension Favicons: FavoritesFaviconCaching {
    func populateFavicon(for domain: String, intoCache: FaviconsCacheType, fromCache: FaviconsCacheType?) {
        loadFavicon(forDomain: domain, intoCache: intoCache, fromCache: fromCache)
    }
}
