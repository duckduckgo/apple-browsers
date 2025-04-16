//
//  FavoritesDisplayMode.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import CoreData
import Foundation

/**
 * This enum defines which set of favorites should be displayed to the user.
 *
 * Users only ever see one set of favorites at a time, and as long as Sync
 * is not enabled, it's the one corresponding to the local device (native)
 * form factor, i.e. `mobile` on iOS and iPadOS and `desktop` on macOS.
 *
 * When Sync is enabled, users get to choose between displaying their native
 * form factor folder, or a unified folder that contains favorites from
 * both mobile and desktop combined.
 */
public enum FavoritesDisplayMode: Equatable {
    /**
     * Display native form factor favorites.
     *
     * This case takes a parameter that specifies the native form factor.
     * It's up to the client app to define its native form factor.
     *
     * Using a parameter gives the flexibility of overriding the form factor
     * on a given client in the future (e.g. treat `desktop` as native form
     * factor on the iPad).
     */
    case displayNative(FavoritesFolderID)

    /**
     * Display unified favorites (mobile + desktop combined)
     *
     * This case takes a parameter that specifies the native form factor.
     * It's required because all favorites that are added to or deleted from
     * the unified folder need also to be added to or deleted from their
     * respective native form factor folder.
     */
    case displayUnified(native: FavoritesFolderID)

    /// Returns true if the current mode is to display unified folder.
    public var isDisplayUnified: Bool {
        switch self {
        case .displayNative:
            return false
        case .displayUnified:
            return true
        }
    }

    /// Returns the UUID of a folder that is displayed for a given display mode.
    public var displayedFolder: FavoritesFolderID {
        switch self {
        case .displayNative(let platform):
            return platform
        case .displayUnified:
            return .unified
        }
    }

    /// Returns the UUID of a native favorites folder for a given display mode.
    public var nativeFolder: FavoritesFolderID {
        switch self {
        case .displayNative(let native), .displayUnified(let native):
            return native
        }
    }

    /// Returns UUIDs of folders that all favorites must be added to in the current display mode.
    var folderUUIDs: Set<String> {
        [nativeFolder.rawValue, FavoritesFolderID.unified.rawValue]
    }
}

extension FavoritesDisplayMode: CustomStringConvertible {
    public var description: String {
        switch self {
        case .displayNative:
            return "display_native"
        case .displayUnified:
            return "display_all"
        }
    }
}

extension BookmarkEntity {

    /**
     * Adds sender to favorites according to `displayMode` passed as argument.
     */
    public func addToFavorites(with displayMode: FavoritesDisplayMode, in context: NSManagedObjectContext) {
        let folders = BookmarkUtils.fetchFavoritesFolders(withUUIDs: displayMode.folderUUIDs, in: context)
        addToFavorites(folders: folders)
    }

    /**
     * Removes sender from favorites according to `displayMode` passed as argument.
     *
     * When current mode is to display unified favorites - a favorite is removed from all folders.
     * When current mode is to display native form factor - it's removed from the native form factor
     * folder, and if it's not favorites on non-native form factor then also removed from unified folder.
     */
    public func removeFromFavorites(with displayMode: FavoritesDisplayMode) {
        let affectedFolders: [BookmarkEntity] = {
            let isFavoritedOnlyOnNativeFormFactor = Set(favoriteFoldersSet.compactMap(\.uuid)) == displayMode.folderUUIDs
            if displayMode.isDisplayUnified || isFavoritedOnlyOnNativeFormFactor {
                return Array(favoriteFoldersSet)
            }
            if let nativeFolder = favoriteFoldersSet.first(where: { $0.uuid == displayMode.nativeFolder.rawValue }) {
                return [nativeFolder]
            }
            return []
        }()

        assert(!affectedFolders.isEmpty)

        if !affectedFolders.isEmpty {
            removeFromFavorites(folders: affectedFolders)
        }
    }

}
