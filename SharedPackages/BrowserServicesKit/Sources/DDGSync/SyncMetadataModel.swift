//
//  SyncMetadataModel.swift
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

    static let syncMetadata = VersionedManagedObjectModel(versions: [
        SyncMetadataModel.v1,
        SyncMetadataModel.v2,
        SyncMetadataModel.v3,
        SyncMetadataModel.v4,
    ])
}

/// Schema versions of the Sync metadata store, formerly `SyncMetadata.xcdatamodeld`.
///
/// Never change a shipped version: append a new one to `VersionedManagedObjectModel.syncMetadata`.
public enum SyncMetadataModel {

    static let feature = "SyncFeatureEntity"
    static let settingsMetadata = "SyncableSettingsMetadata"

    public static func v1() -> [CoreDataEntity] {
        [
            CoreDataEntity(feature, className: feature, attributes: [
                CoreDataAttribute("lastModified", .stringAttributeType, optional: true),
                CoreDataAttribute("name", .stringAttributeType),
            ], indexes: [
                CoreDataIndex("byName", properties: ["name"]),
            ], uniquenessConstraints: [
                ["name"],
            ]),
        ]
    }

    /// Adds feature `state`.
    public static func v2() -> [CoreDataEntity] {
        var entities = v1()
        entities.modify(feature) {
            $0.attributes.append(CoreDataAttribute("state", .stringAttributeType, optional: true))
        }
        return entities
    }

    /// Adds settings metadata.
    public static func v3() -> [CoreDataEntity] {
        var entities = v2()
        entities.append(CoreDataEntity(settingsMetadata, className: settingsMetadata, attributes: [
            CoreDataAttribute("key", .stringAttributeType),
            CoreDataAttribute("lastModified", .dateAttributeType, optional: true),
        ], indexes: [
            CoreDataIndex("byKey", properties: ["key"]),
        ], uniquenessConstraints: [
            ["key"],
        ]))
        return entities
    }

    /// Adds `lastSyncLocalTimestamp`.
    public static func v4() -> [CoreDataEntity] {
        var entities = v3()
        entities.modify(feature) {
            $0.attributes.append(CoreDataAttribute("lastSyncLocalTimestamp", .dateAttributeType, optional: true))
        }
        return entities
    }
}
