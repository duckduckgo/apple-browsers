//
//  HTTPSExcludedDomain.swift
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

import Foundation
import CoreData

@objc(HTTPSExcludedDomain)
public class HTTPSExcludedDomain: NSManagedObject {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<HTTPSExcludedDomain> {
        return NSFetchRequest<HTTPSExcludedDomain>(entityName: "HTTPSExcludedDomain")
    }

    public class func entity(in context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "HTTPSExcludedDomain", in: context)!
    }

    public convenience init(context moc: NSManagedObjectContext) {
        self.init(entity: Self.entity(in: moc),
                  insertInto: moc)
    }

    @NSManaged public var domain: String?

}

extension HTTPSExcludedDomain: Identifiable {

}
