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
