//
//  DefaultBrowsePromptUserActivityMonitor.swift
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
import class UIKit.UIApplication
import Combine

/// A monitor that measures user activity for the SAD prompt feature.
///
/// This class observes application lifecycle events to automatically measure when users
/// are active and stores this information to the provided store.
/// It maintains a rolling window of activity data based on the configured maximum days to keep.
@MainActor
public final class DefaultBrowsePromptUserActivityMonitor: DefaultBrowserPromptUserActivityMonitoring {
    private let store: DefaultBrowsePromptUserActivityStorage
    private let maxDaysToKeep: Int
    private let dateProvider: () -> Date
    private let calendar: Calendar

    private var notificationCancellable: AnyCancellable?

    /// Creates a new activity monitor with the specified configuration.
    ///
    /// The monitor immediately begins observing application lifecycle notifications to track user activity. Activity data older than `maxDaysToKeep` is
    /// automatically pruned to manage storage size.
    ///
    /// - Parameters:
    ///   - store: The storage implementation used to persist activity data.
    ///   - maxDaysToKeep: The maximum number of days of activity data to retain. Older data is automatically removed. Defaults to 30 days.
    ///   - dateProvider: A closure that provides the current date. Defaults to `Date.init`. This parameter is primarily useful for testing.
    ///   - calendar: The calendar used for date calculations. Defaults to `.current`, which uses the user's system calendar settings.
    public init(
        store: DefaultBrowsePromptUserActivityStorage,
        maxDaysToKeep: Int = 30,
        dateProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.maxDaysToKeep = maxDaysToKeep
        self.dateProvider = dateProvider
        self.calendar = calendar
        setupNotifications()
    }

    public func numberOfActiveDays(since date: Date) -> Int {
        let currentActivity = store.currentActivity()
        let startDay = startOfTheDay(date)
        return currentActivity.activeDates.filter { $0 >= startDay }.count

    }

    public func resetNumberOfActiveDays() {
        store.deleteActivity()
    }
}

// MARK: - Private

private extension DefaultBrowsePromptUserActivityMonitor {

    func setupNotifications() {
        notificationCancellable = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleDidBecomeActiveNotification()
            }
    }

    func handleDidBecomeActiveNotification() {
        let today = dateProvider()
        let startOfTheDay = calendar.startOfDay(for: today)

        var currentActivity = store.currentActivity()

        // If already tracked Today skip, otherwise insert
        if let lastActiveDate = currentActivity.lastActiveDate, isSameDay(lastActiveDate, startOfTheDay) {
            return
        }

        // Add today
        currentActivity.activeDates.insert(today)
        currentActivity.lastActiveDate = today

        // Clean up old dates
        if let cutoffDate = calendar.date(byAdding: .day, value: -maxDaysToKeep, to: today) {
            currentActivity.activeDates = currentActivity.activeDates.filter { $0 > cutoffDate }
        }

        // Save activity
        store.save(currentActivity)
    }

    func isSameDay(_ date1: Date, _ date2: Date) -> Bool {
        calendar.isDate(date1, inSameDayAs: date2)
    }

    func startOfTheDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

}
