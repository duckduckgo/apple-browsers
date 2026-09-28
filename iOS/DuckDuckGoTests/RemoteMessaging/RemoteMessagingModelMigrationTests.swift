//
//  RemoteMessagingModelMigrationTests.swift
//  DuckDuckGo
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

import BrowserServicesKit
import CoreData
import Persistence
import RemoteMessaging
import XCTest
@testable import Core

final class RemoteMessagingModelMigrationTests: XCTestCase {

    func testMergedIOSDatabaseMigratesRemoteMessagingV3ToCurrentModel() throws {
        let entities = AppRatingPromptModel.v2() + RemoteMessagingModel.v3() + HTTPSUpgradeModel.v3()
        // V3 lacks impressionCount, so it must not bind the current managed-object subclass.
        let oldModel = NSManagedObjectModel(entities: entities, bindsClasses: false)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Database.sqlite")
        let sourceCoordinator = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
        let sourceStore = try sourceCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL)
        let sourceContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        sourceContext.persistentStoreCoordinator = sourceCoordinator
        let shownDate = Date(timeIntervalSince1970: 1_700_000_000)
        try sourceContext.performAndWait {
            let message = NSEntityDescription.insertNewObject(forEntityName: "RemoteMessageManagedObject", into: sourceContext)
            message.setValue("existing-message", forKey: "id")
            message.setValue(true, forKey: "shown")
            message.setValue(shownDate, forKey: "firstShownDate")
            let appRating = NSEntityDescription.insertNewObject(forEntityName: "AppRatingPromptEntity", into: sourceContext)
            appRating.setValue(shownDate, forKey: "firstShown")
            try sourceContext.save()
        }
        try sourceCoordinator.remove(sourceStore)

        let database = CoreDataDatabase(name: "Database", containerLocation: directory, model: Database.model)
        var loadError: Error?
        database.loadStore { _, error in loadError = error }
        XCTAssertNil(loadError)
        defer { try? database.tearDown(deleteStores: true) }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        try context.performAndWait {
            // The app and test bundle can load separate copies of the managed-object class.
            let messageRequest = NSFetchRequest<NSManagedObject>(entityName: "RemoteMessageManagedObject")
            let messages = try context.fetch(messageRequest)
            guard messages.count == 1 else {
                XCTFail("Expected one migrated remote message, got \(messages.count)")
                return
            }
            let message = messages[0]
            XCTAssertEqual(message.value(forKey: "id") as? String, "existing-message")
            XCTAssertEqual(message.value(forKey: "shown") as? Bool, true)
            XCTAssertEqual(message.value(forKey: "firstShownDate") as? Date, shownDate)
            XCTAssertEqual((message.value(forKey: "impressionCount") as? NSNumber)?.int64Value, 0)

            let appRatingRequest = NSFetchRequest<NSManagedObject>(entityName: "AppRatingPromptEntity")
            let appRatings = try context.fetch(appRatingRequest)
            XCTAssertEqual(appRatings.count, 1)
            XCTAssertEqual(appRatings.first?.value(forKey: "firstShown") as? Date, shownDate)
        }
    }
}
