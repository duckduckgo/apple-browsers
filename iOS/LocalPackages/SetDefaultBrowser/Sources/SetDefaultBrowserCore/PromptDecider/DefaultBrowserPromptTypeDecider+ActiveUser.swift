//
//  DefaultBrowserPromptTypeDecider+ActiveUser.swift
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

    final class ActiveUser: DefaultBrowserPromptTypeDeciding {
        private let featureFlagger: DefaultBrowserPromptActiveUserFeatureFlagger
        private let store: DefaultBrowserPromptStorage
        private let userTypeProvider: DefaultBrowserPromptUserTypeProviding
        private let userActivityProvider: DefaultBrowserPromptUserActivityProvider
        private let daysSinceInstallProvider: () -> Int

        init(
            featureFlagger: DefaultBrowserPromptActiveUserFeatureFlagger,
            store: DefaultBrowserPromptStorage,
            userTypeProvider: DefaultBrowserPromptUserTypeProviding,
            userActivityProvider: DefaultBrowserPromptUserActivityProvider,
            daysSinceInstallProvider: @escaping () -> Int
        ) {
            self.featureFlagger = featureFlagger
            self.store = store
            self.userTypeProvider = userTypeProvider
            self.userActivityProvider = userActivityProvider
            self.daysSinceInstallProvider = daysSinceInstallProvider
        }


        func promptType() -> DefaultBrowserPromptType? {
            // If Feature is disabled return nil
            guard featureFlagger.isDefaultBrowserPromptsForActiveUsersFeatureEnabled else {
                Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Feature disabled.")
                return nil
            }

            guard let userType = userTypeProvider.currentUserType() else {
                Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Failed to determine Active user type. Will not show prompt.")
                return nil
            }

            // Check if we should be using first, second or subsequent modal depending on the user type.
            guard let modalToShow = determineModalType(for: userType) else {
                Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - No Active Modal To Show.")
                return nil
            }

            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Active Modal To Show Before Assessing Default Browser \(modalToShow.debugDescription).")
            return modalToShow
        }

        private func determineModalType(for user: DefaultBrowserPromptUserType) -> DefaultBrowserPromptType? {
            if shouldShowFirstModal() {
                return .active(.firstModal)
            } else if shouldShowSecondModal(for: user) {
                return .active(.secondModal)
            } else if shouldShowSubsequentModal(for: user) {
                return .active(.subsequentModal)
            } else {
                return nil
            }
        }

        // If the user has not seen the first modal, they have installed the app at least `firstModalDelayDays` ago, show the first modal.
        private func shouldShowFirstModal() -> Bool {
            !store.hasSeenFirstModal &&
            daysSinceInstallProvider() >= featureFlagger.firstActiveModalDelayDays
        }

        // If the user has seen the first modal but they have not seen the second modal and they have been active for `secondModalDelayDays`, show the second modal.
        private func shouldShowSecondModal(for user: DefaultBrowserPromptUserType) -> Bool {
            user.isNewOrReturningUser &&
            !store.hasSeenSecondModal &&
            userActivityProvider.numberOfActiveDays() == featureFlagger.secondActiveModalDelayDays
        }

        // If the user has seen the last modal and they have been active for `subsequentModalRepeatIntervalDays`, show the subsequentModalRepeatIntervalDays modal.
        private func shouldShowSubsequentModal(for user: DefaultBrowserPromptUserType) -> Bool {
            let modalSeenCondition = user.isNewOrReturningUser ? store.hasSeenSecondModal : store.hasSeenFirstModal

            return modalSeenCondition &&
            userActivityProvider.numberOfActiveDays() == featureFlagger.subsequentActiveModalRepeatIntervalDays
        }
    }

}
