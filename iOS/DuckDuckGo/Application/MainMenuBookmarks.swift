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
import CoreData
import Persistence

struct MainMenuBookmark: Equatable {
    let title: String
    let url: URL
}

enum MainMenuBookmarkEntry {
    case bookmark(MainMenuBookmark)
    case folder(title: String, id: String)
}

@MainActor
final class MainMenuBookmarks {
    private let database: CoreDataDatabase
    private let appSettings: AppSettings

    init(database: CoreDataDatabase, appSettings: AppSettings) {
        self.database = database
        self.appSettings = appSettings
    }

    var favorites: [MainMenuBookmark] {
        let context = database.makeContext(concurrencyType: .mainQueueConcurrencyType)
        return BookmarkUtils.fetchFavoritesFolder(withUUID: appSettings.favoritesDisplayMode.displayedFolder.rawValue,
                                                  in: context)?.favoritesArray.compactMap(Self.bookmark) ?? []
    }

    func children(of folderID: String? = nil) -> [MainMenuBookmarkEntry] {
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
        guard let url = entity.urlObject else { return nil }
        return MainMenuBookmark(title: entity.title.flatMap { $0.isEmpty ? nil : $0 } ?? url.absoluteString, url: url)
    }
}
