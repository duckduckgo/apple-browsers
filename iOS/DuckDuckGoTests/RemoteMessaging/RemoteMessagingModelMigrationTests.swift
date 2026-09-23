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

final class RemoteMessagingModelMigrationTests: XCTestCase {

    func testMergedIOSDatabaseMigratesRemoteMessagingV3ToCurrentModel() throws {
        let resourceURL = try XCTUnwrap(RemoteMessaging.bundle.resourceURL)
        let modelDirectory = RemoteMessaging.bundle.url(forResource: "RemoteMessaging", withExtension: "momd")
            ?? resourceURL.appendingPathComponent("RemoteMessaging.momd")
        let remoteMessagingV3Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelDirectory.appendingPathComponent("RemoteMessaging 3.mom")))
        let currentRemoteMessagingModel = try XCTUnwrap(CoreDataDatabase.loadModel(from: RemoteMessaging.bundle, named: "RemoteMessaging"))
        let appRatingModel = try XCTUnwrap(CoreDataDatabase.loadModel(from: .main, named: "AppRatingPrompt"))
        let oldModel = try XCTUnwrap(NSManagedObjectModel(byMerging: [appRatingModel, remoteMessagingV3Model, HTTPSUpgrade.managedObjectModel]))
        let currentModel = try XCTUnwrap(NSManagedObjectModel(byMerging: [appRatingModel, currentRemoteMessagingModel, HTTPSUpgrade.managedObjectModel]))
        // V3 lacks impressionCount, so it must not bind the current managed-object subclass.
        oldModel.entities.forEach { $0.managedObjectClassName = NSStringFromClass(NSManagedObject.self) }

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

        let destinationCoordinator = NSPersistentStoreCoordinator(managedObjectModel: currentModel)
        let options: [String: Any] = [NSMigratePersistentStoresAutomaticallyOption: true,
                                      NSInferMappingModelAutomaticallyOption: true]
        let destinationStore = try destinationCoordinator.addPersistentStore(ofType: NSSQLiteStoreType,
                                                                             configurationName: nil,
                                                                             at: storeURL,
                                                                             options: options)
        defer { try? destinationCoordinator.remove(destinationStore) }
        let destinationContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        destinationContext.persistentStoreCoordinator = destinationCoordinator
        try destinationContext.performAndWait {
            let messages = try destinationContext.fetch(RemoteMessageManagedObject.fetchRequest())
            guard messages.count == 1 else {
                XCTFail("Expected one migrated remote message, got \(messages.count)")
                return
            }
            let message = messages[0]
            XCTAssertEqual(message.id, "existing-message")
            XCTAssertTrue(message.shown)
            XCTAssertEqual(message.firstShownDate, shownDate)
            XCTAssertEqual(message.impressionCount, 0)

            let appRatingRequest = NSFetchRequest<NSManagedObject>(entityName: "AppRatingPromptEntity")
            let appRatings = try destinationContext.fetch(appRatingRequest)
            XCTAssertEqual(appRatings.count, 1)
            XCTAssertEqual(appRatings.first?.value(forKey: "firstShown") as? Date, shownDate)
        }
    }
}
