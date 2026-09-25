//
//  PrivacyStatsModel.swift
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

    static let privacyStats = VersionedManagedObjectModel(versions: [
        PrivacyStatsModel.v1,
    ])
}

/// Schema versions of the PrivacyStats store, formerly `PrivacyStats.xcdatamodeld`.
///
/// Never change a shipped version: append a new one to `VersionedManagedObjectModel.privacyStats`.
public enum PrivacyStatsModel {

    public static func v1() -> [CoreDataEntity] {
        [
            CoreDataEntity("DailyBlockedTrackersEntity", className: "DailyBlockedTrackersEntity", attributes: [
                CoreDataAttribute("companyName", .stringAttributeType),
                CoreDataAttribute("count", .integer64AttributeType, defaultValue: 0),
                CoreDataAttribute("timestamp", .dateAttributeType),
            ], indexes: [
                CoreDataIndex("byTimestampAndCompanyName", properties: ["timestamp", "companyName"]),
            ], uniquenessConstraints: [
                ["timestamp", "companyName"],
            ]),
        ]
    }
}
