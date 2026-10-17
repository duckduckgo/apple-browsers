//
//  DateExtension.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public extension Date {

    struct IndexedMonth: Hashable {
        public let name: String
        public let index: Int
    }

    /// Extracts day, month, and year components from the date.
    var components: DateComponents {
        Calendar.current.dateComponents([.day, .year, .month], from: self)
    }

    /// Returns the date exactly one week ago.
    static var weekAgo: Date {
        guard let date = Calendar.current.date(byAdding: .weekOfMonth, value: -1, to: Date()) else {
            fatalError("Unable to calculate a week ago date.")
        }
        return date
    }

    /// Returns the date exactly one month ago.
    static var monthAgo: Date {
        guard let date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) else {
            fatalError("Unable to calculate a month ago date.")
        }
        return date
    }

    /// Returns the date exactly one year ago.
    static var yearAgo: Date {
        guard let date = Calendar.current.date(byAdding: .year, value: -1, to: Date()) else {
            fatalError("Unable to calculate a year ago date.")
        }
        return date
    }

    /// Returns the date exactly one year from now.
    static var aYearFromNow: Date {
        guard let date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) else {
            fatalError("Unable to calculate a year from now date.")
        }
        return date
    }

    /// Returns the date a specific number of days ago.
    static func daysAgo(_ days: Int) -> Date {
        guard let date = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            fatalError("Unable to calculate \(days) days ago date.")
        }
        return date
    }

    /// Checks if two dates fall on the same calendar day.
    static func isSameDay(_ date1: Date, _ date2: Date?) -> Bool {
        guard let date2 = date2 else { return false }
        return Calendar.current.isDate(date1, inSameDayAs: date2)
    }

    /// Returns the start of tomorrow's day.
    static var startOfDayTomorrow: Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        return Calendar.current.startOfDay(for: tomorrow)
    }

    /// Returns the start of today's day.
    static var startOfDayToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Returns the start of the day for this date instance.
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// Returns the date a specific number of days ago from this date instance.
    func daysAgo(_ days: Int) -> Date {
        guard let date = Calendar.current.date(byAdding: .day, value: -days, to: self) else {
            fatalError("Unable to calculate \(days) days ago date from this instance.")
        }
        return date
    }

    /// Returns the start of the current minute.
    static var startOfMinuteNow: Date {
        guard let date = Calendar.current.date(bySetting: .second, value: 0, of: Date()),
              let start = Calendar.current.date(byAdding: .minute, value: -1, to: date) else {
            fatalError("Unable to calculate the start of the current minute.")
        }
        return start
    }

    /// Provides a list of months with their names and indices.
    static var monthsWithIndex: [IndexedMonth] {
        Calendar.current.monthSymbols.enumerated().map { index, month in
            IndexedMonth(name: month, index: index + 1)
        }
    }

    /// Provides a list of days in a month (1 through 31).
    static let daysInMonth = Array(1...31)

    /// Provides a list of the next ten years including the current year.
    static var nextTenYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return (0...10).map { currentYear + $0 }
    }

    /// Provides a list of the last hundred years including the current year.
    static var lastHundredYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return (0...100).map { currentYear - $0 }
    }

    /// Returns the number of whole days since the reference date (January 1, 2001).
    var daySinceReferenceDate: Int {
        Int(self.timeIntervalSinceReferenceDate / TimeInterval.day)
    }

    /// Checks if this date falls on the same calendar day as another date.
    func isSameDay(_ otherDate: Date?) -> Bool {
        guard let otherDate = otherDate else { return false }
        return Calendar.current.isDate(self, inSameDayAs: otherDate)
    }

    /// Checks if this date is within a certain number of days ago.
    func isLessThan(daysAgo days: Int) -> Bool {
        self > Date().addingTimeInterval(Double(-days) * TimeInterval.day)
    }

    /// Checks if this date is within a certain number of minutes ago.
    func isLessThan(minutesAgo minutes: Int) -> Bool {
        self > Date().addingTimeInterval(Double(-minutes) * 60)
    }

    /// Returns the number of seconds since this date until now.
    func secondsSinceNow() -> Int {
        Int(Date().timeIntervalSince(self))
    }

    /// Returns the number of seconds since this date until now.
    func secondsFromNow() -> Int {
        Int(self.timeIntervalSince(Date()))
    }

    /// The number of minutes since this date until now.
    /// Returns a negative number if self is in the future.
    func minutesSinceNow() -> Int {
        Int(secondsSinceNow()) / 60
    }

    /// The number of hours since this date until now.
    /// Returns a negative number if self is in the future.
    func hoursSinceNow() -> Int {
        minutesSinceNow() / 60
    }

    /// The number of days since this date until now.
    /// Returns a negative number if self is in the future.
    func daysSinceNow() -> Int {
        hoursSinceNow() / 24
    }

    /// The number of months since this date until now.
    /// Returns a negative number if self is in the future.
    func monthsSinceNow() -> Int {
        Calendar.current.dateComponents([.month], from: self, to: Date()).month ?? 0
    }

    /// The number of years since this date until now.
    /// Returns a negative number if self is in the future.
    func yearsSinceNow() -> Int {
        Calendar.current.dateComponents([.year], from: self, to: Date()).year ?? 0
    }

    func isInThePast() -> Bool {
        return self < Date()
    }

    func isInTheFuture() -> Bool {
        return self > Date()
    }
}
