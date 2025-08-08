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

protocol TabsModelPersisting {

    func getTabsModel() throws -> TabsModel?
    func clear()
    func save(model: TabsModel)
}

enum TabsPersistenceError: Error {
    case appSupportDirAccess
    case storeInit
}

class TabsModelPersistence: TabsModelPersisting {

    private struct Constants {
        static let storageName = "TabsModel"
        static let storageKey = "TabsModelKey"
        static let legacyUDKey = "com.duckduckgo.opentabs"
    }

    private let store: ThrowingKeyValueStoring
    private let legacyStore: KeyValueStoring

    convenience init() throws {

        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            // Move app to Terminating state
            throw TerminationError.tabsPersistence(.appSupportDirAccess)
        }

        do {
            let store = try KeyValueFileStore(location: appSupportDir, name: Constants.storageName)
            self.init(store: store,
                      legacyStore: UserDefaults.app)
        } catch {
            // Move app to Terminating state
            throw TerminationError.tabsPersistence(.storeInit)
        }
    }

    init(store: ThrowingKeyValueStoring,
         legacyStore: KeyValueStoring) {
        self.store = store
        self.legacyStore = legacyStore
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

    public func getTabsModel() throws -> TabsModel? {

        let data = try store.object(forKey: Constants.storageKey) as? Data
        if let data {
            guard let model = unarchive(data: data) else {
                return nil
            }
            return model
        } else {
            // Attempt to migrate
            if let legacyData = legacyStore.object(forKey: Constants.legacyUDKey) as? Data,
               let model = unarchive(data: legacyData) {
                do {
                    try store.set(legacyData, forKey: Constants.storageKey)
                    legacyStore.removeObject(forKey: Constants.legacyUDKey)
                } catch {
                    Logger.general.error("Could not migrate Tabs Model \(error.localizedDescription, privacy: .public)")
                }
                return model
            }
            return nil
        }
    }

    public func clear() {
        try? store.removeObject(forKey: Constants.storageKey)
        legacyStore.removeObject(forKey: Constants.legacyUDKey)
    }

    public func save(model: TabsModel) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
            try store.set(data, forKey: Constants.storageKey)
        } catch {
            DailyPixel.fireDailyAndCount(pixel: .tabsStoreSaveError,
                                         pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes,
                                         error: error)
            Logger.general.error("Something went wrong archiving TabsModel: \(error.localizedDescription, privacy: .public)")
        }
    }

}
