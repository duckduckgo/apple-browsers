//
//  HomePageSetUpDependencies.swift
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
import Subscription
import Persistence

final class HomePageSetUpDependencies {
    let subscriptionCardVisibilityManager: HomePageSubscriptionCardVisibilityManaging
    let subscriptionCardPersistor: HomePageSubscriptionCardPersisting
    let continueSetUpModelPersistor: HomePageContinueSetUpModelPersisting

    init(subscriptionManager: SubscriptionAuthV1toV2Bridge, keyValueStore: ThrowingKeyValueStoring, legacyKeyValueStore: KeyValueStoring) {
        self.subscriptionCardPersistor = HomePageSubscriptionCardPersistor(keyValueStore: keyValueStore)
        self.subscriptionCardVisibilityManager = HomePageSubscriptionCardVisibilityManager(
            subscriptionManager: subscriptionManager,
            persistor: subscriptionCardPersistor
        )
        self.continueSetUpModelPersistor = HomePageContinueSetUpModelPersistor(
            keyValueStore: legacyKeyValueStore
        )
    }

    func clearAll() {
        subscriptionCardPersistor.clear()
        continueSetUpModelPersistor.clear()
    }
}
