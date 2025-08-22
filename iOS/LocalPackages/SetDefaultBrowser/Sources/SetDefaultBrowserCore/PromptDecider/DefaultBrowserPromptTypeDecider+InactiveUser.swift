//
//  DefaultBrowserPromptTypeDecider+InactiveUser.swift
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

extension DefaultBrowserPromptTypeDecider {

    final class InactiveUser: DefaultBrowserPromptTypeDeciding {
        private let featureFlagger: DefaultBrowserPromptInactiveUserFeatureFlagger
        private let store: DefaultBrowserPromptStorage
        private let userActivityProvider: DefaultBrowserPromptUserActivityProvider
        private let daysSinceInstallProvider: () -> Int

        init(
            featureFlagger: DefaultBrowserPromptInactiveUserFeatureFlagger,
            store: DefaultBrowserPromptStorage,
            userActivityProvider: DefaultBrowserPromptUserActivityProvider,
            daysSinceInstallProvider: @escaping () -> Int
        ) {
            self.featureFlagger = featureFlagger
            self.store = store
            self.userActivityProvider = userActivityProvider
            self.daysSinceInstallProvider = daysSinceInstallProvider
        }

        func promptType() -> DefaultBrowserPromptType? {
            guard featureFlagger.isDefaultBrowserPromptsForInactiveUsersFeatureEnabled else { return nil }

            // Conditions to show prompt for inactive users:
            // 1. The user has not seen this modal ever.
            // 2. User has been inactive for at least seven days.
            // 3. The user has installed the app for at least 28 days.
            let shouldShowInactiveModal = !store.hasInactiveModalShown &&
            userActivityProvider.numberOfInactiveDays() >= featureFlagger.inactiveModalNumberOfInactiveDays &&
            daysSinceInstallProvider() >= featureFlagger.inactiveModalNumberOfDaysSinceInstall

            return shouldShowInactiveModal ? .inactive : nil
        }
    }

}
