//
//  DailyBlockedTrackersEntity.swift
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

import Common
import CoreData

@objc(DailyBlockedTrackersEntity)
final class DailyBlockedTrackersEntity: NSManagedObject {
    enum Const {
        static let entityName = "DailyBlockedTrackersEntity"
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<DailyBlockedTrackersEntity> {
        NSFetchRequest<DailyBlockedTrackersEntity>(entityName: Const.entityName)
    }

    class func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        NSEntityDescription.entity(forEntityName: Const.entityName, in: context)!
    }

    @NSManaged var companyName: String
    @NSManaged var count: Int64
    @NSManaged var timestamp: Date

    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
    }

    private convenience init(context moc: NSManagedObjectContext) {
        self.init(entity: DailyBlockedTrackersEntity.entity(in: moc), insertInto: moc)
    }

    static func make(timestamp: Date = Date(), companyName: String, count: Int64 = 0, context: NSManagedObjectContext) -> DailyBlockedTrackersEntity {
        let object = DailyBlockedTrackersEntity(context: context)
        object.timestamp = timestamp.privacyStatsPackTimestamp
        object.companyName = companyName
        object.count = count
        return object
    }
}
