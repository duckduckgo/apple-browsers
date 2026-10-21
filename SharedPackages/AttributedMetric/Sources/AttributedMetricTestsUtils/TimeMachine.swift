//
//  TimeMachine.swift
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
import AttributedMetric

/// A test utility for controlling time in tests.
/// Allows simulation of time passage for testing time-sensitive features like daily pixels.
public class TimeMachine: DateProviding {
    private var date: Date
    private let calendar: Calendar

    public init(calendar: Calendar? = nil, date: Date? = nil) {
        self.calendar = calendar ?? {
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            calendar.locale = Locale(identifier: "en_US_POSIX")
            return calendar
        }()
        self.date = date ?? .init(timeIntervalSince1970: 0)
    }

    public func travel(by component: Calendar.Component, value: Int) {
        date = calendar.date(byAdding: component, value: value, to: now())!
    }

    public func now() -> Date {
        date
    }

    public var debugDate: Date? // Not used here
}
