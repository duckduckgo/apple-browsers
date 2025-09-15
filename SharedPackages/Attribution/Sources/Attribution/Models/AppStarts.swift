//
//  AppStarts.swift
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

import  Foundation

public struct AppStarts: Codable {
    var timestamps: [Date]

    public init(timestamps: [Date] = []) {
        self.timestamps = timestamps
    }

    mutating func append(timestamp: Date) {
        timestamps.append(timestamp)
    }

    enum TimePast: Equatable {
        case none
        case weeks(Int)
        case months(Int)
    }

    func timePastFromInstallation() -> TimePast {
        guard timestamps.count > 1,
              let installationDate = timestamps.first,
              let lastAppStart = timestamps.last else {
            return .none
        }

        let days = daysBetween(from: installationDate, to: lastAppStart)
        
        // Handle negative time intervals (invalid dates)
        guard days >= 0 else {
            return .none
        }
        
        let weeks = days / 7
        
        guard weeks > 0 else {
            return .none
        }
        
        // If we have more than 3 weeks, switch to months
        // Months are calculated as weeks/4 (every 4 weeks = 1 month)
        if weeks > 3 {
            let months = weeks / 4
            return .months(months)
        } else {
            return .weeks(weeks)
        }
    }
    
    private func daysBetween(from startDate: Date, to endDate: Date) -> Int {
        let timeInterval = endDate.timeIntervalSince(startDate)
        let secondsPerDay: TimeInterval = 24 * 60 * 60
        return Int(timeInterval / secondsPerDay)
    }
}
