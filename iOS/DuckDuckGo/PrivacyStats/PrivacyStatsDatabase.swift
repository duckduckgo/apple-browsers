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
    private let pixelFiring: PixelFiring?

    /// `PrivacyStats` waits in `CoreDataDatabase.makeContext` until the store has loaded, so it must only be
    /// created once the store is open; otherwise app launch hangs. Stats are rebuildable, so a store that cannot
    /// be opened is deleted and recreated. If that fails too, Privacy Stats is unavailable for this session.
    static func makePrivacyStats(location: URL = PrivacyStatsDatabase.defaultLocation,
                                 pixelFiring: PixelFiring? = PixelKit.shared) -> PrivacyStatsProviding {
        let database = PrivacyStatsDatabase(location: location, pixelFiring: pixelFiring)
        guard database.prepareStore() else { return UnavailablePrivacyStats() }
        return PrivacyStats(databaseProvider: database)
    }

    private init(location: URL, pixelFiring: PixelFiring?) {
        self.location = location
        self.database = PrivacyStatsDatabase.makeDatabase(location: location)
        self.pixelFiring = pixelFiring
    }

    /// The store is loaded by `prepareStore()` before `PrivacyStats` calls this.
    func initializeDatabase() -> CoreDataDatabase {
        database
    }

    private func prepareStore() -> Bool {
        guard let error = loadStore() else { return true }

        Logger.general.error("Could not load Privacy Stats database, recreating it: \(error.localizedDescription, privacy: .public)")
        pixelFiring?.fire(PrivacyStatsDatabasePixel.loadFailed(error, stage: .initial), frequency: .dailyAndCount)
        deleteStoreFiles()

        guard let retryError = loadStore() else { return true }

        Logger.general.error("Could not recreate Privacy Stats database: \(retryError.localizedDescription, privacy: .public)")
        pixelFiring?.fire(PrivacyStatsDatabasePixel.loadFailed(retryError, stage: .retry), frequency: .dailyAndCount)
        return false
    }

    private func loadStore() -> Error? {
        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?
        database.loadStore { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        return loadError
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

/// Stands in for `PrivacyStats` when its store cannot be opened: nothing is recorded and counts read as zero.
final class UnavailablePrivacyStats: PrivacyStatsProviding {
    func recordBlockedTracker(_ name: String) async {}
    func fetchPrivacyStatsTotalCount() async -> Int64 { 0 }
    func clearPrivacyStats() async -> Result<Void, Error> { .success(()) }
    func handleAppTermination() async {}
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
