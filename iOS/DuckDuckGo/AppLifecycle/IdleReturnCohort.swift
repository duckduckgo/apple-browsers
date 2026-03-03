//
//  IdleReturnCohort.swift
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
import BrowserServicesKit
import Persistence

/// Sets the "new user" flag for after-inactivity default once per install.
/// New user (install after feature launch) = no install statistics yet when we first run.
/// Old user (already using app) = has install statistics. We never write Last Used Tab;
/// Settings/eligibility use this flag to decide: new → save NTP, old → effective Last Used Tab only (don't save).
enum IdleReturnCohort {

    /// Call early at launch (sync), before StatisticsLoader completes, so new installs still have `hasInstallStatistics == false`.
    /// Sets `idleReturnNewUser` in storage: true if new user, false if old. Only runs once (when flag not yet set).
    static func setIfNeeded(statisticsStore: StatisticsStore, keyValueStore: ThrowingKeyValueStoring) {
        let store: any ThrowingKeyedStoring<AfterInactivitySettingKeys> = keyValueStore.throwingKeyedStoring()
        if (try? store.value(for: \AfterInactivitySettingKeys.idleReturnNewUser)) != nil {
            return
        }
        if (try? store.value(for: \AfterInactivitySettingKeys.afterInactivityOption)) != nil {
            try? store.set(false, for: \AfterInactivitySettingKeys.idleReturnNewUser)
            return
        }
        try? store.set(!statisticsStore.hasInstallStatistics, for: \AfterInactivitySettingKeys.idleReturnNewUser)
    }
}
