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
import PixelKit
import Common
import FoundationExtensions

/// iOS-specific wrapper to provide the PrivacyStats Core Data stack.
final class PrivacyStatsDatabase: PrivacyStatsDatabaseProviding {

    private let database: CoreDataDatabase
    private let pixelFiring: (any PixelKitFiring)?

    init(database: CoreDataDatabase = PrivacyStatsDatabase.makeDatabase(location: PrivacyStatsDatabase.defaultLocation),
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        self.database = database
        self.pixelFiring = pixelFiring
    }

    func initializeDatabase() -> CoreDataDatabase {
        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?
        database.loadStore { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let loadError {
            // `PrivacyStats` would otherwise wait in `CoreDataDatabase.makeContext` forever and freeze the launch.
            // Give the pixel a moment to send before terminating, as `Terminating` does.
            pixelFiring?.fire(PrivacyStatsDatabasePixel.loadFailed(loadError), frequency: .dailyAndCount)
            Thread.sleep(forTimeInterval: 1)
            fatalError("Could not create Privacy Stats database stack: \(loadError.localizedDescription)")
        }
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

enum PrivacyStatsDatabasePixel: PixelKit.Event {

    case loadFailed(Error)

    var name: String { "privacy-stats_database_load_failed" }

    var parameters: [String: String]? { nil }

    var error: NSError? {
        switch self {
        case .loadFailed(let error):
            return error as NSError
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
