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

package enum DefaultBrowserPromptType: Equatable, CustomDebugStringConvertible {

    case inactive
    case active(ActiveUserPrompt)

    package var debugDescription: String {
        switch self {
        case .inactive:
            return "Inactive Modal"
        case let .active(prompt):
            return "Active \(prompt.debugDescription)"
        }
    }
}

package extension DefaultBrowserPromptType {

    enum ActiveUserPrompt: Equatable, CustomDebugStringConvertible {
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

}

@MainActor
package protocol DefaultBrowserPromptTypeDeciding {
    func promptType() -> DefaultBrowserPromptType?
    /// Revalidates prepared work from cached browser status without consuming selection state.
    func isPreparedPromptStillValid() -> Bool
    /// Revalidates retained work using a fresh browser-status check before retrying presentation.
    /// A failed check falls back to the stored status rather than invalidating the retained work.
    func isRetainedPreparedPromptStillValid() -> Bool
}

package extension DefaultBrowserPromptTypeDeciding {
    func isPreparedPromptStillValid() -> Bool {
        true
    }

    func isRetainedPreparedPromptStillValid() -> Bool {
        isPreparedPromptStillValid()
    }
}

@MainActor
package final class DefaultBrowserPromptTypeDecider: DefaultBrowserPromptTypeDeciding {
    private let featureFlagger: DefaultBrowserPromptFeatureFlagger
    private let store: DefaultBrowserPromptStorage
    private let activeUserPromptDecider: DefaultBrowserPromptTypeDeciding
    private let inactiveUserPromptDecider: DefaultBrowserPromptTypeDeciding
    private let defaultBrowserManager: DefaultBrowserManaging
    private let installDateProvider: () -> Date?
    private let dateProvider: () -> Date

    init(
        featureFlagger: DefaultBrowserPromptFeatureFlagger,
        store: DefaultBrowserPromptStorage,
        activeUserPromptDecider: DefaultBrowserPromptTypeDeciding,
        inactiveUserPromptDecider: DefaultBrowserPromptTypeDeciding,
        defaultBrowserManager: DefaultBrowserManaging,
        installDateProvider: @escaping () -> Date?,
        dateProvider: @escaping () -> Date
    ) {
        self.featureFlagger = featureFlagger
        self.store = store
        self.activeUserPromptDecider = activeUserPromptDecider
        self.inactiveUserPromptDecider = inactiveUserPromptDecider
        self.installDateProvider = installDateProvider
        self.defaultBrowserManager = defaultBrowserManager
        self.dateProvider = dateProvider
    }

    package convenience init(
        featureFlagger: DefaultBrowserPromptFeatureFlagger,
        store: DefaultBrowserPromptStorage,
        userTypeProvider: DefaultBrowserPromptUserTypeProviding,
        userActivityProvider: DefaultBrowserPromptUserActivityProvider,
        defaultBrowserManager: DefaultBrowserManaging,
        installDateProvider: @escaping () -> Date?,
        dateProvider: @escaping () -> Date = Date.init
    ) {

        let daysSinceInstall: () -> Int = {
            guard
                let date = installDateProvider(),
                let numberOfDays = Calendar.current.dateComponents([.day], from: date, to: dateProvider()).day
            else {
                return 0
            }

            return numberOfDays
        }

        let activeUserPromptDecider = DefaultBrowserPromptTypeDecider.ActiveUser(
            featureFlagger: featureFlagger,
            store: store,
            userTypeProvider: userTypeProvider,
            userActivityProvider: userActivityProvider,
            daysSinceInstallProvider: daysSinceInstall
        )

        let inactiveUserPromptDecider = DefaultBrowserPromptTypeDecider.InactiveUser(
            featureFlagger: featureFlagger,
            store: store,
            userActivityProvider: userActivityProvider,
            daysSinceInstallProvider: daysSinceInstall
        )

        self.init(
            featureFlagger: featureFlagger,
            store: store,
            activeUserPromptDecider: activeUserPromptDecider,
            inactiveUserPromptDecider: inactiveUserPromptDecider,
            defaultBrowserManager: defaultBrowserManager,
            installDateProvider: installDateProvider,
            dateProvider: dateProvider
        )
    }

    package func promptType() -> DefaultBrowserPromptType? {
        // If user has permanently disabled prompt return nil
        guard !store.isPromptPermanentlyDismissed else {
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Prompt Permanently Dismissed. Will not show prompt.")
            return nil
        }

        // Check what prompt to show
        Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Deciding what prompt to show.")
        guard let promptToShow = decidePromptType() else {
            Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - No Prompt To Show.")
            return nil
        }

        Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Modal To Show Before Assessing Default Browser \(promptToShow.debugDescription).")
        // If browser is not the default one show the modal otherwise do not show it again.
        return defaultBrowserManager.defaultBrowserInfo().isEligibleToShowDefaultBrowserPrompt() ? promptToShow : nil
    }

    package func isPreparedPromptStillValid() -> Bool {
        guard let storedInfo = defaultBrowserManager.storedDefaultBrowserInfo() else {
            return true
        }
        return storedInfo.isEligibleToShowDefaultBrowserPrompt()
    }

    package func isRetainedPreparedPromptStillValid() -> Bool {
        switch defaultBrowserManager.defaultBrowserInfo() {
        case let .success(newInfo):
            return newInfo.isEligibleToShowDefaultBrowserPrompt()
        case .failure:
            // The OS status check is rate limited, and the retained prompt already consumed its
            // selection state, so a failed check must not discard it. Fall back to the stored
            // status, which a rate-limited check refreshes before failing.
            return isPreparedPromptStillValid()
        }
    }

}

// MARK: - Private

private extension DefaultBrowserPromptTypeDecider {

    func decidePromptType() -> DefaultBrowserPromptType? {
        // First, check if we need to display the prompt for inactive users.
        // Second, check if we need to display one of the prompt for active users.
        // Note: Cooldown is now managed globally within the client in (See PromoCoordinationService).
        if let inactivePrompt = inactiveUserPromptDecider.promptType() {
            return inactivePrompt
        } else if let activePrompt = activeUserPromptDecider.promptType() {
            return activePrompt
        } else {
            return nil
        }
    }

}

// MARK: - Private

private extension DefaultBrowserInfoResult {

    func isEligibleToShowDefaultBrowserPrompt() -> Bool {
        guard case let .success(newInfo) = self else { return false }
        return newInfo.isEligibleToShowDefaultBrowserPrompt()
    }

}

private extension DefaultBrowserContext {

    func isEligibleToShowDefaultBrowserPrompt() -> Bool {
        !isDefaultBrowser
    }

}
