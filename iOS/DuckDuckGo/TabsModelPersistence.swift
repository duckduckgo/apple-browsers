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
    func save(model: TabsModel, for key: TabsModelStorageKey)
    func clear(for key: TabsModelStorageKey)
    func clearAll()
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

    public func save(model: TabsModel, for key: TabsModelStorageKey) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
            try store(for: key).set(data, forKey: Constants.storageKey)
        } catch {
            DailyPixel.fireDailyAndCount(pixel: .tabsStoreSaveError,
                                         pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                                         error: error)
            Logger.general.error("Something went wrong archiving TabsModel: \(error.localizedDescription, privacy: .public)")
        }
    }

}
