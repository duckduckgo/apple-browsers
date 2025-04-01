//
//  FavoriteListViewModel.swift
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

import Foundation
import Combine
import CoreData
import Persistence
import Common

public class FavoritesListViewModel: FavoritesListInteracting, ObservableObject {

    let context: NSManagedObjectContext

    public var favorites = [BookmarkEntity]()
    public var favoritesDisplayMode: FavoritesDisplayMode {
        didSet {
            _favoritesFolder = nil
            reloadData()
        }
    }

    private var observer: NSObjectProtocol?
    private let subject = PassthroughSubject<Void, Never>()
    private let localSubject = PassthroughSubject<Void, Never>()
    public var externalUpdates: AnyPublisher<Void, Never>
    public var localUpdates: AnyPublisher<Void, Never>

    private let errorEvents: EventMapping<BookmarksModelError>?

    private var _favoritesFolder: BookmarkEntity?
    private var favoriteFolder: BookmarkEntity? {
        if _favoritesFolder == nil {
            _favoritesFolder = BookmarkUtils.fetchFavoritesFolder(withUUID: favoritesDisplayMode.displayedFolder.rawValue, in: context)

            if _favoritesFolder == nil {
                errorEvents?.fire(.fetchingRootItemFailed(.favorites))
            }
        }
        return _favoritesFolder
    }

    public init(
        bookmarksDatabase: CoreDataDatabase,
        errorEvents: EventMapping<BookmarksModelError>?,
        favoritesDisplayMode: FavoritesDisplayMode
    ) {
        self.externalUpdates = self.subject.eraseToAnyPublisher()
        self.localUpdates = self.localSubject.eraseToAnyPublisher()
        self.favoritesDisplayMode = favoritesDisplayMode
        self.errorEvents = errorEvents

        self.context = bookmarksDatabase.makeContext(concurrencyType: .mainQueueConcurrencyType)
        refresh()
        registerForChanges()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    private func registerForChanges() {
        observer = NotificationCenter.default.addObserver(forName: NSManagedObjectContext.didSaveObjectsNotification,
                                                          object: nil,
                                                          queue: nil) { [weak self] notification in
            guard let otherContext = notification.object as? NSManagedObjectContext,
                  otherContext != self?.context,
            otherContext.persistentStoreCoordinator == self?.context.persistentStoreCoordinator else { return }

            self?.context.perform {
                self?.context.mergeChanges(fromContextDidSave: notification)
                self?.context.refreshAllObjects()
                self?.refresh()
                self?.subject.send()
            }
        }
    }

    public func reloadData() {
        context.performAndWait {
            self.refresh()
        }
    }

    private func refresh() {
        guard let favoriteFolder else {
            errorEvents?.fire(.fetchingRootItemFailed(.favorites))
            favorites = []
            return
        }

        readFavorites(with: favoriteFolder)
    }

    public func favorite(at index: Int) -> BookmarkEntity? {
        guard favorites.indices.contains(index) else {
            errorEvents?.fire(.indexOutOfRange(.favorites))
            return nil
        }

        return favorites[index]
    }

    public func removeFavorite(_ favorite: BookmarkEntity) {
        guard let favoriteFolder else {
            errorEvents?.fire(.fetchingRootItemFailed(.favorites))
            return
        }

        favorite.removeFromFavorites(with: favoritesDisplayMode)

        save()

        readFavorites(with: favoriteFolder)
    }

    public func moveFavorite(_ favorite: BookmarkEntity,
                             fromIndex: Int,
                             toIndex: Int) {
        guard let favoriteFolder else {
            errorEvents?.fire(.fetchingRootItemFailed(.favorites))
            return
        }

        let visibleChildren = favoriteFolder.favoritesArray

        guard fromIndex < visibleChildren.count,
              toIndex < visibleChildren.count else {
            errorEvents?.fire(.indexOutOfRange(.favorites))
            return
        }

        guard visibleChildren[fromIndex] == favorite else {
            errorEvents?.fire(.favoritesListIndexNotMatchingBookmark)
            return
        }

        // Take into account bookmarks that are pending deletion
        let mutableChildrenSet = favoriteFolder.mutableOrderedSetValue(forKeyPath: #keyPath(BookmarkEntity.favorites))

        let actualFromIndex = mutableChildrenSet.index(of: favorite)
        let actualToIndex = mutableChildrenSet.index(of: visibleChildren[toIndex])

        guard actualFromIndex != NSNotFound, actualToIndex != NSNotFound else {
            assertionFailure("Favorite: position could not be determined")
            refresh()
            return
        }

        mutableChildrenSet.moveObjects(at: IndexSet(integer: actualFromIndex), to: actualToIndex)

        save()

        readFavorites(with: favoriteFolder)
    }

    private func save() {
        do {
            try context.save()
            localSubject.send()
        } catch {
            context.rollback()
            errorEvents?.fire(.saveFailed(.favorites), error: error)
        }
    }

    private func readFavorites(with favoritesFolder: BookmarkEntity) {
        favorites = favoritesFolder.favoritesArray
    }
}
