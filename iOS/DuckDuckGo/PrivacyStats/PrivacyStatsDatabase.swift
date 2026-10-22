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

    /// Stats are rebuildable, so a corrupted store is deleted and recreated. Returns `nil` for any other load error,
    /// leaving the store in place for the next launch, or if recreating a corrupted store fails.
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

    /// Deletes the store's files. Missing files are ignored.
    static func deleteStoreFiles(at location: URL) throws {
        for suffix in ["", "-wal", "-shm"] {
            do {
                try FileManager.default.removeItem(at: location.appendingPathComponent("\(name).sqlite\(suffix)"))
            } catch CocoaError.fileNoSuchFile {
                continue
            }
        }
    }

    /// Whether a store load error means the file itself is unreadable, as opposed to an error that can clear up on its own.
    static func isCorruption(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadCorruptFileError {
            return true
        }
        let sqliteCode = nsError.domain == NSSQLiteErrorDomain ? nsError.code : (nsError.userInfo[NSSQLiteErrorDomain] as? NSNumber)?.intValue
        guard let sqliteCode else { return false }
        // Primary result code, ignoring extended bits: SQLITE_CORRUPT (11) or SQLITE_NOTADB (26).
        return [11, 26].contains(sqliteCode & 0xFF)
    }

    private func prepareStore() -> Bool {
        let error: Error
        do {
            try loadStore()
            return true
        } catch let loadError {
            error = loadError
        }

        guard Self.isCorruption(error) else {
            Logger.general.error("Could not load Privacy Stats database: \(error.localizedDescription, privacy: .public)")
            fireLoadFailed(error, outcome: .unavailable)
            return false
        }

        do {
            try Self.deleteStoreFiles(at: location)
            try loadStore()
            Logger.general.error("Recreated corrupted Privacy Stats database: \(error.localizedDescription, privacy: .public)")
            fireLoadFailed(error, outcome: .recreated)
            return true
        } catch let recreateError {
            Logger.general.error("Could not recreate Privacy Stats database: \(recreateError.localizedDescription, privacy: .public)")
            fireLoadFailed(recreateError, outcome: .recreateFailed)
            return false
        }
    }

    private func fireLoadFailed(_ error: Error, outcome: PrivacyStatsDatabasePixel.Outcome) {
        pixelFiring?.fire(PrivacyStatsDatabasePixel.loadFailed(error, outcome: outcome), frequency: .dailyAndCount)
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

    static var defaultLocation: URL {
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

    enum Outcome: String {
        /// The error isn't corruption. The store is left in place and Privacy Stats is unavailable for this session.
        case unavailable
        /// The store was corrupted and has been recreated.
        case recreated
        /// The store was corrupted and recreating it failed. Privacy Stats is unavailable for this session.
        case recreateFailed = "recreate_failed"
    }

    case loadFailed(Error, outcome: Outcome)

    var name: String { "privacy-stats_database_load_failed" }

    var parameters: [String: String]? {
        switch self {
        case .loadFailed(_, let outcome):
            return ["outcome": outcome.rawValue]
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
