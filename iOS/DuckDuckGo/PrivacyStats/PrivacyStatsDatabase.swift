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
    /// created once the store is open; otherwise app launch hangs. Stats are rebuildable, so a corrupt store is
    /// deleted and recreated. Any other failure, or a failed recreate, makes Privacy Stats unavailable for this
    /// session and keeps the store for the next launch.
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

        pixelFiring?.fire(PrivacyStatsDatabasePixel.loadFailed(error, stage: .initial), frequency: .dailyAndCount)
        // Disk full, protected data unavailable before first unlock or no permission are usually temporary,
        // so the user's stats are kept for the next launch.
        guard Self.isCorrupt(error) else {
            Logger.general.error("Could not load Privacy Stats database: \(error.localizedDescription, privacy: .public)")
            return false
        }

        Logger.general.error("Privacy Stats database is corrupt, recreating it: \(error.localizedDescription, privacy: .public)")
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

    /// Whether the store can never load as it is: the file is not a valid database, or it is from a model this
    /// version cannot migrate. The SQLite result code wins when there is one, so a migration that failed because
    /// the disk is full does not count.
    static func isCorrupt(_ error: Error) -> Bool {
        let error = error as NSError
        guard error.domain == NSCocoaErrorDomain else { return false }
        if let sqliteCode = error.userInfo[NSSQLiteErrorDomain] as? Int {
            return sqliteCode == 11 || sqliteCode == 26 // SQLITE_CORRUPT, SQLITE_NOTADB
        }
        return [NSFileReadCorruptFileError,
                NSPersistentStoreIncompatibleVersionHashError,
                NSPersistentStoreIncompatibleSchemaError,
                NSMigrationError,
                NSMigrationMissingSourceModelError,
                NSMigrationMissingMappingModelError].contains(error.code)
    }

    private func deleteStoreFiles() {
        // `destroyPersistentStore` removes the store and all of SQLite's sidecar files, and needs no loaded store.
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel())
        do {
            try coordinator.destroyPersistentStore(at: location.appendingPathComponent("\(Self.name).sqlite"),
                                                   ofType: NSSQLiteStoreType)
        } catch {
            Logger.general.error("Could not delete Privacy Stats database: \(error.localizedDescription, privacy: .public)")
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
