//
//  RollingEightDaysBoolTests.swift
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

import XCTest
@testable import AttributedMetric

final class RollingEightDaysBoolTests: XCTestCase {

    private var rollingBool: RollingEightDaysBool!

    override func setUp() {
        super.setUp()
        rollingBool = RollingEightDaysBool()
    }

    override func tearDown() {
        rollingBool = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertEqual(rollingBool.values.count, 8)
        XCTAssertNil(rollingBool.lastDay)
    }

    func testSetTodayToTrueFirstTime() {
        let beforeDate = Date()

        rollingBool.setTodayToTrue()

        let afterDate = Date()

        // Should set lastDay to current date
        XCTAssertNotNil(rollingBool.lastDay)
        if let lastDay = rollingBool.lastDay {
            XCTAssertGreaterThanOrEqual(lastDay, beforeDate)
            XCTAssertLessThanOrEqual(lastDay, afterDate)
        }

        // Should append true to the array
        XCTAssertEqual(rollingBool.allValues, [true])
        XCTAssertEqual(rollingBool.count, 1)
    }

    func testSetTodayToTrueSameDay() {
        // Set up initial state
        rollingBool.setTodayToTrue()
        let initialCount = rollingBool.count
        let initialValues = rollingBool.allValues
        let initialLastDay = rollingBool.lastDay

        // Call again on same day
        rollingBool.setTodayToTrue()

        // Should not change count or values
        XCTAssertEqual(rollingBool.count, initialCount)
        XCTAssertEqual(rollingBool.allValues, initialValues)
        XCTAssertEqual(rollingBool.lastDay, initialLastDay)
    }

    func testSetTodayToTrueDifferentDay() {
        // Set up initial state with a past date
        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        rollingBool.lastDay = pastDate
        rollingBool.append(true)

        let initialCount = rollingBool.count

        // Call setTodayToTrue (should be different day)
        rollingBool.setTodayToTrue()

        // Should increment count and append new value
        XCTAssertEqual(rollingBool.count, initialCount + 1)
        XCTAssertEqual(rollingBool.allValues, [true, true])

        // Should update lastDay to current date
        XCTAssertNotNil(rollingBool.lastDay)
        if let lastDay = rollingBool.lastDay {
            XCTAssertTrue(Calendar.current.isDateInToday(lastDay))
        }
    }

    func testIsSameDayWithNilLastDay() {
        XCTAssertFalse(rollingBool.isSameDay(Date()))
        XCTAssertFalse(rollingBool.isSameDay(Date.distantPast))
        XCTAssertFalse(rollingBool.isSameDay(Date.distantFuture))
    }

    func testIsSameDayWithSameDay() {
        let testDate = Date()
        rollingBool.lastDay = testDate

        XCTAssertTrue(rollingBool.isSameDay(testDate))

        // Test with slightly different times on same day
        let sameDay = Calendar.current.date(byAdding: .hour, value: 1, to: testDate)!
        XCTAssertTrue(rollingBool.isSameDay(sameDay))
    }

    func testIsSameDayWithDifferentDay() {
        let testDate = Date()
        rollingBool.lastDay = testDate

        let differentDay = Calendar.current.date(byAdding: .day, value: 1, to: testDate)!
        XCTAssertFalse(rollingBool.isSameDay(differentDay))

        let pastDay = Calendar.current.date(byAdding: .day, value: -1, to: testDate)!
        XCTAssertFalse(rollingBool.isSameDay(pastDay))
    }

    func testMultipleDaysSequence() {
        let currentDate = Date()

        // Simulate multiple days of calling setTodayToTrue
        for i in 0..<10 {
            // Set lastDay to current date to simulate different days
            if i > 0 {
                rollingBool.lastDay = currentDate.addingTimeInterval(-.day)
            }

            rollingBool.setTodayToTrue()

            // Verify count doesn't exceed 8 (rolling behaviour)
            XCTAssertLessThanOrEqual(rollingBool.count, 8)

            if i < 8 {
                XCTAssertEqual(rollingBool.count, i + 1)
            } else {
                XCTAssertEqual(rollingBool.count, 8)
            }
        }

        // All values should be true
        let allTrue = Array(repeating: true, count: 8)
        XCTAssertEqual(rollingBool.allValues, allTrue)
    }
}
