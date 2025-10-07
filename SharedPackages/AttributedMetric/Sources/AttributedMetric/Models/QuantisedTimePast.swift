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
    /// Returns weeks for 0-4 week periods, months thereafter using 28-day approximation.
    static func timePastFrom(date: Date, andInstallationDate installationDate: Date) -> QuantisedTimePast {
        let days = daysBetween(from: installationDate, to: date)

        // Handle negative time intervals (invalid dates)
        guard days > 0 else {
            return .none
        }
        // 0 / 1-7/ 8-14 ...
        let weeks = Float(days-1) / 7

        if weeks < 4 {
            return .weeks(Int(weeks+1))
        } else {
            let months = Float(days-1) / 28
            return .months(Int(months+1))
        }
    }

    /// Calculates whole days between two dates using time intervals.
    static func daysBetween(from startDate: Date, to endDate: Date) -> Int {
        let timeInterval = endDate.timeIntervalSince(startDate)
        return Int(timeInterval / .day)
    }
}
