//
//  IdleReturnEligibilityManager.swift
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
import Core
import Persistence

/// Answers whether the user is eligible for "NTP after idle" (and optionally the effective preference).
/// Uses shared effective-option logic from storage; no separate user-status input.
protocol IdleReturnEligibilityManaging {
    func isEligibleForNTPAfterIdle() -> Bool
    func effectiveAfterInactivityOption() -> AfterInactivityOption
}

final class IdleReturnEligibilityManager: IdleReturnEligibilityManaging {

    private let featureFlagger: FeatureFlagger
    private let keyValueStore: ThrowingKeyValueStoring

    init(featureFlagger: FeatureFlagger, keyValueStore: ThrowingKeyValueStoring) {
        self.featureFlagger = featureFlagger
        self.keyValueStore = keyValueStore
    }

    func isEligibleForNTPAfterIdle() -> Bool {
        featureFlagger.isFeatureOn(.showNTPAfterIdleReturn) && effectiveAfterInactivityOption() == .newTab
    }

    func effectiveAfterInactivityOption() -> AfterInactivityOption {
        let storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = keyValueStore.throwingKeyedStoring()
        let resolver = AfterInactivityEffectiveOptionResolver(storage: storage)
        return resolver.resolveEffectiveOption()
    }
}
