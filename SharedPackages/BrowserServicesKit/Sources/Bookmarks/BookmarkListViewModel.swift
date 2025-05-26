//
//  BookmarkListViewModel.swift
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
import Common
import CoreData
import Persistence

public class BookmarkListViewModel: BookmarkListInteracting, ObservableObject {

    public let currentFolder: BookmarkEntity?

    let context: NSManagedObjectContext
    public var favoritesDisplayMode: FavoritesDisplayMode {
        didSet {
            reloadData()
        }
    }

    public var bookmarks = [BookmarkEntity]()

    private var observer: NSObjectProtocol?
    private let subject = PassthroughSubject<Void, Never>()
    private let localSubject = PassthroughSubject<Void, Never>()
    public var externalUpdates: AnyPublisher<Void, Never>
    public var localUpdates: AnyPublisher<Void, Never>

    private let errorEvents: EventMapping<BookmarksModelError>?

    public init(bookmarksDatabase: CoreDataDatabase,
                parentID: NSManagedObjectID?,
                favoritesDisplayMode: FavoritesDisplayMode,
                errorEvents: EventMapping<BookmarksModelError>?) {
        self.externalUpdates = self.subject.eraseToAnyPublisher()
        self.localUpdates = self.localSubject.eraseToAnyPublisher()
        self.errorEvents = errorEvents
        self.context = bookmarksDatabase.makeContext(concurrencyType: .mainQueueConcurrencyType)
        self.favoritesDisplayMode = favoritesDisplayMode

        if let parentID = parentID {
            if let bookmark = (try? context.existingObject(with: parentID)) as? BookmarkEntity {
                if bookmark.isFolder {
                    self.currentFolder = bookmark
                } else {
                    errorEvents?.fire(.bookmarkFolderExpected)
                    self.currentFolder = BookmarkUtils.fetchRootFolder(context)
                }
            } else {
                // This is possible with Sync and specific timing.
                errorEvents?.fire(.bookmarksListMissingFolder)
                self.currentFolder = BookmarkUtils.fetchRootFolder(context)
            }
        } else {
            self.currentFolder = BookmarkUtils.fetchRootFolder(context)
        }

        self.bookmarks = fetchBookmarksInFolder(currentFolder)

        registerForChanges()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
    }

