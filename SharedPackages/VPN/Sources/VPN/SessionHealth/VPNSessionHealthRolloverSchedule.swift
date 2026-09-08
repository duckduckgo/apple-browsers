//
//  VPNSessionHealthRolloverSchedule.swift
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

import Foundation

struct VPNSessionHealthRolloverSchedule {

    private let calendar: Calendar = {
        var calendar = Calendar.current
        if #available(macOS 13.0, iOS 16.0, *) {
            calendar.timeZone = .gmt
        } else {
            calendar.timeZone = TimeZone(secondsFromGMT: .zero) ?? .current
        }

        return calendar
    }()

    /// Detects if an hour boundary has been crossed between `start` and `now`,
    /// returning the end of the old hour and the start of the new one (or `nil` if not).
    ///
    /// # Examples:
    ///     - start = 10:45, now = 11:10 → (endedAt: 11:00, startedAt: 11:00)
    ///     - start = 10:20, now = 13:05 → (endedAt: 11:00, startedAt: 13:00)
    ///     - start = 10:05, now = 10:50 → nil (same hour)
    ///     - start = 11:00, now = 10:00 → nil (now not after start)
    func rolloverDates(from start: Date, to now: Date) -> (endedAt: Date, startedAt: Date)? {
        guard now > start, !calendar.isDate(start, equalTo: now, toGranularity: .hour) else {
            return nil
        }

        /// Please do note that `dateInterval(of: .hour` returns the whole Hour (Start / End) in which a given Date falls
        guard let endedAt = calendar.dateInterval(of: .hour, for: start)?.end, let startedAt = calendar.dateInterval(of: .hour, for: now)?.start else {
            return nil
        }

        return (endedAt: endedAt, startedAt: startedAt)
    }
}
