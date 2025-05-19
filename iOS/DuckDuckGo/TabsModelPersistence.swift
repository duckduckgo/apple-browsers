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

    func getTabsModel() -> TabsModel?
    func clear()
    func save(model: TabsModel)
}

class TabsModelPersistence: TabsModelPersisting {

    private struct Constants {
        static let storageName = "TabsModel"
        static let legacyUDKey = "com.duckduckgo.opentabs"
    }

    enum Error: Swift.Error {
        case tabsPersistenceAppSupportDirAccessError
        case tabsPersistenceInitError
    }

    private let store: ThrowingKeyValueStoring

    init() throws {

        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
//            Pixel.fire(pixel: .keyValueFileStoreSupportDirAccessError)

            // Move app to Terminating state
            throw Error.tabsPersistenceAppSupportDirAccessError
        }

        do {
            self.store = try KeyValueFileStore(location: appSupportDir, name: Constants.storageName)
        } catch {
            Pixel.fire(pixel: .keyValueFileStoreInitError)

            // Move app to Terminating state
            throw Error.tabsPersistenceInitError
        }
    }

    public func getTabsModel() -> TabsModel? {
        guard let data = UserDefaults.app.object(forKey: Constants.legacyUDKey) as? Data else {
            return nil
        }
        var tabsModel: TabsModel?
        do {
            let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
            unarchiver.requiresSecureCoding = false
            tabsModel = unarchiver.decodeObject(of: TabsModel.self, forKey: NSKeyedArchiveRootObjectKey)
            if let error = unarchiver.error {
                throw error
            }
        } catch {
            Logger.general.error("Something went wrong unarchiving TabsModel \(error.localizedDescription, privacy: .public)")
        }
        return tabsModel
    }

    public func clear() {
         UserDefaults.app.removeObject(forKey: Constants.legacyUDKey)
    }

    public func save(model: TabsModel) {
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: model, requiringSecureCoding: false)
            UserDefaults.app.set(data, forKey: Constants.legacyUDKey)
        } catch {
            Logger.general.error("Something went wrong archiving TabsModel: \(error.localizedDescription, privacy: .public)")
        }
    }

}
