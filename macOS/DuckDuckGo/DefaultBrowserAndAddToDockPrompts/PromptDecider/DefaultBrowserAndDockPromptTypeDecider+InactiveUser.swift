//
//  DefaultBrowserAndDockPromptTypeDecider+InactiveUser.swift
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

extension DefaultBrowserAndDockPromptTypeDecider {
    final class InactiveUser: DefaultBrowserAndDockPromptTypeDeciding {
        private let featureFlagger: DefaultBrowserAndDockPromptFeatureFlagger
        private let store: DefaultBrowserAndDockPromptStorageReading
        private let userActivityProvider: DefaultBrowserAndDockPromptUserActivityProvider
        private let daysSinceInstallProvider: () -> Int

        init(
            featureFlagger: DefaultBrowserAndDockPromptFeatureFlagger,
            store: DefaultBrowserAndDockPromptStorageReading,
            userActivityProvider: DefaultBrowserAndDockPromptUserActivityProvider,
            daysSinceInstallProvider: @escaping () -> Int
        ) {
            self.featureFlagger = featureFlagger
            self.store = store
            self.userActivityProvider = userActivityProvider
            self.daysSinceInstallProvider = daysSinceInstallProvider
        }

        /// **INACTIVE USER TIMING RULES**
        ///
        /// Implements the timing logic for inactive users (re-engagement modal).
        /// Called by `DefaultBrowserAndDockPromptTypeDecider.promptType()` - checked BEFORE active user prompts.
        ///
        /// **Conditions (ALL must be true):**
        /// 1. **Never seen before**: `!hasSeenInactiveUserModal` (shown only once, ever)
        /// 2. **Inactive period**: User hasn't opened app for ≥7 days (default: `inactiveModalNumberOfInactiveDays`)
        /// 3. **Install age**: App installed for ≥28 days (default: `inactiveModalNumberOfDaysSinceInstall`)
        ///
        /// **Inactivity Recording:**
        /// - `DefaultBrowserAndDockPromptUserActivityManager` records activity on app launch
        /// - Compares last activity date to current date
        /// - See `DefaultBrowserAndDockPromptService.applicationDidBecomeActive()`
        ///
        /// **Feature Flag:**
        /// - `FeatureFlag.scheduledDefaultBrowserAndDockPromptsInactiveUser` must be enabled
        ///
        /// **Priority:**
        /// - This prompt has HIGHER priority than active user prompts (popover/banner)
        /// - If conditions are met, this shows instead of popover/banner
        ///
        /// **Debug:**
        /// - Use Debug menu → "SAD/ATT Prompts" → "Inactive User Modal will show: [date]" to see when eligible
        /// - Simulating date alone won't trigger this - need actual inactivity period
        ///
        /// **See also:**
        /// - `DefaultBrowserAndDockPromptUserActivityManager` - records recent app usage days
        /// - `DefaultBrowserAndDockPromptFeatureFlagger` - timing values and feature flags
        func promptType() -> DefaultBrowserAndDockPromptPresentationType? {
            // If Feature is disabled return nil
            guard featureFlagger.isDefaultBrowserAndDockPromptForInactiveUsersFeatureEnabled else { return nil }

            // Conditions to show prompt for inactive users:
            // 1. The user has not seen this modal ever.
            // 2. User has been inactive for at least seven days.
            // 3. The user has installed the app for at least 28 days.
            let shouldShowInactiveModal = !store.hasSeenInactiveUserModal &&
                userActivityProvider.numberOfInactiveDays() >= featureFlagger.inactiveModalNumberOfInactiveDays &&
                daysSinceInstallProvider() >= featureFlagger.inactiveModalNumberOfDaysSinceInstall

            return shouldShowInactiveModal ? .inactive : nil
        }
    }
}
