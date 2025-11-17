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
    let resourcesURLDirectory: URL
    let testLocation: URL

    init() throws {
        testLocation = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resourcesLocation = testLocation.appendingPathComponent( "BrowserServicesKit_RemoteMessagingTests.bundle/Contents/Resources/")
        if FileManager.default.fileExists(atPath: resourcesLocation.path) == false {
            resourcesURLDirectory = try #require(Bundle.module.resourceURL)
        } else {
            resourcesURLDirectory = resourcesLocation
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: testLocation)
    }

    @Test("Check Model Lightweight Migration From V1 to V2")
    func checkModelMigrationFromV1ToV2() throws {
        // GIVEN
        // Copy real V1 database files
        try copyDatabase(name: "Database_V1", formDirectory: resourcesURLDirectory, toDirectory: testLocation, targetName: "RemoteMessaging")

        // WHEN Load with V2 model - Core Data automatically perform lightweight migration
        let v2Model = try #require(CoreDataDatabase.loadModel(from: RemoteMessaging.bundle, named: "RemoteMessaging"))
        let migratedDatabase = CoreDataDatabase(name: "RemoteMessaging", containerLocation: testLocation, model: v2Model)
        migratedDatabase.loadStore()

        // THEN Assert fetching and save new object works fine.
        let context = migratedDatabase.makeContext(concurrencyType: .privateQueueConcurrencyType)
        try context.performAndWait {
            // Verify migration by accessing surfaces property
            let fetchRequest: NSFetchRequest<RemoteMessageManagedObject> = RemoteMessageManagedObject.fetchRequest()
            let messages = try context.fetch(fetchRequest)
            #expect(messages.count == 1)
            let message = try #require(messages.first)
            #expect(message.surfaces == nil, "Migrated records should have nil surfaces")
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
        }

        // Clean up
        try migratedDatabase.tearDown(deleteStores: true)
    }
}

extension RemoteMessagingModelMigrationTests {

    func copyDatabase(name: String, formDirectory: URL, toDirectory: URL, targetName: String) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: toDirectory, withIntermediateDirectories: true)
        try ["sqlite", "sqlite-shm", "sqlite-wal"].forEach { ext in
            let sourceURL = formDirectory.appendingPathComponent("\(name).\(ext)")
            let targetURL  = toDirectory.appendingPathComponent("\(targetName).\(ext)")
            if fileManager.fileExists(atPath: sourceURL.path) {
                try fileManager.copyItem(at: sourceURL, to: targetURL)
            }
        }
    }
}
