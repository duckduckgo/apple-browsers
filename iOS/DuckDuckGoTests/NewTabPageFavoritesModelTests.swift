//
//  NewTabPageFavoritesModelTests.swift
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

import XCTest
import Combine
import Bookmarks
@testable import Core
@testable import DuckDuckGo

final class NewTabPageFavoritesModelTests: XCTestCase {
    private let favoriteDataSource = MockNewTabPageFavoriteDataSource()

    override func setUpWithError() throws {
        throw XCTSkip("Potentially flaky")

        try super.setUpWithError()
    }

    override func tearDown() {
        PixelFiringMock.tearDown()
    }

    func testReturnsAllFavoritesWhenCustomizationDisabled() {
        favoriteDataSource.favorites.append(contentsOf: Array(repeating: Favorite.stub(), count: 10))
        let sut = createSUT()
        
        XCTAssertEqual(sut.allFavorites.count, 10)
    }

    func testFiresPixelsOnFavoriteSelected() {
        let sut = createSUT()

        sut.favoriteSelected(Favorite(id: "", title: "", domain: "", urlObject: URL(string: "https://foo.bar")))

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.favoriteLaunchedNTP.name)
        XCTAssertEqual(PixelFiringMock.lastDailyPixelInfo?.pixelName, Pixel.Event.favoriteLaunchedNTPDaily.name)
    }

    func testFiresPixelOnFavoriteDeleted() {
        let favorite = Favorite.stub()
        favoriteDataSource.favorites = [favorite]

        let sut = createSUT()

        sut.deleteFavorite(favorite)

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.homeScreenDeleteFavorite.name)
    }

    func testFiresPixelOnFavoriteEdited() {
        let favorite = Favorite.stub()
        favoriteDataSource.favorites = [favorite]

        let sut = createSUT()

        sut.editFavorite(favorite)

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.homeScreenEditFavorite.name)
    }

    private func createSUT() -> FavoritesViewModel {
        FavoritesViewModel(favoriteDataSource: favoriteDataSource,
                           faviconLoader: MockFavoritesFaviconLoading(),
                           faviconsCache: MockFavoritesFaviconCaching(),
                           pixelFiring: PixelFiringMock.self,
                           dailyPixelFiring: PixelFiringMock.self)
    }
}

private final class MockNewTabPageFavoriteDataSource: NewTabPageFavoriteDataSource {
    var externalUpdates: AnyPublisher<Void, Never> = Empty().eraseToAnyPublisher()
    var favorites: [DuckDuckGo.Favorite] = []

    func moveFavorite(_ favorite: DuckDuckGo.Favorite, fromIndex: Int, toIndex: Int) { }
    func favorite(at index: Int) throws -> DuckDuckGo.Favorite? { nil }
    func removeFavorite(_ favorite: DuckDuckGo.Favorite) { }
    func bookmarkEntity(for favorite: DuckDuckGo.Favorite) -> Bookmarks.BookmarkEntity? {
        createStubBookmark()
    }

    private func createStubBookmark() -> BookmarkEntity {
        let bookmarksDB = MockBookmarksDatabase.make()
        let context = bookmarksDB.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let root = BookmarkUtils.fetchRootFolder(context)!
        return BookmarkEntity.makeBookmark(title: "foo", url: "", parent: root, context: context)
    }
}

private extension Favorite {
    static func stub() -> Favorite {
        Favorite(id: UUID().uuidString, title: "foo", domain: "bar")
    }
}

private final class MockFavoritesFaviconLoading: FavoritesFaviconLoading {
    func loadFavicon(for favorite: Favorite, size: CGFloat) async -> Favicon? {
        nil
    }

    func fakeFavicon(for favorite: Favorite, size: CGFloat) -> Favicon {
        Favicon(image: .init(), isUsingBorder: false, isFake: false)
    }

    func existingFavicon(for favorite: Favorite, size: CGFloat) -> Favicon? {
        nil
    }
}

private final class MockFavoritesFaviconCaching: FavoritesFaviconCaching {
    func populateFavicon(for domain: String, intoCache: FaviconsCacheType, fromCache: FaviconsCacheType?) {

    }
}
