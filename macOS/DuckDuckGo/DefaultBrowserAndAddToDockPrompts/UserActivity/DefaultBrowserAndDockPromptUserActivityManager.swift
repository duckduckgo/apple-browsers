//
//  DefaultBrowserAndDockPromptUserActivityManager.swift
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
import Combine

/// A type that records the user activity information for SAD & ATD prompt decisions.
protocol DefaultBrowserAndDockPromptUserActivityRecorder {
    func recordActivity()
}

/// A monitor that measures user activity for the SAD & ATD prompt feature.
///
/// This class observes application lifecycle events to automatically measure when users
/// are active and stores this information to the provided store.
final class DefaultBrowserAndDockPromptUserActivityManager: DefaultBrowserAndDockPromptUserActivityRecorder, DefaultBrowserAndDockPromptUserActivityProvider {
    let store: DefaultBrowserAndDockPromptUserActivityStorage
    private let dateProvider: () -> Date
    private let calendar: Calendar

    /// Creates a new activity monitor with the specified configuration.
    ///
    /// The monitor immediately begins observing application lifecycle notifications to measure user activity.
    ///
    /// - Parameters:
    ///   - store: The storage implementation used to persist activity data.
    ///   - dateProvider: A closure that provides the current date. Defaults to `Date.init`. This parameter is primarily useful for testing.
    ///   - calendar: The calendar used for date calculations. Defaults to `.current`, which uses the user's system calendar settings.
    init(
        store: DefaultBrowserAndDockPromptUserActivityStorage,
        dateProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.dateProvider = dateProvider
        self.calendar = calendar
    }

    func recordActivity() {
        let today = calendar.startOfDay(for: dateProvider())

        let currentActivity = store.currentActivity()

        // If we already measured today, skip.
        if let lastActive = currentActivity.lastActiveDate, calendar.isDate(lastActive, inSameDayAs: today) {
            return
        }

        // If last active date is nil it means that we are running the code for the first time. In that case the last activity and second last activity should be the same day.
        // The second last active day will be used to calculate the number of inactive days from `lastActiveDate`.
        let lastActiveDate = today
        let secondLastActiveDate = currentActivity.lastActiveDate ?? lastActiveDate

        let newActivity = DefaultBrowserAndDockPromptUserActivity(lastActiveDate: lastActiveDate, secondLastActiveDate: secondLastActiveDate)
        store.save(newActivity)
    }

    func numberOfInactiveDays() -> Int {
        let currentActivity = store.currentActivity()
        guard let lastActiveDate = currentActivity.lastActiveDate, let secondLastActiveDate = currentActivity.secondLastActiveDate else { return 0 }
        let daysSincePreviouslyActive = calendar.numberOfDaysBetween(calendar.startOfDay(for: secondLastActiveDate), and: calendar.startOfDay(for: lastActiveDate)) ?? 0
        return max(0, daysSincePreviouslyActive - 1) // Exclude the current and previous active days
    }
}
