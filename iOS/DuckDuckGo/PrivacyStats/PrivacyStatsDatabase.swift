//
//  PrivacyStatsDatabase.swift
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

import Foundation
import CoreData
import PrivacyStats
import Persistence
import Common

/// iOS-specific wrapper to provide the PrivacyStats Core Data stack.
final class PrivacyStatsDatabase: PrivacyStatsDatabaseProviding {

    private let database: CoreDataDatabase

    init(database: CoreDataDatabase = PrivacyStatsDatabase.makeDatabase(location: PrivacyStatsDatabase.defaultLocation)) {
        self.database = database
    }

    func initializeDatabase() -> CoreDataDatabase {
        let semaphore = DispatchSemaphore(value: 0)
        database.loadStore { _, error in
            if let error {
                assertionFailure("Could not create Privacy Stats database stack: \(error.localizedDescription)")
            }
            semaphore.signal()
        }
        semaphore.wait()
        return database
    }

    private static var defaultLocation: URL {
        guard let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Failed to resolve application support directory")
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    private static func makeDatabase(location: URL) -> CoreDataDatabase {
        let bundle = PrivacyStats.bundle
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: "PrivacyStats") else {
            fatalError("Failed to load PrivacyStats model")
        }
        return CoreDataDatabase(name: "PrivacyStats", containerLocation: location, model: model)
    }
}
