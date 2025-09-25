//
//  RollingEightDays.swift
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

/// A specialised rolling data structure that maintains exactly 8 values for tracking weekly data.
public class RollingEightDays<T: Codable & Equatable>: RollingArray<T> {

    var lastDay: Date?

    /// Creates a new `RollingEightDays` instance with 8 empty slots.
    ///
    /// The rolling eight-day structure is initialized with a fixed capacity of 8 slots,
    /// all initially empty and ready to receive daily data values.
    public init() {
        super.init(capacity: 8)
    }

    /// Creates a new `RollingEightDays` instance from a decoder.
    ///
    /// This initialiser allows the rolling eight-day structure to be decoded from
    /// persistent storage or network data while maintaining the seven-day capacity.
    ///
    /// - Parameter decoder: The decoder to read data from.
    /// - Throws: An error if decoding fails.
    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }

    /// Checks if the given date is the same calendar day as the last recorded day.
    public func isSameDay(_ date: Date) -> Bool {
        guard let lastDay else { return false }
        return Calendar.current.isDate(date, inSameDayAs: lastDay)
    }
}

// MARK: -

/// Specialised rolling eight-day structure for boolean values with daily aggregation.
public class RollingEightDaysBool: RollingEightDays<Bool> {

    /// Sets the last value to `true` if in the same day, creates a new one otherwise.
    public func setTodayToTrue() {
        let now = Date()

        if lastDay == nil {
            lastDay = now
            append(true)
            return
        }

        if !isSameDay(now) {
            lastDay = now
            append(true)
        }
    }
}

/// Specialised rolling eight-day structure for integer values with daily aggregation and averaging.
public class RollingEightDaysInt: RollingEightDays<Int> {

    /// Increments the last value if in the same day, creates a new one otherwise.
    public func increment() {
        let now = Date()
        if lastDay == nil {
            lastDay = now
        }

        // The last increment happened the same day,
        if isSameDay(now) {
            var value = self.last
            value = (value ?? 0) + 1
            self[self.lastIndex] = value
        } else {
            lastDay = now
            append(1)
        }
    }

    /// Calculates the rounded average of the past 7 days, excluding today and unknown values.
    /// WARNING: still pending logic decision: https://app.asana.com/1/137249556945/task/1211313432282643/comment/1211464184465774?focus=true
    public var past7DaysAverage: Int {
        var sum = 0
        for value in values.dropLast() {
            switch value {
            case .unknown:
                break
            case .value(let intValue):
                sum += intValue
            }
        }
        return Int((Float(sum) / Float(values.count - 1)).rounded(.toNearestOrAwayFromZero)) // E.g. 6.4 = 6, 6.5 = 7, 6.6 = 7
    }

    /// Counts non-unknown values in the past 7 days, excluding today.
    public var countPast7Days: Int {
        return values.dropLast().count(where: { $0 != .unknown })
    }
}
