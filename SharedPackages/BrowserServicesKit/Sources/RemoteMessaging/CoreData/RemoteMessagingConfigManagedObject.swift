//
//  RemoteMessagingConfigManagedObject.swift
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

@objc(RemoteMessagingConfigManagedObject)
public class RemoteMessagingConfigManagedObject: NSManagedObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RemoteMessagingConfigManagedObject> {
        return NSFetchRequest<RemoteMessagingConfigManagedObject>(entityName: "RemoteMessagingConfigManagedObject")
    }

    public class func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "RemoteMessagingConfigManagedObject", in: context)!
    }

    @NSManaged public var evaluationTimestamp: Date?
    @NSManaged public var invalidate: NSNumber?
    @NSManaged public var version: NSNumber?

    public convenience init(context moc: NSManagedObjectContext) {
        self.init(entity: RemoteMessagingConfigManagedObject.entity(in: moc), insertInto: moc)
    }
}

extension RemoteMessagingConfig {
    init(_ remoteMessagingConfigManagedObject: RemoteMessagingConfigManagedObject) {
        self.init(version: remoteMessagingConfigManagedObject.version?.int64Value ?? 0,
                  invalidate: remoteMessagingConfigManagedObject.invalidate?.boolValue ?? false,
                  evaluationTimestamp: remoteMessagingConfigManagedObject.evaluationTimestamp)
    }
}
