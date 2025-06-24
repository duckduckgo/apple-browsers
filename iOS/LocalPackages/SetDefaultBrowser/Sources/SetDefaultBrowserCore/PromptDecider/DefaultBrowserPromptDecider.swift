//
//  DefaultBrowserPromptDecider.swift
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

enum DefaultBrowserPromptType {
    case firstModal
    case secondModal
    case subsequentModal
}

@MainActor
protocol DefaultBrowserPromptDeciding {
    func promptType() -> DefaultBrowserPromptType?
}

@MainActor
final class DefaultBrowserPromptDecider: DefaultBrowserPromptDeciding {
    private let featureFlagger: DefaultBrowserPromptFeatureFlagger
    private let store: DefaultBrowserPromptStorageReading
    private let userTypeProvider: DefaultBrowserPromptUserTypeProviding
    private let userActivityProvider: DefaultBrowserPromptUserActivityProvider
    private let defaultBrowserManager: DefaultBrowserManaging
    private let installDateProvider: () -> Date?
    private let dateProvider: () -> Date

    init(
        featureFlagger: DefaultBrowserPromptFeatureFlagger,
        store: DefaultBrowserPromptStorageReading,
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

    func promptType() -> DefaultBrowserPromptType? {
        // If Feature is disabled return nil
        guard featureFlagger.isDefaultBrowserPromptsFeatureEnabled else { return nil }

        // If user has permanently disabled prompt return nil
        guard !store.isPromptPermanentlyDismissed else { return nil }

        // Check if we should be using first, second or subsequent modal depending on the user type.
        guard let modalToShow = determineModalType(for: userTypeProvider.currentUserType()) else { return nil }

        // If browser is not the default one show the modal otherwise do not show it again.
        return !defaultBrowserManager.defaultBrowserInfo().isDefaultBrowser() ? modalToShow : nil
    }

}

// MARK: - Private

private extension DefaultBrowserPromptDecider {

    func determineModalType(for user: DefaultBrowserUserType) -> DefaultBrowserPromptType? {
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
    func shouldShowSecondModal(for user: DefaultBrowserUserType) -> Bool {
        user.isNewOrReturningUser &&
        !store.hasSeenSecondModal &&
        activeDaysSinceFirstModal() == featureFlagger.secondModalDelayDays
    }

    // If the user has seen the last modal and they have been active for `secondModalDelayDays`, show the second modal.
    func shouldShowSubsequentModal(for user: DefaultBrowserUserType) -> Bool {
        let modalSeenCondition = user.isNewOrReturningUser ? store.hasSeenSecondModal : store.hasSeenFirstModal

        return modalSeenCondition &&
        activeDaysSinceLastModal() == featureFlagger.subsequentModalRepeatIntervalDays
    }

    func daysSinceInstall() -> Int {
        daysSince(date: installDateProvider())
    }

    func activeDaysSinceFirstModal() -> Int {
        activeDaysSince(date: store.lastModalShownDate)
    }

    func activeDaysSinceLastModal() -> Int {
        activeDaysSince(date: store.lastModalShownDate)
    }

    func activeDaysSince(date: TimeInterval?) -> Int {
        guard let date else { return 0 }
        return userActivityProvider.numberOfActiveDays(since: Date(timeIntervalSince1970: date))
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
