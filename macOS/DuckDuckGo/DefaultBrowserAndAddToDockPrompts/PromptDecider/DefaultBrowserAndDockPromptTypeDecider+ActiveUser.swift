//
//  DefaultBrowserAndDockPromptTypeDecider+ActiveUser.swift
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
    final class ActiveUser: DefaultBrowserAndDockPromptTypeDeciding {
        private let featureFlagger: DefaultBrowserAndDockPromptFeatureFlagger
        private let store: DefaultBrowserAndDockPromptStorageReading
        private let daysSinceInstallProvider: () -> Int
        private let daysSinceProvider: (Date?) -> Int

        init(
            featureFlagger: DefaultBrowserAndDockPromptFeatureFlagger,
            store: DefaultBrowserAndDockPromptStorageReading,
            daysSinceInstallProvider: @escaping () -> Int,
            daysSinceProvider: @escaping (Date?) -> Int
        ) {
            self.featureFlagger = featureFlagger
            self.store = store
            self.daysSinceInstallProvider = daysSinceInstallProvider
            self.daysSinceProvider = daysSinceProvider
        }

        /// **ACTIVE USER TIMING RULES**
        ///
        /// Implements the timing logic for active users (popover → banner → repeat banner).
        /// Called by `DefaultBrowserAndDockPromptTypeDecider.promptType()`.
        ///
        /// **Timing Sequence (default values):**
        /// 1. **Popover** (first prompt):
        ///    - Shown once after ≥14 days from install (`firstPopoverDelayDays`)
        ///    - Condition: `!hasSeenPopover && daysSinceInstall >= 14`
        ///
        /// 2. **First Banner** (follow-up):
        ///    - Shown ≥14 days after popover was seen (`bannerAfterPopoverDelayDays`)
        ///    - Condition: `!hasSeenBanner && daysSincePopoverShown >= 14`
        ///
        /// 3. **Repeat Banner** (recurring):
        ///    - Shown every ≥14 days after last banner (`bannerRepeatIntervalDays`)
        ///    - Condition: `hasSeenBanner && daysSinceBannerShown >= 14`
        ///    - Stops if user clicks "Never Ask Again" (checked in parent)
        ///
        /// **Feature Flag:**
        /// - `FeatureFlag.scheduledSetDefaultBrowserAndAddToDockPrompts` must be enabled
        ///
        /// **Debug:**
        /// - Use Debug menu → "SAD/ATT Prompts" → "Simulate Today's Date" to fast-forward time
        /// - Use "Advance by 14 Days" to jump forward by the default delay interval
        /// - See menu items for calculated dates: "Popover will show: [date]", "First Banner will show: [date]"
        ///
        /// **See also:**
        /// - `DefaultBrowserAndDockPromptFeatureFlagger` - timing values and feature flags
        /// - `DefaultBrowserAndDockPromptDebugMenu` - debug tools for testing
        func promptType() -> DefaultBrowserAndDockPromptPresentationType? {
            // If Feature is disabled return nil
            guard featureFlagger.isDefaultBrowserAndDockPromptForActiveUsersFeatureEnabled else { return nil }

            // If the user has not seen the popover and if they have installed the app at least `bannerAfterPopoverDelayDays` ago, show the popover.
            // If the user has seen the popover but they have not seen the banner and they have seen the popover at least `bannerAfterPopoverDelayDays
            // If the user has seen not dismissed permanently the banner and the have seen the banner at least `bannerRepeatIntervalDays`, show the banner again.
            if !store.hasSeenPopover && daysSinceInstallProvider() >= featureFlagger.firstPopoverDelayDays {
                return .active(.popover)
            } else if !store.hasSeenBanner && daysSincePopoverShown() >= featureFlagger.bannerAfterPopoverDelayDays {
                return .active(.banner)
            } else if store.hasSeenBanner && daysSinceBannerShown() >= featureFlagger.bannerRepeatIntervalDays {
                return .active(.banner)
            } else {
                return nil
            }
        }

        private func daysSincePopoverShown() -> Int {
            daysSinceProvider(store.popoverShownDate.flatMap(Date.init(timeIntervalSince1970:)))
        }

        private func daysSinceBannerShown() -> Int {
            daysSinceProvider(store.bannerShownDate.flatMap(Date.init(timeIntervalSince1970:)))
        }
    }
}
