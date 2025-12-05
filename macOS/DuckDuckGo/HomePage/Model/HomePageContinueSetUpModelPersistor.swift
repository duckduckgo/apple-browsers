//
//  HomePageContinueSetUpModelPersistor.swift
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

import Foundation
import Persistence

protocol HomePageContinueSetUpModelPersisting {
    var shouldShowMakeDefaultSetting: Bool { get set }
    var shouldShowAddToDockSetting: Bool { get set }
    var shouldShowImportSetting: Bool { get set }
    var shouldShowDuckPlayerSetting: Bool { get set }
    var shouldShowEmailProtectionSetting: Bool { get set }
    var isFirstSession: Bool { get set }
    func clear()
}

struct HomePageContinueSetUpModelPersistor: HomePageContinueSetUpModelPersisting {
    private let keyValueStore: KeyValueStoring

    enum Key: String {
        case homePageShowMakeDefault = "home.page.show.make.default"
        case homePageShowAddToDock = "home.page.show.add.to.dock"
        case homePageShowImport = "home.page.show.import"
        case homePageShowDuckPlayer = "home.page.show.duck.player"
        case homePageShowEmailProtection = "home.page.show.email.protection"
        case homePageIsFirstSession = "home.page.is.first.session"
    }

    init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var shouldShowMakeDefaultSetting: Bool {
        get { keyValueStore.object(forKey: Key.homePageShowMakeDefault.rawValue) as? Bool ?? true }
        set { keyValueStore.set(newValue, forKey: Key.homePageShowMakeDefault.rawValue) }
    }

    var shouldShowAddToDockSetting: Bool {
        get { keyValueStore.object(forKey: Key.homePageShowAddToDock.rawValue) as? Bool ?? true }
        set { keyValueStore.set(newValue, forKey: Key.homePageShowAddToDock.rawValue) }
    }

    var shouldShowImportSetting: Bool {
        get { keyValueStore.object(forKey: Key.homePageShowImport.rawValue) as? Bool ?? true }
        set { keyValueStore.set(newValue, forKey: Key.homePageShowImport.rawValue) }
    }

    var shouldShowDuckPlayerSetting: Bool {
        get { keyValueStore.object(forKey: Key.homePageShowDuckPlayer.rawValue) as? Bool ?? true }
        set { keyValueStore.set(newValue, forKey: Key.homePageShowDuckPlayer.rawValue) }
    }

    var shouldShowEmailProtectionSetting: Bool {
        get { keyValueStore.object(forKey: Key.homePageShowEmailProtection.rawValue) as? Bool ?? true }
        set { keyValueStore.set(newValue, forKey: Key.homePageShowEmailProtection.rawValue) }
    }

    var isFirstSession: Bool {
        get { keyValueStore.object(forKey: Key.homePageIsFirstSession.rawValue) as? Bool ?? true }
        set { keyValueStore.set(newValue, forKey: Key.homePageIsFirstSession.rawValue) }
    }

    func clear() {
        keyValueStore.removeObject(forKey: Key.homePageShowMakeDefault.rawValue)
        keyValueStore.removeObject(forKey: Key.homePageShowAddToDock.rawValue)
        keyValueStore.removeObject(forKey: Key.homePageShowImport.rawValue)
        keyValueStore.removeObject(forKey: Key.homePageShowDuckPlayer.rawValue)
        keyValueStore.removeObject(forKey: Key.homePageShowEmailProtection.rawValue)
        keyValueStore.removeObject(forKey: Key.homePageIsFirstSession.rawValue)
    }
}
