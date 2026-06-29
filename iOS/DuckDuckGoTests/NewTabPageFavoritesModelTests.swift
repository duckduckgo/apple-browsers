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
import CoreData
import Common
import Persistence
@testable import Core
@testable import DuckDuckGo

final class NewTabPageFavoritesModelTests: XCTestCase {
    private let favoriteDataSource = MockNewTabPageFavoriteDataSource()

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

    func testFiresPixelsOnFavoriteSelectedInFocussedState() {
        let sut = createSUT(isFocussedState: true)

        sut.favoriteSelected(Favorite(id: "", title: "", domain: "", urlObject: URL(string: "https://foo.bar")))

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.favoriteLaunchedWebsite.name)
        XCTAssertNil(PixelFiringMock.lastDailyPixelInfo?.pixelName)
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

    private func createSUT(isFocussedState: Bool = false) -> FavoritesViewModel {
        FavoritesViewModel(isFocussedState: isFocussedState,
                           favoriteDataSource: favoriteDataSource,
                           faviconLoader: MockFavoritesFaviconLoading(),
                           faviconsCache: MockFavoritesFaviconCaching(),
                           pixelFiring: PixelFiringMock.self,
                           dailyPixelFiring: PixelFiringMock.self)
    }

    // MARK: - Reordering (regression for m_d_favorites_list_index_not_matching_bookmark)

    // These exercise the real model -> adapter -> view model stack, because the bug only appears
    // when the adapter forwards the model's in-process `localUpdates` back into the originating
    // view model (added in 7.225), making `updateData()` re-enter during `moveFavorites`.

    func testReorderingFavoriteKeepsInMemoryListInSyncWithModel() throws {
        let env = try makeReorderEnvironment()
        defer { try? env.db.tearDown(deleteStores: true) }

        XCTAssertEqual(env.sut.allFavorites.map(\.title), BasicBookmarksStructure.favoriteTitles)

        env.sut.moveFavorites(from: IndexSet(integer: 0), to: 2)

        // The in-memory list must match the persisted order. Before the fix the move was applied
        // twice — once by the re-entrant model update and again by the manual `allFavorites.move(...)`
        // — leaving the in-memory list permanently out of step with Core Data.
        XCTAssertEqual(env.sut.allFavorites.map(\.id), env.adapter.favorites.map(\.id))
        XCTAssertFalse(env.recorder.events.contains(.favoritesListIndexNotMatchingBookmark))
    }

    func testRepeatedReorderingDoesNotFireIndexMismatch() throws {
        let env = try makeReorderEnvironment()
        defer { try? env.db.tearDown(deleteStores: true) }

        env.sut.moveFavorites(from: IndexSet(integer: 0), to: 2)
        env.sut.moveFavorites(from: IndexSet(integer: 0), to: 2)

        XCTAssertFalse(env.recorder.events.contains(.favoritesListIndexNotMatchingBookmark),
                       "Reordering favorites desynced the in-memory list from the model, firing favoritesListIndexNotMatchingBookmark")
    }

    private typealias ReorderEnvironment = (
        sut: FavoritesViewModel,
        adapter: FavoritesListInteractingAdapter,
        db: CoreDataDatabase,
        recorder: BookmarksModelErrorRecorder
    )

    private func makeReorderEnvironment() throws -> ReorderEnvironment {
        let managedObjectModel = try XCTUnwrap(CoreDataDatabase.loadModel(from: Bookmarks.bundle, named: "BookmarksModel"))
        let db = CoreDataDatabase(name: "Test", containerLocation: tempDBDir(), model: managedObjectModel)
        db.loadStore()
        let context = db.makeContext(concurrencyType: .mainQueueConcurrencyType, name: "TestContext")
        BasicBookmarksStructure.populateDB(context: context)

        let recorder = BookmarksModelErrorRecorder()
        let model = FavoritesListViewModel(
            bookmarksDatabase: db,
            errorEvents: .init(mapping: { event, _, _, _ in
                recorder.events.append(event)
            }),
            favoritesDisplayMode: .displayNative(.mobile))
        let adapter = FavoritesListInteractingAdapter(favoritesListInteracting: model, appSettings: AppSettingsMock())
        let sut = FavoritesViewModel(isFocussedState: false,
                                     favoriteDataSource: adapter,
                                     faviconLoader: MockFavoritesFaviconLoading(),
                                     faviconsCache: MockFavoritesFaviconCaching(),
                                     pixelFiring: PixelFiringMock.self,
                                     dailyPixelFiring: PixelFiringMock.self)
        // `adapter` retains `model`, keeping the Core Data stack alive for the test's lifetime.
        return (sut, adapter, db, recorder)
    }
}

private final class BookmarksModelErrorRecorder {
    var events: [BookmarksModelError] = []
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
