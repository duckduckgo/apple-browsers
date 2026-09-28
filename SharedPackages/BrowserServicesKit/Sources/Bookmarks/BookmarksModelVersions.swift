//
//  BookmarksModelVersions.swift
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

import CoreData
import Persistence

public extension VersionedManagedObjectModel {

    static let bookmarks = VersionedManagedObjectModel(versions: [
        BookmarksModel.v1,
        BookmarksModel.v2,
        BookmarksModel.v3,
        BookmarksModel.v4,
        BookmarksModel.v5,
        BookmarksModel.v6,
    ])
}

/// Schema versions of the Bookmarks store, formerly `BookmarksModel.xcdatamodeld`.
///
/// Never change a shipped version: append a new one to `VersionedManagedObjectModel.bookmarks`.
public enum BookmarksModel {

    static let bookmark = "BookmarkEntity"

    public static func v1() -> [CoreDataEntity] {
        [
            CoreDataEntity(bookmark, className: bookmark, attributes: [
                CoreDataAttribute("isFavorite", .booleanAttributeType),
                CoreDataAttribute("isFolder", .booleanAttributeType),
                CoreDataAttribute("title", .stringAttributeType, optional: true),
                CoreDataAttribute("url", .stringAttributeType, optional: true),
                CoreDataAttribute("uuid", .stringAttributeType),
            ], relationships: [
                .toMany("children", bookmark, inverse: "parent", optional: true, ordered: true, deleteRule: .cascadeDeleteRule),
                .toOne("favoriteFolder", bookmark, inverse: "favorites", optional: true),
                .toMany("favorites", bookmark, inverse: "favoriteFolder", optional: true, ordered: true),
                .toOne("parent", bookmark, inverse: "children", optional: true),
            ]),
        ]
    }

    /// Indexes `uuid` and `url`.
    public static func v2() -> [CoreDataEntity] {
        var entities = v1()
        entities.modify(bookmark) {
            $0.modifyAttribute("url") { $0.versionHashModifier = "2" }
            $0.modifyAttribute("uuid") { $0.versionHashModifier = "2" }
            $0.indexes = [
                CoreDataIndex("byUUID", properties: ["uuid"]),
                CoreDataIndex("byURL", properties: ["url"]),
            ]
        }
        return entities
    }

    /// Sync support: soft deletion and modification dates; favorites are tracked by the favorites folder only.
    public static func v3() -> [CoreDataEntity] {
        var entities = v2()
        entities.modify(bookmark) {
            $0.attributes.removeAll { $0.name == "isFavorite" }
            $0.attributes.append(CoreDataAttribute("isPendingDeletion", .booleanAttributeType, optional: true, defaultValue: false, versionHashModifier: "3"))
            $0.attributes.append(CoreDataAttribute("modifiedAt", .dateAttributeType, optional: true))
            $0.modifyAttribute("url") { $0.versionHashModifier = "3" }
            $0.modifyAttribute("uuid") { $0.versionHashModifier = "3" }
            $0.indexes = [
                CoreDataIndex("byUUID", properties: ["uuid", "isPendingDeletion"]),
                CoreDataIndex("byURL", properties: ["url", "isPendingDeletion"]),
                CoreDataIndex("byIsPendingDeletion", properties: ["isPendingDeletion"]),
            ]
        }
        return entities
    }

    /// Form-factor specific favorites: a bookmark can be in several favorites folders.
    public static func v4() -> [CoreDataEntity] {
        var entities = v3()
        entities.modify(bookmark) {
            $0.relationships.removeAll { $0.name == "favoriteFolder" }
            $0.relationships.append(.toMany("favoriteFolders", bookmark, inverse: "favorites", optional: true, renamingIdentifier: "favoriteFolder"))
            $0.modifyRelationship("favorites") { $0.inverse = "favoriteFolders" }
        }
        return entities
    }

    /// Adds `lastChildrenPayloadReceivedFromSync`.
    public static func v5() -> [CoreDataEntity] {
        var entities = v4()
        entities.modify(bookmark) {
            $0.attributes.append(CoreDataAttribute("lastChildrenPayloadReceivedFromSync", .stringAttributeType, optional: true))
        }
        return entities
    }

    /// Adds `isStub`.
    public static func v6() -> [CoreDataEntity] {
        var entities = v5()
        entities.modify(bookmark) {
            $0.attributes.append(CoreDataAttribute("isStub", .booleanAttributeType, optional: true))
        }
        return entities
    }
}
