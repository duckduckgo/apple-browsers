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

/// Sets `idleReturnNewUser` once at launch (before statistics load) so that
/// `AfterInactivityEffectiveOptionResolver` can default new users to .newTab and existing users to .lastUsedTab.
/// Must run before StatisticsLoader.load() completes, otherwise a new user's first load would set hasInstallStatistics and we would misclassify them as existing.
/// New user = no install statistics yet (true); existing user = has install statistics from a previous session (false).
enum IdleReturnCohort {

    static func setCohortIfNeeded(
        storage: any ThrowingKeyedStoring<AfterInactivitySettingKeys>,
        statisticsStore: StatisticsStore
    ) {
        guard (try? storage.afterInactivityOption) == nil,
              (try? storage.idleReturnNewUser) == nil else {
            return
        }
        let isNewUser = !statisticsStore.hasInstallStatistics
        try? storage.set(isNewUser, for: \AfterInactivitySettingKeys.idleReturnNewUser)
    }
}
