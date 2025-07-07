//
//  DefaultBrowserPromptTypeDecider.swift
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

package enum DefaultBrowserPromptType: CustomDebugStringConvertible {
    case firstModal
    case secondModal
    case subsequentModal

    package var debugDescription: String {
        switch self {
        case .firstModal:
            return "First modal"
        case .secondModal:
            return "Second modal"
        case .subsequentModal:
            return "Subsequent modal"
        }
    }
}

@MainActor
package protocol DefaultBrowserPromptTypeDeciding {
    func promptType() -> DefaultBrowserPromptType?
}

@MainActor
package final class DefaultBrowserPromptTypeDecider: DefaultBrowserPromptTypeDeciding {
    private let featureFlagger: DefaultBrowserPromptFeatureFlagger
    private let store: DefaultBrowserPromptStorage
    private let userTypeProvider: DefaultBrowserPromptUserTypeProviding
    private let userActivityProvider: DefaultBrowserPromptUserActivityProvider
    private let defaultBrowserManager: DefaultBrowserManaging
    private let installDateProvider: () -> Date?
    private let dateProvider: () -> Date

    package init(
        featureFlagger: DefaultBrowserPromptFeatureFlagger,
        store: DefaultBrowserPromptStorage,
        userTypeProvider: DefaultBrowserPromptUserTypeProviding,
        userActivityProvider: DefaultBrowserPromptUserActivityProvider,
        defaultBrowserManager: DefaultBrowserManaging,
        installDateProvider: @escaping () -> Date?,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.featureFlagger = featureFlagger
        self.store = store
        self.userTypeProvider = userTypeProvider
        self.userActivityProvider = userActivityProvider
        self.installDateProvider = installDateProvider
        self.defaultBrowserManager = defaultBrowserManager
        self.dateProvider = dateProvider
    }

    package func promptType() -> DefaultBrowserPromptType? {
        // If Feature is disabled return nil
        guard featureFlagger.isDefaultBrowserPromptsFeatureEnabled else {
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Feature disabled.")
            return nil
        }

        // If user has permanently disabled prompt return nil
        guard !store.isPromptPermanentlyDismissed else {
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Prompt Permanently Dismissed. Will not show prompt.")
            return nil
        }

        guard let userType = userTypeProvider.currentUserType() else {
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Failed to determine user type. Will not show prompt.")
            return nil
        }

        // Check if we should be using first, second or subsequent modal depending on the user type.
        guard let modalToShow = determineModalType(for: userType) else {
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - No Modal To Show.")
            return nil
        }

        Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Modal To Show Before Assessing Default Browser \(modalToShow.debugDescription).")

        // If browser is not the default one show the modal otherwise do not show it again.
        return defaultBrowserManager.defaultBrowserInfo().isEligibleToShowDefaultBrowserPrompt() ? modalToShow : nil
    }

}

// MARK: - Private

private extension DefaultBrowserPromptTypeDecider {

    func determineModalType(for user: DefaultBrowserPromptUserType) -> DefaultBrowserPromptType? {
        if shouldShowFirstModal() {
            return .firstModal
        } else if shouldShowSecondModal(for: user) {
            return .secondModal
        } else if shouldShowSubsequentModal(for: user) {
            return .subsequentModal
        } else {
            return nil
        }
    }

    // If the user has not seen the first modal, they have installed the app at least `firstModalDelayDays` ago, show the first modal.
    func shouldShowFirstModal() -> Bool {
        !store.hasSeenFirstModal &&
        daysSinceInstall() >= featureFlagger.firstModalDelayDays
    }

    // If the user has seen the first modal but they have not seen the second modal and they have been active for `secondModalDelayDays`, show the second modal.
    func shouldShowSecondModal(for user: DefaultBrowserPromptUserType) -> Bool {
        user.isNewOrReturningUser &&
        !store.hasSeenSecondModal &&
        userActivityProvider.numberOfActiveDays() == featureFlagger.secondModalDelayDays
    }

    // If the user has seen the last modal and they have been active for `secondModalDelayDays`, show the second modal.
    func shouldShowSubsequentModal(for user: DefaultBrowserPromptUserType) -> Bool {
        let modalSeenCondition = user.isNewOrReturningUser ? store.hasSeenSecondModal : store.hasSeenFirstModal

        return modalSeenCondition &&
        userActivityProvider.numberOfActiveDays() == featureFlagger.subsequentModalRepeatIntervalDays
    }

    func daysSinceInstall() -> Int {
        daysSince(date: installDateProvider())
    }

    func daysSince(date: Date?) -> Int {
        guard
            let date,
            let numberOfDays = Calendar.current.dateComponents([.day], from: date, to: dateProvider()).day
        else {
            return 0
        }

        return numberOfDays
    }

}

// MARK: - Private

private extension DefaultBrowserInfoResult {

    func isEligibleToShowDefaultBrowserPrompt() -> Bool {
        guard case let .success(newInfo) = self else { return false }
        return !newInfo.isDefaultBrowser
    }

}
