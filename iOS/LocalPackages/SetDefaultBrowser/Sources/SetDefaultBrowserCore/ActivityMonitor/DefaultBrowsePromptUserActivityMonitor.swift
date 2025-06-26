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
@MainActor
package final class DefaultBrowsePromptUserActivityMonitor: DefaultBrowserPromptUserActivityManaging {
    private let store: DefaultBrowsePromptUserActivityStorage
    private let dateProvider: () -> Date
    private let calendar: Calendar

    private var notificationCancellable: AnyCancellable?

    /// Creates a new activity monitor with the specified configuration.
    ///
    /// The monitor immediately begins observing application lifecycle notifications to measure user activity. 
    ///
    /// - Parameters:
    ///   - store: The storage implementation used to persist activity data.
    ///   - dateProvider: A closure that provides the current date. Defaults to `Date.init`. This parameter is primarily useful for testing.
    ///   - calendar: The calendar used for date calculations. Defaults to `.current`, which uses the user's system calendar settings.
    package init(
        store: DefaultBrowsePromptUserActivityStorage,
        dateProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.dateProvider = dateProvider
        self.calendar = calendar
        setupNotifications()
    }

    package func numberOfActiveDays() -> Int {
        store.currentActivity().numberOfActiveDays
    }

    package func resetNumberOfActiveDays() {
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
        let today = calendar.startOfDay(for: dateProvider())

        var currentActivity = store.currentActivity()

        // If we already measured today, skip.
        if let lastActive = currentActivity.lastActiveDate, calendar.isDate(lastActive, inSameDayAs: today) {
            return
        }

        currentActivity.numberOfActiveDays += 1
        currentActivity.lastActiveDate = today
        store.save(currentActivity)
    }
}
