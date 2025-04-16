//
//  BrowsingHistoryEntryManagedObject.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

@objc(BrowsingHistoryEntryManagedObject)
public class BrowsingHistoryEntryManagedObject: NSManagedObject {

}

extension BrowsingHistoryEntryManagedObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<BrowsingHistoryEntryManagedObject> {
        return NSFetchRequest<BrowsingHistoryEntryManagedObject>(entityName: "BrowsingHistoryEntryManagedObject")
    }

    @NSManaged public var blockedTrackingEntities: String?
    @NSManaged public var failedToLoad: Bool
    @NSManaged public var identifier: UUID?
    @NSManaged public var lastVisit: Date?
    @NSManaged public var numberOfTotalVisits: Int64
    @NSManaged public var numberOfTrackersBlocked: Int64
    @NSManaged public var title: String?
    @NSManaged public var trackersFound: Bool
    @NSManaged public var url: URL?
    @NSManaged public var visits: NSSet?

}

// MARK: Generated accessors for visits
extension BrowsingHistoryEntryManagedObject {

    @objc(addVisitsObject:)
    @NSManaged public func addToVisits(_ value: PageVisitManagedObject)

    @objc(removeVisitsObject:)
    @NSManaged public func removeFromVisits(_ value: PageVisitManagedObject)

    @objc(addVisits:)
    @NSManaged public func addToVisits(_ values: NSSet)

    @objc(removeVisits:)
    @NSManaged public func removeFromVisits(_ values: NSSet)

}

extension BrowsingHistoryEntryManagedObject: Identifiable {

}
