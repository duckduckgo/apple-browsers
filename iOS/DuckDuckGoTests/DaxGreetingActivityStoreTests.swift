//
//  DaxGreetingActivityStoreTests.swift
//  DuckDuckGo
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

import XCTest
@testable import DuckDuckGo

@MainActor
final class DaxGreetingActivityStoreTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(day: Int = 15, hour: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    func testWhenOpeningAppThenCountResetsOnColdLaunchAndNewDay() {
        var now = date()
        var lastActiveDate: Date? = date(day: 14)
        let store = DaxGreetingActivityStore(readLastActiveDate: { lastActiveDate }, now: { now },
                                             calendarProvider: { self.calendar }, isEnabled: { true })
        lastActiveDate = now
        store.recordForegroundOpen()
        var context = store.context(at: now, calendar: calendar, appearance: .dark)
        XCTAssertEqual(context.foregroundOpenCount, 1)
        XCTAssertEqual(context.isFirstOpenOfDay, true)
        XCTAssertEqual(context.appearance, .dark)

        store.recordForegroundOpen()
        store.recordForegroundOpen()
        context = store.context(at: now, calendar: calendar, appearance: nil)
        XCTAssertEqual(context.foregroundOpenCount, 3)
        XCTAssertEqual(context.isFirstOpenOfDay, false)

        let nextLaunch = DaxGreetingActivityStore(readLastActiveDate: { lastActiveDate }, now: { now },
                                                  calendarProvider: { self.calendar }, isEnabled: { true })
        nextLaunch.recordForegroundOpen()
        context = nextLaunch.context(at: now, calendar: calendar, appearance: nil)
        XCTAssertEqual(context.foregroundOpenCount, 1)
        XCTAssertEqual(context.isFirstOpenOfDay, false)

        now = date(day: 16)
        lastActiveDate = now
        XCTAssertEqual(nextLaunch.context(at: now, calendar: calendar, appearance: nil).foregroundOpenCount, 0)
        nextLaunch.recordForegroundOpen()
        context = nextLaunch.context(at: now, calendar: calendar, appearance: nil)
        XCTAssertEqual(context.foregroundOpenCount, 1)
        XCTAssertEqual(context.isFirstOpenOfDay, true)
    }

    func testWhenReadingContextRepeatedlyThenNoAppOpenIsRecorded() {
        let store = DaxGreetingActivityStore(isEnabled: { true })
        for _ in 0..<5 {
            XCTAssertEqual(store.context(at: date(), calendar: calendar, appearance: nil).foregroundOpenCount, 0)
        }
    }

    func testWhenFeatureIsDisabledThenNoOpenIsCounted() {
        var enabled = false
        let store = DaxGreetingActivityStore(now: { self.date() }, isEnabled: { enabled })
        store.recordForegroundOpen()
        XCTAssertEqual(store.context(at: date(), calendar: calendar, appearance: nil).foregroundOpenCount, 0)
        enabled = true
        store.recordForegroundOpen()
        XCTAssertEqual(store.context(at: date(), calendar: calendar, appearance: nil).foregroundOpenCount, 1)
    }
}
