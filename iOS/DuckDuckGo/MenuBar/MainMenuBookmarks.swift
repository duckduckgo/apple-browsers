//
//  MainMenuBookmarks.swift
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

import Bookmarks
import Combine
import CoreData
import Persistence

/// A bookmark shown in the iPad menu bar.
struct MainMenuBookmark: Equatable {
    let id: String
    let title: String
    let url: URL
}

/// A child of a bookmarks folder shown in the iPad menu bar.
enum MainMenuBookmarkEntry: Equatable {
    case bookmark(MainMenuBookmark)
    case folder(title: String, id: String)
}

/// Reads favorites and the bookmarks tree for the iPad menu bar.
final class MainMenuBookmarks {
    private let database: CoreDataDatabase
    private let appSettings: AppSettings
    private var cachedFavorites: [MainMenuBookmark]?
    private var cancellables = Set<AnyCancellable>()

    /// Emits on the main queue after bookmarks are saved, including by Sync, or the favorites display mode changes.
    let changes: AnyPublisher<Void, Never>

    init(database: CoreDataDatabase, appSettings: AppSettings, notificationCenter: NotificationCenter = .default) {
        self.database = database
        self.appSettings = appSettings
        let bookmarkSaves = notificationCenter.publisher(for: NSManagedObjectContext.didSaveObjectsNotification)
            .filter { notification in
                (notification.object as? NSManagedObjectContext)?.persistentStoreCoordinator === database.coordinator
            }
        let displayModeChanges = notificationCenter.publisher(for: AppUserDefaults.Notifications.favoritesDisplayModeChange)
        changes = bookmarkSaves.merge(with: displayModeChanges)
            .map { _ in }
            .receive(on: DispatchQueue.main)
            .share()
            .eraseToAnyPublisher()

        changes
            .sink { [weak self] in self?.cachedFavorites = nil }
            .store(in: &cancellables)
    }

    var favorites: [MainMenuBookmark] {
        if let cachedFavorites { return cachedFavorites }
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let favorites = BookmarkUtils.fetchFavoritesFolder(withUUID: appSettings.favoritesDisplayMode.displayedFolder.rawValue,
                                                           in: context)?.favoritesArray.compactMap(Self.bookmark) ?? []
        cachedFavorites = favorites
        return favorites
    }

    /// Children of the folder with the given ID, or of the root folder followed by orphaned bookmarks when the ID is `nil`.
    func children(ofFolderWithID folderID: String? = nil) -> [MainMenuBookmarkEntry] {
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        let folder: BookmarkEntity?
        if let folderID {
            let request = BookmarkEntity.fetchRequest()
            request.predicate = NSPredicate(format: "%K == %@", #keyPath(BookmarkEntity.uuid), folderID)
            folder = try? context.fetch(request).first
        } else {
            folder = BookmarkUtils.fetchRootFolder(context)
        }
        let entities = (folder?.childrenArray ?? []) + (folderID == nil ? BookmarkUtils.fetchOrphanedEntities(context) : [])
        return entities.compactMap { entity in
            if entity.isFolder, let id = entity.uuid {
                return .folder(title: entity.title ?? "", id: id)
            }
            return Self.bookmark(entity).map(MainMenuBookmarkEntry.bookmark)
        }
    }

    private static func bookmark(_ entity: BookmarkEntity) -> MainMenuBookmark? {
        guard let id = entity.uuid, let url = entity.urlObject else { return nil }
        let title = entity.title.flatMap { $0.isEmpty ? nil : $0 } ?? url.absoluteString
        return MainMenuBookmark(id: id, title: title, url: url)
    }
}
