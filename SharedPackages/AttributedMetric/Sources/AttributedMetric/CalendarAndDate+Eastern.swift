//
//  CalendarAndDate+Eastern.swift
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

/// Any date and calendar calculation in the framework should be done here for guaranteeing that only Eastern time is used.
extension Calendar {

    /// Calendar configured for Eastern Time Zone (America/New_York)
    /// This automatically handles EST/EDT transitions
    static var eastern: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = easternTimeZone
        return calendar
    }

    /// Eastern Time Zone (America/New_York)
    /// Automatically adjusts for EST/EDT based on the date
    static var easternTimeZone: TimeZone {
        TimeZone(identifier: "America/New_York")!
    }
}

extension Date {

    func ISO8601ETFormat() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withDashSeparatorInDate]
        formatter.timeZone = Calendar.easternTimeZone
        return formatter.string(from: self)
    }
}
