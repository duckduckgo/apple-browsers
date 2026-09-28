//
//  AppRatingPromptModel.swift
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

    static let appRatingPrompt = VersionedManagedObjectModel(versions: [
        AppRatingPromptModel.v1,
        AppRatingPromptModel.v2,
    ])
}

/// Schema versions of the app rating prompt entity, formerly `AppRatingPrompt.xcdatamodeld`, stored in the
/// main iOS `Database` store.
///
/// Never change a shipped version: append a new one to `VersionedManagedObjectModel.appRatingPrompt`.
public enum AppRatingPromptModel {

    static let entity = "AppRatingPromptEntity"

    public static func v1() -> [CoreDataEntity] {
        [
            CoreDataEntity(entity, className: entity, attributes: [
                CoreDataAttribute("lastAccess", .dateAttributeType, optional: true),
                CoreDataAttribute("lastShown", .dateAttributeType, optional: true),
                CoreDataAttribute("uniqueAccessDays", .integer64AttributeType, optional: true, defaultValue: 0),
            ]),
        ]
    }

    /// Adds `firstShown`.
    public static func v2() -> [CoreDataEntity] {
        var entities = v1()
        entities.modify(entity) {
            $0.attributes.insert(CoreDataAttribute("firstShown", .dateAttributeType, optional: true), at: 0)
        }
        return entities
    }
}
