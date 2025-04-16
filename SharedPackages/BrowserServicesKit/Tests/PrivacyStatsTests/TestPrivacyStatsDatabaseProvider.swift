//
//  TestPrivacyStatsDatabaseProvider.swift
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

import Persistence
import XCTest
@testable import PrivacyStats

final class TestPrivacyStatsDatabaseProvider: PrivacyStatsDatabaseProviding {
    let databaseName: String
    var database: CoreDataDatabase!
    var location: URL!

    init(databaseName: String) {
        self.databaseName = databaseName
    }

    init(databaseName: String, location: URL) {
        self.databaseName = databaseName
        self.location = location
    }

    @discardableResult
    func initializeDatabase() -> CoreDataDatabase {
        if location == nil {
            location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        }
        let model = CoreDataDatabase.loadModel(from: PrivacyStats.bundle, named: "PrivacyStats")!
        database = CoreDataDatabase(name: databaseName, containerLocation: location, model: model)
        database.loadStore()
        return database
    }

    func tearDownDatabase() {
        try? database.tearDown(deleteStores: true)
        database = nil
        try? FileManager.default.removeItem(at: location)
    }

    func addObjects(_ objects: (NSManagedObjectContext) -> [DailyBlockedTrackersEntity], file: StaticString = #file, line: UInt = #line) throws {
        let context = database.makeContext(concurrencyType: .privateQueueConcurrencyType)
        context.performAndWait {
            _ = objects(context)
            do {
                try context.save()
            } catch {
                XCTFail("save failed: \(error)", file: file, line: line)
            }
        }
    }
}
