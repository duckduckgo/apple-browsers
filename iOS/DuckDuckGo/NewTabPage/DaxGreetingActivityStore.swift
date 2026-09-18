//
//  DaxGreetingActivityStore.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import Combine
import Foundation

private struct DaxGreetingActivity {
    var lastForegroundDate: Date?
    var foregroundOpenCount = 0
    var isFirstOpenOfDay = false
}

@MainActor
final class DaxGreetingActivityStore {
    private var activity = DaxGreetingActivity()
    private let readLastActiveDate: () -> Date?
    private let now: () -> Date
    private let calendarProvider: () -> Calendar
    private let isEnabled: () -> Bool
    private let changesSubject = PassthroughSubject<Void, Never>()

    var changes: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }

    init(readLastActiveDate: @escaping () -> Date? = { nil },
         now: @escaping () -> Date = Date.init,
         calendarProvider: @escaping () -> Calendar = { .current },
         isEnabled: @escaping () -> Bool) {
        self.readLastActiveDate = readLastActiveDate
        self.now = now
        self.calendarProvider = calendarProvider
        self.isEnabled = isEnabled
    }

    // Called before the existing daily-activity recorder updates its last-active date.
    func recordForegroundOpen() {
        guard isEnabled() else { return }
        let date = now()
        let calendar = calendarProvider()
        if let previous = activity.lastForegroundDate, calendar.isDate(previous, inSameDayAs: date), previous <= date {
            activity.foregroundOpenCount = min(activity.foregroundOpenCount, Int.max - 1) + 1
        } else {
            activity.foregroundOpenCount = 1
        }
        let wasActiveToday = readLastActiveDate().map { calendar.isDate($0, inSameDayAs: date) } ?? false
        activity.isFirstOpenOfDay = activity.foregroundOpenCount == 1 && !wasActiveToday
        activity.lastForegroundDate = date
        changesSubject.send()
    }

    func context(at date: Date, calendar: Calendar, appearance: DaxGreetingContext.Appearance?) -> DaxGreetingContext {
        func happenedToday(_ eventDate: Date?) -> Bool {
            guard let eventDate, eventDate <= date else { return false }
            return calendar.isDate(eventDate, inSameDayAs: date)
        }
        let opens = happenedToday(activity.lastForegroundDate) ? activity.foregroundOpenCount : 0
        return DaxGreetingContext(appearance: appearance,
                                  isFirstOpenOfDay: opens > 0 && activity.isFirstOpenOfDay,
                                  foregroundOpenCount: opens)
    }
}
