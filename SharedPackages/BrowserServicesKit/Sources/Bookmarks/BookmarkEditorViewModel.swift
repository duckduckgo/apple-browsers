//
//  BookmarkEditorViewModel.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

public class BookmarkEditorViewModel: ObservableObject {

    public struct Location {

        public let bookmark: BookmarkEntity
        public let depth: Int
    }

    let context: NSManagedObjectContext
    public let favoritesDisplayMode: FavoritesDisplayMode

    @Published public var bookmark: BookmarkEntity
    @Published public var locations = [Location]()

    lazy var favoritesFolder: BookmarkEntity! = BookmarkUtils.fetchFavoritesFolder(
        withUUID: favoritesDisplayMode.displayedFolder.rawValue,
        in: context
    )

    private var observer: NSObjectProtocol?
    private let subject = PassthroughSubject<Void, Never>()
    public var externalUpdates: AnyPublisher<Void, Never>

    private let errorEvents: EventMapping<BookmarksModelError>?

    public var canSave: Bool {
        let titleOK = bookmark.title?.trimmingWhitespace().count ?? 0 > 0
        let urlOK = bookmark.isFolder ? true : bookmark.urlObject != nil
        return titleOK && urlOK
    }

    public var canAddNewFolder: Bool {
        !bookmark.isFolder
    }

    public var isNew: Bool {
        bookmark.isInserted
    }

    public init(editingEntityID: NSManagedObjectID,
                bookmarksDatabase: CoreDataDatabase,
                favoritesDisplayMode: FavoritesDisplayMode,
                errorEvents: EventMapping<BookmarksModelError>?) {

        externalUpdates = subject.eraseToAnyPublisher()
        self.errorEvents = errorEvents
        self.context = bookmarksDatabase.makeContext(concurrencyType: .mainQueueConcurrencyType)
        self.favoritesDisplayMode = favoritesDisplayMode

        guard let entity = context.object(with: editingEntityID) as? BookmarkEntity else {
            // For sync, this is valid scenario in case of a timing issue
            fatalError("Failed to load entity when expected")
        }
        self.bookmark = entity

        refresh()
        registerForChanges()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    public init(creatingFolderWithParentID parentFolderID: NSManagedObjectID?,
                bookmarksDatabase: CoreDataDatabase,
                favoritesDisplayMode: FavoritesDisplayMode,
                errorEvents: EventMapping<BookmarksModelError>?) {

        externalUpdates = subject.eraseToAnyPublisher()
        self.errorEvents = errorEvents
        self.context = bookmarksDatabase.makeContext(concurrencyType: .mainQueueConcurrencyType)
        self.favoritesDisplayMode = favoritesDisplayMode

        let parent: BookmarkEntity?
        if let parentFolderID = parentFolderID {
            parent = context.object(with: parentFolderID) as? BookmarkEntity
        } else {
            parent = BookmarkUtils.fetchRootFolder(context)
        }
        assert(parent != nil)

        // We don't support creating bookmarks from scratch at this time, so it must be a folder
        self.bookmark = BookmarkEntity.makeFolder(title: "",
                                                  parent: parent!,
                                                  context: context)

        refresh()
        registerForChanges()
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

                if let bookmark = self?.bookmark, !bookmark.isInserted {
                    self?.context.refresh(bookmark, mergeChanges: true)
                }

                self?.refresh()
                self?.subject.send()
            }
        }
    }

    public func reloadData() {
        context.perform {
            self.refresh()
        }
    }

    public func refresh() {
        guard let rootFolder = BookmarkUtils.fetchRootFolder(context) else {
            errorEvents?.fire(.fetchingRootItemFailed(.edit))
            locations = []
            return
        }
        var locations = [Location(bookmark: rootFolder, depth: 0)]

        func descendInto(_ folders: [BookmarkEntity], depth: Int) {
            folders.forEach { entity in
                if entity.isFolder,
                    entity.uuid != bookmark.uuid {

                    locations.append(Location(bookmark: entity, depth: depth))
                    descendInto(entity.childrenArray, depth: depth + 1)
                }
            }
        }

        descendInto(rootFolder.childrenArray, depth: 1)

        self.locations = locations
    }

    public func selectLocationAtIndex(_ index: Int) {
        guard locations.indices.contains(index) else {
            errorEvents?.fire(.indexOutOfRange(.edit))
            return
        }
        let newParent = locations[index].bookmark
        bookmark.parent = newParent
        refresh()
    }

    public func isSelected(_ folder: BookmarkEntity?) -> Bool {
        return bookmark.parent?.uuid == (folder?.uuid ?? BookmarkEntity.Constants.rootFolderID)
    }

    public func removeFromFavorites() {
        assert(bookmark.isFavorite(on: favoritesDisplayMode.displayedFolder))
        bookmark.removeFromFavorites(with: favoritesDisplayMode)
    }

    public func addToFavorites() {
        assert(!bookmark.isFavorite(on: favoritesDisplayMode.displayedFolder))
        bookmark.addToFavorites(with: favoritesDisplayMode, in: context)
    }

    public func setParentWithID(_ parentID: NSManagedObjectID) {
        guard let parent = (try? context.existingObject(with: parentID)) as? BookmarkEntity else {
            errorEvents?.fire(.editorNewParentMissing)
            return
        }
        bookmark.parent = parent
    }

    public func save() {
        do {
            try context.save()
        } catch {
            errorEvents?.fire(.saveFailed(.edit), error: error)
        }
    }
}
