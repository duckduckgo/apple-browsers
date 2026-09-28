//
//  BookmarkFormFactorFavoritesMigration.swift
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
import CoreData
import Persistence
import Common
import FoundationExtensions

public protocol BookmarkFormFactorFavoritesMigrating {

    func getFavoritesOrderFromPreV4Model(dbContainerLocation: URL,
                                         dbFileURL: URL) throws -> [String]?
}

public class BookmarkFormFactorFavoritesMigration: BookmarkFormFactorFavoritesMigrating {

    public init() {}

    public func getFavoritesOrderFromPreV4Model(dbContainerLocation: URL,
                                                dbFileURL: URL) throws -> [String]? {

        let bookmarksModel = VersionedManagedObjectModel.bookmarks
        guard let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: dbFileURL),
              !bookmarksModel.current.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata),
              // Before migrating to latest scheme version, read order of favorites from DB
              let oldBookmarksModel = bookmarksModel.model(compatibleWithStoreMetadata: metadata, bindsClasses: true)
        else {
            return nil
        }

        let oldDB = CoreDataDatabase(name: dbFileURL.deletingPathExtension().lastPathComponent,
                                     containerLocation: dbContainerLocation,
                                     model: oldBookmarksModel)

        var oldFavoritesOrder: [String]?

        var loadError: Error?
        oldDB.loadStore { context, error in
            guard let context = context else {
                loadError = error
                return
            }

            let favs = BookmarkUtils.fetchLegacyFavoritesFolder(context)
            let orderedFavorites = favs?.favorites?.array as? [BookmarkEntity] ?? []
            oldFavoritesOrder = orderedFavorites.compactMap { $0.uuid }
        }

        if let loadError {
            throw loadError
        }

        return oldFavoritesOrder
    }

    public static func migrateToFormFactorSpecificFavorites(byCopyingExistingTo folderID: FavoritesFolderID,
                                                            preservingOrderOf orderedUUIDs: [String]?,
                                                            in context: NSManagedObjectContext) {
        assert(folderID != .unified, "You must specify either desktop or mobile folder")

        guard let favoritesFolder = BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.unified.rawValue, in: context) else {
            return
        }

        if let orderedUUIDs {
            // Fix order of favorites
            let favorites = favoritesFolder.favoritesArray

            for fav in favorites {
                fav.removeFromFavorites(favoritesRoot: favoritesFolder)
            }

            for uuid in orderedUUIDs {
                if let fav = favorites.first(where: { $0.uuid == uuid }) {
                    fav.addToFavorites(favoritesRoot: favoritesFolder)
                }
            }
        }

        if BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.desktop.rawValue, in: context) == nil {
            let desktopFavoritesFolder = BookmarkUtils.insertRootFolder(uuid: FavoritesFolderID.desktop.rawValue, into: context)

            if folderID == .desktop {
                favoritesFolder.favoritesArray.forEach { bookmark in
                    bookmark.addToFavorites(favoritesRoot: desktopFavoritesFolder)
                }
            } else {
                desktopFavoritesFolder.shouldManageModifiedAt = false
            }
        }

        if BookmarkUtils.fetchFavoritesFolder(withUUID: FavoritesFolderID.mobile.rawValue, in: context) == nil {
            let mobileFavoritesFolder = BookmarkUtils.insertRootFolder(uuid: FavoritesFolderID.mobile.rawValue, into: context)

            if folderID == .mobile {
                favoritesFolder.favoritesArray.forEach { bookmark in
                    bookmark.addToFavorites(favoritesRoot: mobileFavoritesFolder)
                }
            } else {
                mobileFavoritesFolder.shouldManageModifiedAt = false
            }
        }
    }
}
