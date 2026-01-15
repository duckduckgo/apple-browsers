//
//  WinBackOfferFactory.swift
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

import Foundation
import PrivacyConfig
import Common
import Persistence
import Subscription

enum WinBackOfferFactory {
    static func makeService(keyValueFilesStore: ThrowingKeyValueStoring,
                            featureFlagger: FeatureFlagger,
                            daxDialogs: DaxDialogs) -> WinBackOfferService {
        let winBackOfferVisibilityManager: WinBackOfferVisibilityManaging
#if DEBUG || ALPHA
        let winBackOfferDebugStore = WinBackOfferDebugStore(keyValueStore: keyValueFilesStore)
        winBackOfferVisibilityManager = WinBackOfferVisibilityManager(
            subscriptionManager: AppDependencyProvider.shared.subscriptionManager,
            winbackOfferStore: WinbackOfferStore(keyValueStore: keyValueFilesStore),
            winbackOfferFeatureFlagProvider: WinBackOfferFeatureFlagger(featureFlagger: featureFlagger),
            dateProvider: { winBackOfferDebugStore.simulatedTodayDate },
            timeBeforeOfferAvailability: .seconds(5)
        )
#else
        winBackOfferVisibilityManager = WinBackOfferVisibilityManager(
            subscriptionManager: AppDependencyProvider.shared.subscriptionManager,
            winbackOfferStore: WinbackOfferStore(keyValueStore: keyValueFilesStore),
            winbackOfferFeatureFlagProvider: WinBackOfferFeatureFlagger(featureFlagger: featureFlagger),
        )
#endif
        
        
        let winBackOfferService = WinBackOfferService(
            visibilityManager: winBackOfferVisibilityManager,
            isOnboardingCompletedProvider: { !daxDialogs.isEnabled }
        )
        
        return winBackOfferService
    }
}
