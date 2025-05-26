//
//  SyncableBookmarksExtension.swift
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

import Bookmarks
import DDGSync

extension Syncable {
    static func rootFolder(children: [String]) -> Syncable {
        .folder(id: BookmarkEntity.Constants.rootFolderID, children: children)
    }

    static func favoritesFolder(favorites: [String]) -> Syncable {
        .folder(id: FavoritesFolderID.unified.rawValue, children: favorites)
    }

    static func mobileFavoritesFolder(favorites: [String]) -> Syncable {
        .folder(id: FavoritesFolderID.mobile.rawValue, children: favorites)
    }

    static func desktopFavoritesFolder(favorites: [String]) -> Syncable {
        .folder(id: FavoritesFolderID.desktop.rawValue, children: favorites)
    }

    static func bookmark(_ title: String? = nil, id: String, url: String? = nil, lastModified: String? = nil, isDeleted: Bool = false) -> Syncable {
        var json: [String: Any] = [
            "id": id,
            "title": title ?? id,
            "page": ["url": (url ?? title) ?? id],
            "client_last_modified": "1234"
        ]
        if isDeleted {
            json["deleted"] = ""
        }
        return .init(jsonObject: json)
    }

    static func folder(_ title: String? = nil, id: String, children: [String] = [], lastModified: String? = nil, isDeleted: Bool = false) -> Syncable {
        var json: [String: Any] = [
            "id": id,
            "title": title ?? id,
            "folder": ["children": children],
            "client_last_modified": lastModified as Any
        ]
        if isDeleted {
            json["deleted"] = ""
        }
        return .init(jsonObject: json)
    }
}
