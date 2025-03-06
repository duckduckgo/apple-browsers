//
//  HistoryRangeExtension.swift
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

import Common
import Foundation

public extension DataModel.HistoryRange {

    /**
     * Initializes HistoryRange based on `date`s proximity to `referenceDate`.
     *
     * Possible values are:
     * - `today`,
     * - `yesterday`,
     * - week day name for 2-7 days ago,
     * - `older`.
     * - `nil` when `date` is newer than `referenceDate` (which shouldn't happen).
     */
    init?(date: Date, referenceDate: Date) {
        guard referenceDate >= date else {
            return nil
        }
        let calendar = Calendar.autoupdatingCurrent
        let numberOfDaysSinceReferenceDate = calendar.numberOfDaysBetween(date, and: referenceDate)

        switch numberOfDaysSinceReferenceDate {
        case 0:
            self = .today
        case 1:
            self = .yesterday
        default:
            let weekday = calendar.component(.weekday, from: date)
            if let numberOfDaysSinceReferenceDate, numberOfDaysSinceReferenceDate < 7, let range = DataModel.HistoryRange(weekday: weekday) {
                self = range
            } else {
                self = .older
            }
        }
    }

    /**
     * Calculates date range for the receiver, respective to `referenceDate` indicating current day.
     *
     * - Date range for `.today` is 00:00-23:59 on the current day, `.yesterday` is 00:00-23:59
     *   on the previous day, etc.
     * - `.older` range starts in distant past, while `.all` returns `nil`.
     */
    func dateRange(for referenceDate: Date) -> Range<Date>? {
        guard let weekday = weekday(for: referenceDate) else { // this covers .all range
            return nil
        }

        let calendar = Calendar.autoupdatingCurrent
        let startOfDayReferenceDate = referenceDate.startOfDay
        let startDate = self == .today ? startOfDayReferenceDate : calendar.firstWeekday(weekday, before: startOfDayReferenceDate)
        let nextDay = startDate.daysAgo(-1)

        guard self != .older else {
            return Date.distantPast ..< nextDay
        }

        return startDate ..< nextDay
    }

    /**
     * Calculates the date of the receiver, respective to `referenceDate` indicating current day.
     *
     * - `.older` and `.all` return `nil` because they span more than 1 day.
     */
    func date(for referenceDate: Date) -> Date? {
        guard self != .all, self != .older, let weekday = weekday(for: referenceDate) else {
            return nil
        }
        let calendar = Calendar.autoupdatingCurrent
        let startOfDayReferenceDate = referenceDate.startOfDay
        return self == .today ? startOfDayReferenceDate : calendar.firstWeekday(weekday, before: startOfDayReferenceDate)
    }

    /**
     * Returns a list of 7 ranges to be displayed in the History View for a given `referenceDate`.
     *
     * This function only generates the ranges. They may be filtered and some of them removed
     * before being presented.
     */
    static func displayedRanges(for referenceDate: Date) -> [DataModel.HistoryRange] {
        var currentRange: DataModel.HistoryRange? = .today
        var ranges = (0..<7).reduce(into: [DataModel.HistoryRange]()) { partialResult, _ in
            if let currentRange {
                partialResult.append(currentRange)
            }
            currentRange = currentRange?.previousRange(for: referenceDate)
        }
        ranges.append(.older)
        return ranges
    }

    // MARK: - Private

    private init?(weekday: Int) {
        switch weekday {
        case 1:
            self = .sunday
        case 2:
            self = .monday
        case 3:
            self = .tuesday
        case 4:
            self = .wednesday
        case 5:
            self = .thursday
        case 6:
            self = .friday
        case 7:
            self = .saturday
        default:
            return nil
        }
    }

    private func weekday(for referenceDate: Date) -> Int? {
        let calendar = Calendar.autoupdatingCurrent
        let referenceWeekday = calendar.component(.weekday, from: referenceDate)

        switch self {
        case .all:
            return nil
        case .today, .older:
            return referenceWeekday
        case .yesterday:
            return referenceWeekday == 1 ? 7 : referenceWeekday-1
        case .sunday:
            return 1
        case .monday:
            return 2
        case .tuesday:
            return 3
        case .wednesday:
            return 4
        case .thursday:
            return 5
        case .friday:
            return 6
        case .saturday:
            return 7
        }
    }

    /**
     * This function returns the range that would appear below the receiver in the History View ranges list.
     *
     * For example, for `.today`, it returns `.yesterday`.
     */
    private func previousRange(for referenceDate: Date) -> Self? {
        switch self {
        case .all:
            return .today
        case .today:
            return .yesterday
        case .yesterday:
            guard let oneDayAgo = date(for: referenceDate)?.daysAgo(1) else {
                return nil
            }
            return DataModel.HistoryRange(date: oneDayAgo, referenceDate: referenceDate)
        case .sunday:
            return .saturday
        case .monday:
            return .sunday
        case .tuesday:
            return .monday
        case .wednesday:
            return .tuesday
        case .thursday:
            return .wednesday
        case .friday:
            return .thursday
        case .saturday:
            return .friday
        case .older:
            return nil
        }
    }
}
