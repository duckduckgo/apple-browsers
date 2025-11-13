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
