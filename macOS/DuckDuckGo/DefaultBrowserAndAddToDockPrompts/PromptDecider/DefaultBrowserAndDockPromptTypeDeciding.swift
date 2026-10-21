//
//  DefaultBrowserAndDockPromptTypeDeciding.swift
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

protocol DefaultBrowserAndDockPromptTypeDeciding {
    func promptType() -> DefaultBrowserAndDockPromptPresentationType?
}

final class DefaultBrowserAndDockPromptTypeDecider: DefaultBrowserAndDockPromptTypeDeciding {
    private let featureFlagger: DefaultBrowserAndDockPromptFeatureFlagger
    private let store: DefaultBrowserAndDockPromptStorageReading
    private let activeUserPromptDecider: DefaultBrowserAndDockPromptTypeDeciding
    private let inactiveUserPromptDecider: DefaultBrowserAndDockPromptTypeDeciding
    private let dateProvider: () -> Date

    init(
        featureFlagger: DefaultBrowserAndDockPromptFeatureFlagger,
        store: DefaultBrowserAndDockPromptStorageReading,
        userActivityProvider: DefaultBrowserAndDockPromptUserActivityProvider,
        activeUserPromptDecider: DefaultBrowserAndDockPromptTypeDeciding? = nil,
        inactiveUserPromptDecider: DefaultBrowserAndDockPromptTypeDeciding? = nil,
        installDateProvider: @escaping () -> Date?,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        let daysSince: (Date?) -> Int = { date in
            guard let date else { return 0 }
            return Calendar.current.numberOfDaysBetween(date, and: dateProvider()) ?? 0
        }

        let daysSinceInstall: () -> Int = {
            daysSince(installDateProvider())
        }

        self.featureFlagger = featureFlagger
        self.store = store
        self.dateProvider = dateProvider
        self.activeUserPromptDecider = activeUserPromptDecider ?? ActiveUser(featureFlagger: featureFlagger,
                                                                             store: store,
                                                                             daysSinceInstallProvider: daysSinceInstall,
                                                                             daysSinceProvider: daysSince)
        self.inactiveUserPromptDecider = inactiveUserPromptDecider ?? InactiveUser(featureFlagger: featureFlagger,
                                                                                   store: store,
                                                                                   userActivityProvider: userActivityProvider,
                                                                                   daysSinceInstallProvider: daysSinceInstall)
    }

    /// **TIMING LOGIC DISPATCHER**
    ///
    /// Called by `DefaultBrowserAndDockPromptCoordinator.getPromptType()` to determine if timing conditions are met.
    /// This is where the timing rules are enforced.
    ///
    /// **Global Checks (apply to all prompts):**
    /// 1. **Permanent dismissal**: If user clicked "Never Ask Again" on banner → returns nil
    /// 2. **Daily limit**: If any prompt already shown today → returns nil (prevents spam)
    ///
    /// **Priority Order:**
    /// 1. **Inactive user prompt** (checked first, highest priority)
    ///    - See `DefaultBrowserAndDockPromptTypeDecider.InactiveUser`
    /// 2. **Active user prompts** (popover or banner)
    ///    - See `DefaultBrowserAndDockPromptTypeDecider.ActiveUser`
    ///
    /// **Remote Configuration:**
    /// All timing thresholds (install delay, popover→banner delay, banner repeat interval, inactive user thresholds) come from
    /// `DefaultBrowserAndDockPromptFeatureFlagger` so the schedule can be fine-tuned via Privacy Config.
    ///
    /// **See also:**
    /// - `DefaultBrowserAndDockPromptTypeDecider.ActiveUser.promptType()` - active user timing
    /// - `DefaultBrowserAndDockPromptTypeDecider.InactiveUser.promptType()` - inactive user timing
    /// - `hasAlreadySeenAnyModalToday()` - daily limit check
    func promptType() -> DefaultBrowserAndDockPromptPresentationType? {
        // If user has permanently disabled prompt or user has already seen any prompt today do not show another one.
        guard !store.isBannerPermanentlyDismissed, !hasAlreadySeenAnyModalToday() else {
            return nil
        }

        // First, check if we need to display the prompt for inactive users.
        // Second, check if we need to display one of the prompt for active users.
        if let inactivePrompt = inactiveUserPromptDecider.promptType() {
            return inactivePrompt
        } else if let activePrompt = activeUserPromptDecider.promptType() {
            return activePrompt
        } else {
            return nil
        }
    }

}

private extension DefaultBrowserAndDockPromptTypeDecider {
    func hasAlreadySeenAnyModalToday() -> Bool {
        guard let lastModalShownDate = store.lastPromptShownDate else { return false }
        return Calendar.current.isDate(Date(timeIntervalSince1970: lastModalShownDate), inSameDayAs: dateProvider())
    }
}
