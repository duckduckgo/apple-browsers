//
//  HTTPSUpgradeManagedObjectModel.swift
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
import Persistence

extension HTTPSUpgrade {

    public static var managedObjectModel: NSManagedObjectModel {
        VersionedManagedObjectModel.httpsUpgrade.current
    }
}

public extension VersionedManagedObjectModel {

    static let httpsUpgrade = VersionedManagedObjectModel(versions: [
        HTTPSUpgradeModel.v3,
    ])
}

/// Schema versions of the HTTPS upgrade entities, formerly `HTTPSUpgrade.xcdatamodeld`, stored in the
/// main iOS and macOS `Database` stores.
///
/// Versions 1 and 2 were removed from the model long before this conversion.
/// Never change a shipped version: append a new one to `VersionedManagedObjectModel.httpsUpgrade`.
public enum HTTPSUpgradeModel {

    public static func v3() -> [CoreDataEntity] {
        [
            CoreDataEntity("HTTPSExcludedDomain", className: "HTTPSExcludedDomain", attributes: [
                CoreDataAttribute("domain", .stringAttributeType, optional: true),
            ], indexes: [
                CoreDataIndex("domainIndex", properties: ["domain"]),
            ], renamingIdentifier: "HTTPSWhitelistedDomain"),
            CoreDataEntity("HTTPSStoredBloomFilterSpecification", className: "HTTPSStoredBloomFilterSpecification", attributes: [
                CoreDataAttribute("bitCount", .integer64AttributeType, defaultValue: 0),
                CoreDataAttribute("errorRate", .doubleAttributeType, defaultValue: 0),
                CoreDataAttribute("sha256", .stringAttributeType),
                CoreDataAttribute("totalEntries", .integer64AttributeType, defaultValue: 0),
            ]),
        ]
    }
}
