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
/// for compiled `.mom` files. A code-defined model has none, so `migrateStoreIfNeeded(at:options:)` picks
/// the source version itself and runs the same inferred (lightweight) migration.
/// For a store matching none of the versions, Core Data still falls back to the copy of the model it
/// caches inside the SQLite file.
///
/// Declare each model once, as a `static let`, and share it: an `NSEntityDescription` and the
/// `NSManagedObject` subclass it claims must not belong to more than one model instance.
///
/// `@unchecked Sendable`: `current` is built once under a lock, the rest is constant, and the version
/// builders only create new values.
public final class VersionedManagedObjectModel: @unchecked Sendable {

    /// The latest schema version, bound to the app's `NSManagedObject` subclasses.
    ///
    /// Built on first use, so a model merged into another one never claims those subclasses itself.
    public var current: NSManagedObjectModel {
        currentLock.lock()
        defer { currentLock.unlock() }
        if let currentModel {
            return currentModel
        }
        let model = NSManagedObjectModel(entities: latestEntities())
        currentModel = model
        return model
    }

    private var currentModel: NSManagedObjectModel?
    private let currentLock = NSLock()

    /// Version histories of the models sharing the store, each oldest first; one history unless merged.
    private let components: [[() -> [CoreDataEntity]]]

    /// - Parameter versions: entity definitions of every shipped schema version, oldest first.
    ///   The last one is the current version. Never change a shipped version: add a new one.
    public convenience init(versions: [() -> [CoreDataEntity]]) {
        self.init(components: [versions])
    }

    /// Several models sharing one store. Each keeps its own version history, so a store is migrated from
    /// whatever combination of their versions it was last saved with.
    public convenience init(merging models: [VersionedManagedObjectModel]) {
        self.init(components: models.flatMap(\.components))
    }

    private init(components: [[() -> [CoreDataEntity]]]) {
        guard !components.isEmpty, components.allSatisfy({ !$0.isEmpty }) else {
            preconditionFailure("A model needs at least one version")
        }
        self.components = components
    }

    private func latestEntities() -> [CoreDataEntity] {
        components.flatMap { $0[$0.count - 1]() }
    }

    /// Brings a store created by an older schema version up to `current`.
    ///
    /// Does nothing if there is no store yet, the store already matches `current`, or it matches none of
    /// the known versions — the last case is left to Core Data's automatic migration when the store loads.
    ///
    /// - Parameter options: the options the store is opened with, such as file protection.
    public func migrateStoreIfNeeded(at storeURL: URL, options: [AnyHashable: Any]? = nil) throws {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL, options: options)
        guard !current.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata),
              let sourceModel = model(compatibleWithStoreMetadata: metadata) else { return }

        let destinationModel = NSManagedObjectModel(entities: latestEntities(), bindsClasses: false)
        let mappingModel = try NSMappingModel.inferredMappingModel(forSourceModel: sourceModel, destinationModel: destinationModel)
        let migrationManager = NSMigrationManager(sourceModel: sourceModel, destinationModel: destinationModel)

        let migratedStoreURL = storeURL.deletingPathExtension().appendingPathExtension("migrated.sqlite")
        Self.removeStoreFiles(at: migratedStoreURL)
        defer { Self.removeStoreFiles(at: migratedStoreURL) }

        try migrationManager.migrateStore(from: storeURL,
                                          sourceType: NSSQLiteStoreType,
                                          options: options,
                                          with: mappingModel,
                                          toDestinationURL: migratedStoreURL,
                                          destinationType: NSSQLiteStoreType,
                                          destinationOptions: options)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: destinationModel)
        try coordinator.replacePersistentStore(at: storeURL,
                                               destinationOptions: options,
                                               withPersistentStoreFrom: migratedStoreURL,
                                               sourceOptions: options,
                                               ofType: NSSQLiteStoreType)
    }

    /// `destroyPersistentStore` truncates the database but leaves its files behind.
    private static func removeStoreFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }

    /// A new instance of the newest known version compatible with a store, or `nil` if none is.
    ///
    /// For merged models, picks the newest version of each model whose entities all match the store.
    ///
    /// - Parameter bindsClasses: whether entities map to the app's `NSManagedObject` subclasses. Only bind them
    ///   to read an outdated store through those subclasses, and only for properties that version has.
    public func model(compatibleWithStoreMetadata metadata: [String: Any], bindsClasses: Bool = false) -> NSManagedObjectModel? {
        guard let storeHashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data] else { return nil }

        var entities = [CoreDataEntity]()
        for versions in components {
            let matchingVersion = versions.reversed().lazy.map { $0() }.first { versionEntities in
                let hashes = NSManagedObjectModel(entities: versionEntities).entityVersionHashesByName
                return hashes.allSatisfy { storeHashes[$0.key] == $0.value }
            }
            guard let matchingVersion else { return nil }
            entities += matchingVersion
        }

        let model = NSManagedObjectModel(entities: entities, bindsClasses: bindsClasses)
        return model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) ? model : nil
    }
}
