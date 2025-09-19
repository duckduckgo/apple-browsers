//
//  TimePast.swift
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

public enum TimePast: Equatable, Codable {
    case none
    case weeks(Int)
    case months(Int)

    public static func == (lhs: TimePast, rhs: TimePast) -> Bool {
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

    static func timePastFrom(date: Date, andInstallationDate installationDate: Date) -> TimePast {
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

    static func daysBetween(from startDate: Date, to endDate: Date) -> Int {
        let timeInterval = endDate.timeIntervalSince(startDate)
        return Int(timeInterval / .day)
    }
}
