//
//  AppRatingPromptDatabaseMigrationTests.swift
//  DuckDuckGo
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

import XCTest
@testable import DuckDuckGo
@testable import Core
import CoreData
import Persistence

final class AppRatingPromptDatabaseMigrationTests: XCTestCase {

    /// Entity version hashes of every shipped schema version, as compiled by `momc` from the former
    /// `AppRatingPrompt.xcdatamodeld`. A mismatch means a shipped version was changed — add a new version instead.
    func testEveryVersionMatchesShippedVersionHashes() {
        let expected = [
            "toMA+c/wuxvWObcyatsUwgaNE/IryjRBX4PxX7XVmKk=",
            "xuGb1YlO69OWozj+UZy937w0091kBLB7S6U78K4U1/Q=",
        ]
        let versions = [AppRatingPromptModel.v1, AppRatingPromptModel.v2]

        for (index, (version, hash)) in zip(versions, expected).enumerated() {
            let model = NSManagedObjectModel(entities: version())
            XCTAssertEqual(model.entityVersionHashesByName.mapValues { $0.base64EncodedString() }, ["AppRatingPromptEntity": hash],
                           "AppRatingPrompt v\(index + 1)")
        }
    }

    /// `AppRatingPrompt_v1` is a real `Database` store saved with AppRatingPrompt v1, RemoteMessaging v1 and HTTPSUpgrade v3.
    func testMigrationFromV1toLatest() throws {
        let fixtureURL = try XCTUnwrap(Bundle(for: type(of: self)).url(forResource: "AppRatingPrompt_v1", withExtension: nil))
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: fixtureURL, to: location)
        defer { try? FileManager.default.removeItem(at: location) }
        let storeURL = location.appendingPathComponent("Database.sqlite")

        // The fixture must match known versions, so it's migrated without relying on Core Data's cached model.
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL)
        XCTAssertNotNil(Database.model.model(compatibleWithStoreMetadata: metadata))

        let database = CoreDataDatabase(name: "Database", containerLocation: location, model: Database.model)
        var loadError: Error?
        database.loadStore { _, error in loadError = error }
        XCTAssertNil(loadError)
        defer { try? database.tearDown(deleteStores: false) }

        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        try context.performAndWait {
            let count = try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "AppRatingPromptEntity"))
            XCTAssertGreaterThan(count, 0, "Migration failed, no entities found.")
        }
        let migratedMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL)
        XCTAssertTrue(Database.model.current.isConfiguration(withName: nil, compatibleWithStoreMetadata: migratedMetadata))
    }

}
