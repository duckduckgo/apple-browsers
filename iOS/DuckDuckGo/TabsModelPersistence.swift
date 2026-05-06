//
//  TabsModelPersistence.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import UIKit
import Persistence
import Core

enum TabsModelStorageKey {
    case normal
    case fire
}

protocol TabsModelPersisting {

    func getTabsModel(for key: TabsModelStorageKey) throws -> TabsModel?
    func save(model: TabsModel, for key: TabsModelStorageKey) -> Result<Void, Error>
    func clear(for key: TabsModelStorageKey)
    func clearAll()
    /// Blocks the caller until any in-flight asynchronous save has finished writing to disk.
    /// Conformers that perform synchronous writes can leave the default no-op.
    func flush()
    /// Synchronously persists the model and returns the real outcome (the async `save(model:for:)`
    /// path may return `.success` immediately and report errors only via telemetry).
    func saveSynchronously(model: TabsModel, for key: TabsModelStorageKey) -> Result<Void, Error>
}

extension TabsModelPersisting {
    func flush() {}
    /// Default implementation: defer to `save(model:for:)` for conformers whose `save` is already
    /// synchronous (e.g. test mocks).
    func saveSynchronously(model: TabsModel, for key: TabsModelStorageKey) -> Result<Void, Error> {
        save(model: model, for: key)
    }
}

enum TabsPersistenceError: Error {
    case appSupportDirAccess
    case storeInit
}

class TabsModelPersistence: TabsModelPersisting {

    private struct Constants {
        static let normalStorageName = "TabsModel"
        static let fireStorageName = "FireTabsModel"
        static let storageKey = "TabsModelKey"
        static let legacyUDKey = "com.duckduckgo.opentabs"
    }

    private let normalStore: ThrowingKeyValueStoring
    private let fireStore: ThrowingKeyValueStoring
    private let legacyStore: KeyValueStoring

    /// Serial queue used to encode + write tabs models off the main thread. All writes for both
    /// stores funnel through this queue, so a `flush()` from any thread is guaranteed to wait for
    /// any in-flight encode to finish.
    private let persistQueue = DispatchQueue(label: "com.duckduckgo.tabsmodel.persist", qos: .utility)

    convenience init() throws {

        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // Move app to Terminating state
            throw TerminationError.tabsPersistence(.appSupportDirAccess)
        }

        do {
            let normalStore = try KeyValueFileStore(location: appSupportDir, name: Constants.normalStorageName)
            let fireStore = try KeyValueFileStore(location: appSupportDir, name: Constants.fireStorageName)
            self.init(normalStore: normalStore,
                      fireStore: fireStore,
                      legacyStore: UserDefaults.app)
        } catch {
            // Move app to Terminating state
            throw TerminationError.tabsPersistence(.storeInit)
        }
    }

    init(normalStore: ThrowingKeyValueStoring,
         fireStore: ThrowingKeyValueStoring,
         legacyStore: KeyValueStoring) {
        self.normalStore = normalStore
        self.fireStore = fireStore
        self.legacyStore = legacyStore
    }

    private func store(for key: TabsModelStorageKey) -> ThrowingKeyValueStoring {
        switch key {
        case .normal: return normalStore
        case .fire: return fireStore
        }
    }

    private func unarchive(data: Data) -> TabsModel? {
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            let model = unarchiver.decodeObject(of: TabsModel.self, forKey: NSKeyedArchiveRootObjectKey)
            if let error = unarchiver.error {
                throw error
            }
            return model
        } catch {
            DailyPixel.fireDailyAndCount(pixel: .tabsStoreReadError,
                                         pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                                         error: error)
            Logger.general.error("Something went wrong unarchiving TabsModel \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    public func getTabsModel(for key: TabsModelStorageKey) throws -> TabsModel? {
        let targetStore = store(for: key)
        let data = try targetStore.object(forKey: Constants.storageKey) as? Data
        if let data {
            return unarchive(data: data)
        }

        guard key == .normal else { return nil }

        if let legacyData = legacyStore.object(forKey: Constants.legacyUDKey) as? Data,
           let model = unarchive(data: legacyData) {
            do {
                try targetStore.set(legacyData, forKey: Constants.storageKey)
                legacyStore.removeObject(forKey: Constants.legacyUDKey)
            } catch {
                Logger.general.error("Could not migrate Tabs Model \(error.localizedDescription, privacy: .public)")
            }
            return model
        }
        return nil
    }

    public func clear(for key: TabsModelStorageKey) {
        try? store(for: key).removeObject(forKey: Constants.storageKey)
        if key == .normal {
            legacyStore.removeObject(forKey: Constants.legacyUDKey)
        }
    }

    public func clearAll() {
        try? normalStore.removeObject(forKey: Constants.storageKey)
        try? fireStore.removeObject(forKey: Constants.storageKey)
        legacyStore.removeObject(forKey: Constants.legacyUDKey)
    }

    public func save(model: TabsModel, for key: TabsModelStorageKey) -> Result<Void, Error> {
        // Hop the heavy NSCoding encode + disk write off the main thread. We reference the live
        // model: subsequent main-thread mutations after this point are intentionally not captured
        // (they will be picked up by the next save()). Lifecycle force-flush callers should drain
        // the queue via `flush()` before the app suspends to guarantee durability.
        let targetStore = store(for: key)
        persistQueue.async {
            _ = self.encodeAndWrite(model: model, into: targetStore)
        }
        return .success(())
    }

    /// Encodes the model and writes it to the given store, returning the real outcome and reporting
    /// failures via daily pixel + log. Always invoked from the persistence's serial queue.
    @discardableResult
    private func encodeAndWrite(model: TabsModel, into targetStore: ThrowingKeyValueStoring) -> Result<Void, Error> {
        do {
            // Deep-copy to freeze mutable state before archiving (race-safe off-main encode).
            let snapshot = model.archivalSnapshot()
            let data = try NSKeyedArchiver.archivedData(withRootObject: snapshot, requiringSecureCoding: false)
            try targetStore.set(data, forKey: Constants.storageKey)
            return .success(())
        } catch {
            DailyPixel.fireDailyAndCount(pixel: .tabsStoreSaveError,
                                         pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                                         error: error)
            Logger.general.error("Something went wrong archiving TabsModel: \(error.localizedDescription, privacy: .public)")
            return .failure(error)
        }
    }

    /// Blocks until any pending async save has finished writing.
    public func flush() {
        persistQueue.sync { }
    }

    /// Synchronously persists the model: drains any queued async saves first, then encodes + writes
    /// inline on the serial queue, returning the actual outcome. Use this when the caller needs the
    /// real `Result` (e.g. data-clearing telemetry) rather than the always-success placeholder
    /// returned by the debounced/async path.
    public func saveSynchronously(model: TabsModel, for key: TabsModelStorageKey) -> Result<Void, Error> {
        let targetStore = store(for: key)
        return persistQueue.sync {
            self.encodeAndWrite(model: model, into: targetStore)
        }
    }

}
