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
import os.log

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

    // MARK: - Codable

    private enum CodingKeys: CodingKey {
        case lastDay
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastDay = try container.decodeIfPresent(Date.self, forKey: .lastDay)
        try super.init(from: decoder)
    }

    public override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(lastDay, forKey: .lastDay)
        try super.encode(to: encoder)
    }

    /// Checks if the given date is the same calendar day as the last recorded day.
    public func isSameDay(_ date: Date) -> Bool {
        guard let lastDay else { return false }
        return Calendar.eastern.isDate(date, inSameDayAs: lastDay)
    }
}

// MARK: -

/// Specialised rolling eight-day structure for boolean values with daily aggregation.
public class RollingEightDaysBool: RollingEightDays<Bool> {

    /// Sets the last value to `true` if in the same day, creates a new one otherwise.
    ///
    /// - Parameter dateProvider: The date provider to use for getting the current date.
    public func setTodayToTrue(dateProvider: DateProviding) {
        let now = dateProvider.now()

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
public class RollingEightDaysInt: RollingEightDays<Int>, CustomDebugStringConvertible {

    /// Increments the value for the current day.
    ///
    /// If `lastDay` is today (same calendar day in Eastern Time), increments the last value.
    /// If `lastDay` is not today, appends `.unknown` for each missing day between `lastDay`
    /// and today, then appends `1` for today.
    ///
    /// - Parameter dateProvider: The date provider to use for getting the current date.
    ///
    /// ## Example:
    /// ```swift
    /// // Day 1: First increment
    /// rolling.increment() // [1]
    ///
    /// // Day 1: Same day increment
    /// rolling.increment() // [2]
    ///
    /// // Day 4: Missing days 2 and 3
    /// rolling.increment() // [2, unknown, unknown, 1]
    /// ```
    public func increment(dateProvider: DateProviding) {
        let now = dateProvider.now()

        // First time initialization
        guard let lastDay else {
            self.lastDay = now
            append(1)
            return
        }

        guard now >= lastDay else {
            Logger.attributedMetricRolling8Days.error("The date is incorrect; the current date precedes the last recorded date.")
            return
        }

        // Check if it's the same day
        if isSameDay(now) {
            // Increment the last value in the data structure
            let currentValue = self.last ?? 0
            self[self.lastIndex] = currentValue + 1
        } else {
            // Calculate days between lastDay and now
            let daysBetween = Calendar.eastern.dateComponents([.day], from: Calendar.eastern.startOfDay(for: lastDay), to: Calendar.eastern.startOfDay(for: now)).day ?? 0

            guard daysBetween > 0 else {
                Logger.attributedMetricRolling8Days.error("Attempted to increment rolling value for a date that was the same as the last date, which is not possible.")
                return
            }

            // Append .unknown for each missing day (excluding today)
            for _ in 1..<daysBetween {
                values.removeFirst()
                values.append(.unknown)
            }

            // Update lastDay and append 1 for today
            self.lastDay = now
            append(1)
        }
    }

    /// Calculates the rounded average of the past 7 days, excluding today and unknown values.
    public var past7DaysAverage: Int {
        var sum = 0
        var notUnknownValues = 0
        for value in values.dropLast() {
            switch value {
            case .unknown:
                break
            case .value(let intValue):
                notUnknownValues += 1
                sum += intValue
            }
        }

        if notUnknownValues > 0 {
            return Int((Float(sum) / Float(notUnknownValues)).rounded(.toNearestOrAwayFromZero)) // E.g. 6.4 = 6, 6.5 = 7, 6.6 = 7
        } else {
            return 0
        }
    }

    /// Counts non-unknown values in the past 7 days, excluding today.
    public var countPast7Days: Int {
        return values.dropLast().count(where: { $0 != .unknown })
    }

    public var debugDescription: String {
        let dateString: String
        if let lastDay {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            dateString = formatter.string(from: lastDay)
        } else {
            dateString = "nil"
        }

        let valuesDescription = values.map { element -> String in
            switch element {
            case .unknown:
                return "-"
            case .value(let v):
                return String(v)
            }
        }.joined(separator: ", ")

        return """
                RollingEightDaysInt
                lastDay: \(dateString)
                values: [\(valuesDescription)]
                past7DaysAverage: \(past7DaysAverage)
                countPast7Days: \(countPast7Days)
                """
    }
}
