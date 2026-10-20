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
import os.log

/// iOS-specific wrapper to provide the PrivacyStats Core Data stack.
final class PrivacyStatsDatabase: PrivacyStatsDatabaseProviding {

    private static let name = "PrivacyStats"

    private let location: URL
    private let database: CoreDataDatabase
    private let pixelFiring: (any PixelKitFiring)?

    /// Stats are rebuildable, so a store that cannot be opened is deleted and recreated.
    /// Returns `nil` if that fails too.
    init?(location: URL = PrivacyStatsDatabase.defaultLocation,
          pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        self.location = location
        self.database = PrivacyStatsDatabase.makeDatabase(location: location)
        self.pixelFiring = pixelFiring
        guard prepareStore() else { return nil }
    }

    /// The store is already loaded by `init`.
    func initializeDatabase() -> CoreDataDatabase {
        database
    }

    private func prepareStore() -> Bool {
        do {
            try loadStore()
            return true
        } catch {
            Logger.general.error("Could not load Privacy Stats database, recreating it: \(error.localizedDescription, privacy: .public)")
            pixelFiring?.fire(PrivacyStatsDatabasePixel.loadFailed(error, stage: .initial), frequency: .dailyAndCount)
            deleteStoreFiles()
        }

        do {
            try loadStore()
            return true
        } catch {
            Logger.general.error("Could not recreate Privacy Stats database: \(error.localizedDescription, privacy: .public)")
            pixelFiring?.fire(PrivacyStatsDatabasePixel.loadFailed(error, stage: .retry), frequency: .dailyAndCount)
            return false
        }
    }

    private func loadStore() throws {
        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?
        database.loadStore { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let loadError { throw loadError }
    }

    private func deleteStoreFiles() {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: location.appendingPathComponent("\(Self.name).sqlite\(suffix)"))
        }
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
        guard let model = CoreDataDatabase.loadModel(from: bundle, named: name) else {
            fatalError("Failed to load PrivacyStats model")
        }
        return CoreDataDatabase(name: name, containerLocation: location, model: model)
    }
}

enum PrivacyStatsDatabasePixel: PixelKit.Event {

    enum Stage: String {
        /// The store failed to load at launch.
        case initial
        /// The store failed to load again after it was deleted. Privacy Stats is unavailable for this session.
        case retry
    }

    case loadFailed(Error, stage: Stage)

    var name: String { "privacy-stats_database_load_failed" }

    var parameters: [String: String]? {
        switch self {
        case .loadFailed(_, let stage):
            return ["stage": stage.rawValue]
        }
    }

    var error: NSError? {
        switch self {
        case .loadFailed(let error, _):
            return error as NSError
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}
