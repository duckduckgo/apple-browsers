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
    private let installDateProvider: () -> Date?
    private let dateProvider: () -> Date

    init(
        featureFlagger: DefaultBrowserAndDockPromptFeatureFlagger,
        store: DefaultBrowserAndDockPromptStorageReading,
        installDateProvider: @escaping () -> Date?,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.featureFlagger = featureFlagger
        self.store = store
        self.installDateProvider = installDateProvider
        self.dateProvider = dateProvider
    }

    func promptType() -> DefaultBrowserAndDockPromptPresentationType? {
        // If Feature is disabled return nil
        guard featureFlagger.isDefaultBrowserAndDockPromptFeatureEnabled else { return nil }

        // If user has permanently disabled prompt return nil
        guard !store.isBannerPermanentlyDismissed else { return nil }

        // If the user has not seen the popover and if they have installed the app at least `bannerAfterPopoverDelayDays` ago, show the popover.
        // If the user has seen the popover but they have not seen the banner and they have seen the popover at least `bannerAfterPopoverDelayDays
        // If the user has seen not dismissed permanently the banner and the have seen the banner at least `bannerRepeatIntervalDays`, show the banner again.
        if !store.hasSeenPopover && daysSinceInstall() >= featureFlagger.firstPopoverDelayDays {
            return .popover
        } else if !store.hasSeenBanner && daysSincePopoverShown() >= featureFlagger.bannerAfterPopoverDelayDays {
            return .banner
        } else if store.hasSeenBanner && daysSinceBannerShown() >= featureFlagger.bannerRepeatIntervalDays {
            return .banner
        } else {
            return nil
        }
    }

}

// MARK: - Private

private extension DefaultBrowserAndDockPromptTypeDecider {

    func daysSinceInstall() -> Int {
        daysSince(date: installDateProvider())
    }

    func daysSincePopoverShown() -> Int {
        daysSince(date: store.popoverShownDate.flatMap(Date.init(timeIntervalSince1970:)))
    }

    func daysSinceBannerShown() -> Int {
        daysSince(date: store.bannerShownDate.flatMap(Date.init(timeIntervalSince1970:)))
    }

    func daysSince(date: Date?) -> Int {
        guard let date else { return 0 }
        return Calendar.current.numberOfDaysBetween(date, and: dateProvider()) ?? 0
    }

}
