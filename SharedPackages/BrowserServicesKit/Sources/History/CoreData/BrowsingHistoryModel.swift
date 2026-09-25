//
//  BrowsingHistoryModel.swift
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

    static let browsingHistory = VersionedManagedObjectModel(versions: [
        BrowsingHistoryModel.v1,
        BrowsingHistoryModel.v2,
        BrowsingHistoryModel.v3,
    ])
}

/// Schema versions of the History store, formerly `BrowsingHistory.xcdatamodeld`.
///
/// Never change a shipped version: append a new one to `VersionedManagedObjectModel.browsingHistory`.
public enum BrowsingHistoryModel {

    static let entry = "BrowsingHistoryEntryManagedObject"
    static let visit = "PageVisitManagedObject"
    static let tabHistory = "TabHistoryManagedObject"

    public static func v1() -> [CoreDataEntity] {
        [
            CoreDataEntity(entry, className: entry, attributes: [
                CoreDataAttribute("blockedTrackingEntities", .stringAttributeType, optional: true),
                CoreDataAttribute("failedToLoad", .booleanAttributeType, defaultValue: false),
                CoreDataAttribute("identifier", .UUIDAttributeType),
                CoreDataAttribute("lastVisit", .dateAttributeType),
                CoreDataAttribute("numberOfTotalVisits", .integer64AttributeType, optional: true, defaultValue: 0, renamingIdentifier: "numberOfVisits"),
                CoreDataAttribute("numberOfTrackersBlocked", .integer64AttributeType, optional: true, defaultValue: 0),
                CoreDataAttribute("title", .stringAttributeType, optional: true, valueTransformerName: "NSStringTransformer"),
                CoreDataAttribute("trackersFound", .booleanAttributeType, optional: true),
                CoreDataAttribute("url", .URIAttributeType, valueTransformerName: "NSURLTransformer"),
            ], relationships: [
                .toMany("visits", visit, inverse: "historyEntry", optional: true, deleteRule: .cascadeDeleteRule),
            ]),
            CoreDataEntity(visit, className: visit, attributes: [
                CoreDataAttribute("date", .dateAttributeType),
            ], relationships: [
                .toOne("historyEntry", entry, inverse: "visits"),
            ]),
        ]
    }

    /// Adds `cookiePopupBlocked`.
    public static func v2() -> [CoreDataEntity] {
        var entities = v1()
        entities.modify(entry) {
            $0.attributes.insert(CoreDataAttribute("cookiePopupBlocked", .booleanAttributeType, defaultValue: false), at: 1)
        }
        return entities
    }

    /// Adds per-tab history.
    public static func v3() -> [CoreDataEntity] {
        var entities = v2()
        entities.modify(visit) {
            $0.relationships.append(.toOne("tabHistory", tabHistory, inverse: "visit", optional: true))
        }
        entities.append(CoreDataEntity(tabHistory, className: tabHistory, attributes: [
            CoreDataAttribute("tabID", .stringAttributeType),
            CoreDataAttribute("url", .URIAttributeType),
        ], relationships: [
            .toOne("visit", visit, inverse: "tabHistory", optional: true),
        ]))
        return entities
    }
}
