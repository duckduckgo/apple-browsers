//
//  HomePageSubscriptionCardPersistor.swift
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

protocol HomePageSubscriptionCardPersisting {
    var shouldShowSubscriptionSetting: Bool { get set }
    var userHadSubscription: Bool { get set }
    func clear()
}

struct HomePageSubscriptionCardPersistor: HomePageSubscriptionCardPersisting {
    private let keyValueStore: ThrowingKeyValueStoring

    enum Key: String {
        case homePageShowSubscription = "home.page.show.subscription"
        case homePageUserHadSubscription = "home.page.user.had.subscription"
    }

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var shouldShowSubscriptionSetting: Bool {
        get { (try? keyValueStore.object(forKey: Key.homePageShowSubscription.rawValue) as? Bool) ?? true }
        set { try? keyValueStore.set(newValue, forKey: Key.homePageShowSubscription.rawValue) }
    }

    var userHadSubscription: Bool {
        get { (try? keyValueStore.object(forKey: Key.homePageUserHadSubscription.rawValue) as? Bool) ?? false }
        set { try? keyValueStore.set(newValue, forKey: Key.homePageUserHadSubscription.rawValue) }
    }

    func clear() {
        try? keyValueStore.removeObject(forKey: Key.homePageShowSubscription.rawValue)
        try? keyValueStore.removeObject(forKey: Key.homePageUserHadSubscription.rawValue)
    }
}
