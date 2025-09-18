//
//  RollingSevenDays.swift
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

/// A specialized rolling data structure that maintains exactly 7 values for tracking weekly data.
///
/// `RollingSevenDays` is a subclass of `RollingArray` with a fixed capacity of 7, specifically
/// designed for tracking data over a seven-day period. It inherits all the functionality of
/// `RollingArray` while providing a more specific API for weekly tracking use cases.
///
/// ## Key Characteristics:
/// - **Fixed Seven-Day Capacity**: Always maintains exactly 7 slots for weekly data
/// - **Rolling Behavior**: New values automatically push out week-old values
/// - **Type Safety**: Supports both `Int` and `Bool` value types with convenient aliases
/// - **Weekly Context**: Designed specifically for tracking weekly patterns and trends
///
/// ## Usage Example:
/// ```swift
/// var weeklyClicks = RollingSevenDays<Int>()
///
/// // Track daily click counts
/// weeklyClicks.append(10) // Day 1
/// weeklyClicks.append(15) // Day 2
/// weeklyClicks.append(8)  // Day 3
///
/// weeklyClicks.count // 3
/// weeklyClicks.allValues // [10, 15, 8]
///
/// // Continue tracking through the week
/// for dayClicks in [12, 20, 18, 25] {
///     weeklyClicks.append(dayClicks)
/// }
/// weeklyClicks.allValues // [10, 15, 8, 12, 20, 18, 25]
///
/// // Next day rolls over (removes oldest)
/// weeklyClicks.append(30)
/// weeklyClicks.allValues // [15, 8, 12, 20, 18, 25, 30]
/// ```
public class RollingSevenDays<T: Codable & Equatable>: RollingArray<T> {

    var lastDay: Date?

    /// Creates a new `RollingSevenDays` instance with 7 empty slots.
    ///
    /// The rolling seven-day structure is initialized with a fixed capacity of 7 slots,
    /// all initially empty and ready to receive daily data values.
    public init() {
        super.init(capacity: 7)
    }

    /// Creates a new `RollingSevenDays` instance from a decoder.
    ///
    /// This initializer allows the rolling seven-day structure to be decoded from
    /// persistent storage or network data while maintaining the seven-day capacity.
    ///
    /// - Parameter decoder: The decoder to read data from.
    /// - Throws: An error if decoding fails.
    public required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }

    public func isSameDay() -> Bool {
        guard let lastDay else { return false }
        return Calendar.current.isDate(Date(), inSameDayAs: lastDay)
    }
}

// MARK: - Type Aliases
//public class RollingSevenDaysBool: RollingSevenDays<Bool> {
//
//    
//}
public class RollingSevenDaysInt: RollingSevenDays<Int> {

    /// Increment the last value if in the same day, creates a new one otherwise
    public func increment() {

        if lastDay == nil {
            lastDay = Date()
        }

        // The last increment happened the same day,
        if isSameDay() {
            var value = self.last
            value = (value ?? 0) + 1
            self[self.lastIndex] = value
        } else {
            append(1)
        }
    }
}
