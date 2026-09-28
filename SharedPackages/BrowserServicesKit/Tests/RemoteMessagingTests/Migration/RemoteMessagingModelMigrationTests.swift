//
//  RemoteMessagingModelMigrationTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Testing
import Persistence
@testable import RemoteMessaging

@Suite("RMF - Core Data Migration")
final class RemoteMessagingModelMigrationTests {
    let testLocation: URL

    init() {
        testLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    deinit {
        try? FileManager.default.removeItem(at: testLocation)
    }

    @Test("Check Model Lightweight Migration From V1 to Current Version")
    func checkModelMigrationFromV1ToCurrentVersion() throws {
        // GIVEN a standalone Remote Messaging store (as on macOS) saved with V1
        let storeURL = testLocation.appendingPathComponent("RemoteMessaging.sqlite")
        try makeV1Store(at: storeURL)

        // The store must match a known version, so it's migrated without relying on Core Data's cached model.
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL)
        #expect(VersionedManagedObjectModel.remoteMessaging.model(compatibleWithStoreMetadata: metadata) != nil)

        // WHEN Load with the current model, which migrates the store
        let migratedDatabase = CoreDataDatabase(name: "RemoteMessaging", containerLocation: testLocation, model: .remoteMessaging)
        migratedDatabase.loadStore()

        // THEN Assert fetching and save new object works fine.
        let context = migratedDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        try context.performAndWait {
            // Verify migration by accessing properties added after V1.
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            let messages = try context.fetch(fetchRequest)
            #expect(messages.count == 1)
            let message = try #require(messages.first)
            #expect(message.id == "v1-message")
            #expect(message.shown == true)
            #expect(message.surfaces == nil, "Migrated records should have nil surfaces")
            #expect(message.firstShownDate == nil)
            #expect(message.impressionCount == 0, "Migrated records should start with no impressions")
        }

        // Test creating new record with surfaces
        try context.performAndWait {
            let newMessage = RemoteMessageManagedObject(context: context)
            newMessage.id = "post-migration-test"
            newMessage.message = "Test after migration"
            newMessage.surfaces = NSNumber(value: RemoteMessageSurfaceType.newTabPage.rawValue)
            try context.save()
            // Verify new functionality works
            #expect(newMessage.surfaces?.int16Value == RemoteMessageSurfaceType.newTabPage.rawValue)
            #expect(newMessage.impressionCount == 0)
        }

        // Clean up
        try migratedDatabase.tearDown(deleteStores: true)
    }
}

extension RemoteMessagingModelMigrationTests {

    func makeV1Store(at storeURL: URL) throws {
        try FileManager.default.createDirectory(at: testLocation, withIntermediateDirectories: true)
        // V1 lacks later attributes, so it must not bind the current managed-object subclasses.
        let model = NSManagedObjectModel(entities: RemoteMessagingModel.v1(), bindsClasses: false)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            let message = NSEntityDescription.insertNewObject(forEntityName: "RemoteMessageManagedObject", into: context)
            message.setValue("v1-message", forKey: "id")
            message.setValue(true, forKey: "shown")
            try context.save()
        }
        try coordinator.remove(store)
    }
}
