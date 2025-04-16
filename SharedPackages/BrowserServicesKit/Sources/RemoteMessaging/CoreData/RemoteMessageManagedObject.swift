//
//  RemoteMessageManagedObject.swift
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

@objc(RemoteMessageManagedObject)
public class RemoteMessageManagedObject: NSManagedObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<RemoteMessageManagedObject> {
        return NSFetchRequest<RemoteMessageManagedObject>(entityName: "RemoteMessageManagedObject")
    }

    public class func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "RemoteMessageManagedObject", in: context)!
    }

    @NSManaged public var id: String?
    @NSManaged public var message: String?
    @NSManaged public var shown: Bool
    @NSManaged public var status: NSNumber?

    public convenience init(context moc: NSManagedObjectContext) {
        self.init(entity: RemoteMessageManagedObject.entity(in: moc), insertInto: moc)
    }
}