    public func createBookmark(
        title: String,
        url: String,
        folder: BookmarkEntity,
        folderIndex: Int,
        favoritesFoldersAndIndexes: [BookmarkEntity: Int]
    ) {
        let bookmark = BookmarkEntity.makeBookmark(title: title, url: url, parent: folder, context: context)
        if let addedIndex = folder.childrenArray.firstIndex(of: bookmark) {
            moveBookmark(bookmark, fromIndex: addedIndex, toIndex: folderIndex)
        }
        for (favoritesFolder, index) in favoritesFoldersAndIndexes {
            bookmark.addToFavorites(insertAt: index, favoritesRoot: favoritesFolder)
        }
        save()
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

    public func bookmark(at index: Int) -> BookmarkEntity? {
        guard bookmarks.indices.contains(index) else { return nil }
        return bookmarks[index]
    }

    public func toggleFavorite(_ bookmark: BookmarkEntity) {
        if bookmark.isFavorite(on: favoritesDisplayMode.displayedFolder) {
            bookmark.removeFromFavorites(with: favoritesDisplayMode)
        } else {
            bookmark.addToFavorites(with: favoritesDisplayMode, in: context)
        }
        save()
    }

    public func moveBookmark(_ bookmark: BookmarkEntity,
                             fromIndex: Int,
                             toIndex: Int) {
        let shouldIncludeOrphans = bookmark.parent?.uuid == BookmarkEntity.Constants.rootFolderID || bookmark.parent == nil
        if shouldIncludeOrphans {
            reattachOrphanedBookmarks(forMoving: bookmark, toIndex: toIndex)
        }

        guard let parentFolder = bookmark.parent else {
            errorEvents?.fire(.missingParent(.bookmark))
            return
        }

        let visibleChildren = parentFolder.childrenArray

        guard fromIndex < visibleChildren.count,
              toIndex < visibleChildren.count else {
            errorEvents?.fire(.indexOutOfRange(.bookmarks))
            return
        }

        guard visibleChildren[fromIndex] == bookmark else {
            errorEvents?.fire(.bookmarksListIndexNotMatchingBookmark)
            return
        }

        // Take into account bookmarks that are pending deletion
        let mutableChildrenSet = parentFolder.mutableOrderedSetValue(forKeyPath: #keyPath(BookmarkEntity.children))

        let actualFromIndex = mutableChildrenSet.index(of: bookmark)
        let actualToIndex = mutableChildrenSet.index(of: visibleChildren[toIndex])

        guard actualFromIndex != NSNotFound, actualToIndex != NSNotFound else {
            assertionFailure("Bookmark: position could not be determined")
            refresh()
            return
        }

        mutableChildrenSet.moveObjects(at: IndexSet(integer: actualFromIndex), to: actualToIndex)

        save()
        refresh()
    }

    private func reattachOrphanedBookmarks(forMoving bookmark: BookmarkEntity, toIndex: Int) {
        guard let rootFolder = BookmarkUtils.fetchRootFolder(context) else {
            return
        }

        let orphanedBookmarks = bookmarks.filter { $0.parent == nil }
        guard !orphanedBookmarks.isEmpty else {
            return
        }

        let orphanedBookmarksToAttachToRootFolder: [BookmarkEntity] = {
            let toIndexInOrphanedBookmarks = toIndex - rootFolder.childrenArray.count
            guard bookmark.parent == nil else {
                return toIndexInOrphanedBookmarks >= 0 ? Array(orphanedBookmarks.prefix(through: toIndexInOrphanedBookmarks)) : []
            }
            guard let bookmarkIndexInOrphans = orphanedBookmarks.firstIndex(where: { $0.uuid == bookmark.uuid }) else {
                return [bookmark]
            }
            return Array(orphanedBookmarks.prefix(through: max(toIndexInOrphanedBookmarks, bookmarkIndexInOrphans)))
        }()

        orphanedBookmarksToAttachToRootFolder.forEach { rootFolder.addToChildren($0) }
    }

    public func softDeleteBookmark(_ bookmark: BookmarkEntity) {
        if bookmark.parent == nil {
            BookmarkUtils.fetchRootFolder(context)?.addToChildren(bookmark)
        }
        guard bookmark.parent != nil else {
            errorEvents?.fire(.missingParent(.bookmark))
            return
        }

        bookmark.markPendingDeletion()

        save()
        refresh()
    }

    public func bookmark(for url: URL) -> BookmarkEntity? {
        BookmarkUtils.fetchBookmark(for: url, context: context)
    }

    public func reloadData() {
        context.performAndWait {
            self.refresh()
        }
    }

    private func refresh() {
        bookmarks = fetchBookmarksInFolder(currentFolder)
    }

    private func save() {
        do {
            try context.save()
            localSubject.send()
        } catch {
            context.rollback()
            errorEvents?.fire(.saveFailed(.bookmarks), error: error)
        }
    }

    // MARK: - Read

    public func countBookmarksForDomain(_ domain: String) -> Int {
        let count = countBookmarksForDomain(domain, inFolder: fetchRootBookmarksFolder())
        return count
    }

    private func countBookmarksForDomain(_ domain: String, inFolder folder: BookmarkEntity) -> Int {
        var count = 0
        folder.childrenArray.forEach { child in
            if child.isFolder {
                count += countBookmarksForDomain(domain, inFolder: child)
            } else if child.urlObject?.isPart(ofDomain: domain) == true {
                count += 1
            }
        }
        return count
    }

    public var totalBookmarksCount: Int {
        let countRequest = BookmarkEntity.fetchRequest()
        countRequest.predicate = NSPredicate(
            format: "%K == false && %K == NO && (%K == NO OR %K == nil)",
            #keyPath(BookmarkEntity.isFolder),
            #keyPath(BookmarkEntity.isPendingDeletion),
            #keyPath(BookmarkEntity.isStub), #keyPath(BookmarkEntity.isStub)
        )

        return (try? context.count(for: countRequest)) ?? 0
    }

    private func fetchRootBookmarksFolder() -> BookmarkEntity {
        return BookmarkUtils.fetchRootFolder(context)!
    }

    private func fetchBookmarksInRootFolder() -> [BookmarkEntity] {
        guard let root = BookmarkUtils.fetchRootFolder(context) else {
            errorEvents?.fire(.fetchingRootItemFailed(.bookmarks))
            return []
        }

        return root.childrenArray
    }

    public func fetchBookmarksInFolder(_ folder: BookmarkEntity?) -> [BookmarkEntity] {
        let shouldFetchRootFolder = folder == nil || folder?.uuid == BookmarkEntity.Constants.rootFolderID

        var folderBookmarks: [BookmarkEntity] = {
            if let folder = folder {
                return folder.childrenArray
            }
            return fetchBookmarksInRootFolder()
        }()

        if shouldFetchRootFolder {
            folderBookmarks += BookmarkUtils.fetchOrphanedEntities(context)
        }
        return folderBookmarks
    }

    public func bookmark(with id: NSManagedObjectID) -> BookmarkEntity? {
        return (try? context.existingObject(with: id)) as? BookmarkEntity
    }

}
