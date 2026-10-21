//
//  DuckAIFirstPromptNewInstallCohort.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Foundation
import Persistence

/// Launch-time gate for the prompt pixels' `first_prompt_new_install`: installs that predate it are
/// marked as having prompted, so only a brand-new install's first prompt can report it.
enum DuckAIFirstPromptNewInstallCohort {

    static let cohortAssignedKey = "com.duckduckgo.aichat.firstPromptNewInstall.cohortAssigned"

    /// Must run before the statistics load, which makes every install look existing. The marker
    /// stops a new install's second launch from marking it before its first prompt.
    static func assignIfNeeded(statisticsStore: StatisticsStore,
                               featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery(),
                               marker: KeyValueStoring = UserDefaults.standard) {
        guard marker.object(forKey: cohortAssignedKey) == nil else { return }
        if statisticsStore.hasInstallStatistics {
            featureDiscovery.setWasUsedBefore(.duckAIPrompt)
        }
        marker.set(true, forKey: cohortAssignedKey)
    }
}
