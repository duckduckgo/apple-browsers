//
//  RemoteMessageUtils.swift
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

import CoreData

struct RemoteMessageUtils {
    static func fetchRemoteMessage(with id: String, in context: NSManagedObjectContext) -> RemoteMessageManagedObject? {
        let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(RemoteMessageManagedObject.id), id)
        fetchRequest.fetchLimit = 1

        return try? context.fetch(fetchRequest).first
    }

    static func fetchScheduledRemoteMessage(in context: NSManagedObjectContext) -> RemoteMessageManagedObject? {
        let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "%K == %i",
            #keyPath(RemoteMessageManagedObject.status),
            RemoteMessagingStore.RemoteMessageStatus.scheduled.rawValue
        )
        fetchRequest.fetchLimit = 1

        return try? context.fetch(fetchRequest).first
    }

    static func fetchAllRemoteMessages(in context: NSManagedObjectContext) -> [RemoteMessageManagedObject] {
        let fetchRequest = RemoteMessageManagedObject.fetchRequest()
        return (try? context.fetch(fetchRequest)) ?? []
    }
}
