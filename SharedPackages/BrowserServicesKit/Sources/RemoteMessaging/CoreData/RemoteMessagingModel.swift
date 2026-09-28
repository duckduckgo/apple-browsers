//
//  RemoteMessagingModel.swift
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

    static let remoteMessaging = VersionedManagedObjectModel(versions: [
        RemoteMessagingModel.v1,
        RemoteMessagingModel.v2,
        RemoteMessagingModel.v3,
        RemoteMessagingModel.v4,
    ])
}

/// Schema versions of the Remote Messaging entities, formerly `RemoteMessaging.xcdatamodeld`: a store of
/// their own on macOS, part of the main `Database` store on iOS.
///
/// Never change a shipped version: append a new one to `VersionedManagedObjectModel.remoteMessaging`.
public enum RemoteMessagingModel {

    static let message = "RemoteMessageManagedObject"
    static let config = "RemoteMessagingConfigManagedObject"

    public static func v1() -> [CoreDataEntity] {
        [
            CoreDataEntity(message, className: message, attributes: [
                CoreDataAttribute("id", .stringAttributeType, optional: true),
                CoreDataAttribute("message", .stringAttributeType, optional: true),
                CoreDataAttribute("shown", .booleanAttributeType, defaultValue: false),
                CoreDataAttribute("status", .integer16AttributeType, optional: true, defaultValue: 0),
            ]),
            CoreDataEntity(config, className: config, attributes: [
                CoreDataAttribute("evaluationTimestamp", .dateAttributeType, optional: true),
                CoreDataAttribute("invalidate", .booleanAttributeType, optional: true),
                CoreDataAttribute("version", .integer64AttributeType, optional: true, defaultValue: 0),
            ]),
        ]
    }

    /// Adds message `surfaces`.
    public static func v2() -> [CoreDataEntity] {
        var entities = v1()
        entities.modify(message) {
            $0.attributes.append(CoreDataAttribute("surfaces", .integer16AttributeType, optional: true))
        }
        return entities
    }

    /// Adds `firstShownDate`.
    public static func v3() -> [CoreDataEntity] {
        var entities = v2()
        entities.modify(message) {
            $0.attributes.append(CoreDataAttribute("firstShownDate", .dateAttributeType, optional: true))
        }
        return entities
    }

    /// Adds `impressionCount`.
    public static func v4() -> [CoreDataEntity] {
        var entities = v3()
        entities.modify(message) {
            $0.attributes.append(CoreDataAttribute("impressionCount", .integer64AttributeType, defaultValue: 0))
        }
        return entities
    }
}
