//
//  QuantisedTimePast.swift
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

/// Represents time intervals since app installation for metrics attribution.
/// Quantises durations into weeks (up to 4) then months for privacy-preserving analytics.
public enum QuantisedTimePast: Equatable, Codable {
    /// No time has passed or invalid date range
    case none
    /// Duration measured in weeks (1-4 weeks)
    case weeks(Int)
    /// Duration measured in months (1+ months, 28-day approximation)
    case months(Int)

    /// Human-readable description of the time period
    public var description: String {
        switch self {
        case .none:
            return "None (install day or invalid)"
        case .weeks(let count):
            return count == 1 ? "1 week" : "\(count) weeks"
        case .months(let count):
            return count == 1 ? "1 month" : "\(count) months"
        }
    }

    public static func == (lhs: QuantisedTimePast, rhs: QuantisedTimePast) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            return true
        case (.weeks(let lhsWeeks), .weeks(let rhsWeeks)):
            return lhsWeeks == rhsWeeks
        case (.months(let lhsMonths), .months(let rhsMonths)):
            return lhsMonths == rhsMonths
        default:
            return false
        }
    }

    /// Calculates quantised time interval between installation and given date.
    ///
    /// Quantisation logic:
    /// - Day 0 (install day): `.none`
    /// - Days 1-7: `.weeks(1)`
    /// - Days 8-14: `.weeks(2)`
    /// - Days 15-21: `.weeks(3)`
    /// - Days 22-28: `.weeks(4)`
    /// - Days 29-56: `.months(2)` ← Note: Month 1 is intentionally skipped
    /// - Days 57-84: `.months(3)`
    /// - Days 85-112: `.months(4)`
    /// - Days 113-140: `.months(5)`
    /// - Days 141-168: `.months(6)`
    /// - And so on...
    ///
    /// Each month bucket represents a 28-day period for consistent quantization.
    /// Month 1 is skipped to avoid confusion between "4 weeks" and "1 month".
    static func timePastFrom(date: Date, andInstallationDate installationDate: Date) -> QuantisedTimePast {
        let days = daysBetween(from: installationDate, to: date)

        // Install day or invalid date range (negative time)
        guard days > 0 else {
            return .none
        }

        // Calculate which bucket this falls into (0-indexed)
        // Days 1-7 → bucket 0 → week 1
        // Days 8-14 → bucket 1 → week 2
        // Days 29-56 → bucket 4 → month 2 (bucket 4 + 1 = 5, then subtract 3 for skipped weeks)
        let bucket = (days - 1) / 7

        if bucket < 4 {
            // Weeks 1-4: bucket 0-3 maps to weeks 1-4
            return .weeks(bucket + 1)
        } else {
            // Months: Convert 7-day buckets to 28-day (4-week) buckets
            // bucket 4-7 → month 2, bucket 8-11 → month 3, etc.
            let monthBucket = bucket / 4
            return .months(monthBucket + 1)
        }
    }

    /// Calculates whole days between two dates using time intervals.
    static func daysBetween(from startDate: Date, to endDate: Date) -> Int {
        let timeInterval = endDate.timeIntervalSince(startDate)
        return Int(timeInterval / .day)
    }
}
