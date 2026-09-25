//
//  VersionedManagedObjectModel.swift
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

import CoreData
import Foundation

/// A Core Data model defined in code together with every schema version it has shipped with.
///
/// Replaces an `.xcdatamodeld` bundle: nothing has to be compiled by `momc` or looked up in a resource
/// bundle, so the model works the same when built by Xcode or by `swift build`/`swift test`.
///
/// Core Data's automatic migration finds the source model of an outdated store by searching bundles
/// for compiled `.mom` files. A code-defined model has none, so `migrateStoreIfNeeded(at:)` picks the
/// source version from `versions` itself and runs the same inferred (lightweight) migration.
/// For a store matching none of the versions, Core Data still falls back to the copy of the model it
/// caches inside the SQLite file.
///
/// Declare each model once, as a `static let`, and share it: an `NSEntityDescription` and the
/// `NSManagedObject` subclass it claims must not belong to more than one model instance.
public final class VersionedManagedObjectModel {

    /// The latest schema version, bound to the app's `NSManagedObject` subclasses.
    public let current: NSManagedObjectModel

    private let versions: [() -> [CoreDataEntity]]

    /// - Parameter versions: entity definitions of every shipped schema version, oldest first.
    ///   The last one is the current version. Never change a shipped version: add a new one.
    public init(versions: [() -> [CoreDataEntity]]) {
        guard let latest = versions.last else {
            preconditionFailure("A model needs at least one version")
        }
        self.versions = versions
        self.current = NSManagedObjectModel(entities: latest())
    }

    /// Brings a store created by an older schema version up to `current`.
    ///
    /// Does nothing if there is no store yet, the store already matches `current`, or it matches none of
    /// the known versions — the last case is left to Core Data's automatic migration when the store loads.
    public func migrateStoreIfNeeded(at storeURL: URL) throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL)
        guard !current.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata),
              let sourceModel = sourceModel(forStoreMetadata: metadata) else { return }

        let destinationModel = NSManagedObjectModel(entities: versions[versions.count - 1](), bindsClasses: false)
        let mappingModel = try NSMappingModel.inferredMappingModel(forSourceModel: sourceModel, destinationModel: destinationModel)
        let migrationManager = NSMigrationManager(sourceModel: sourceModel, destinationModel: destinationModel)

        let migratedStoreURL = storeURL.deletingPathExtension().appendingPathExtension("migrated.sqlite")
        Self.removeStoreFiles(at: migratedStoreURL)
        defer { Self.removeStoreFiles(at: migratedStoreURL) }

        try migrationManager.migrateStore(from: storeURL,
                                          sourceType: NSSQLiteStoreType,
                                          options: nil,
                                          with: mappingModel,
                                          toDestinationURL: migratedStoreURL,
                                          destinationType: NSSQLiteStoreType,
                                          destinationOptions: nil)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: destinationModel)
        try coordinator.replacePersistentStore(at: storeURL,
                                               destinationOptions: nil,
                                               withPersistentStoreFrom: migratedStoreURL,
                                               sourceOptions: nil,
                                               ofType: NSSQLiteStoreType)
    }

    /// `destroyPersistentStore` truncates the database but leaves its files behind.
    private static func removeStoreFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    /// The newest known version compatible with the store, mapped to plain `NSManagedObject`.
    func sourceModel(forStoreMetadata metadata: [String: Any]) -> NSManagedObjectModel? {
        for version in versions.reversed() {
            let model = NSManagedObjectModel(entities: version(), bindsClasses: false)
            if model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
                return model
            }
        }
        return nil
    }
}
