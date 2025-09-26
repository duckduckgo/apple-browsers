//
//  RollingEightDaysIntTests.swift
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

final class RollingEightDaysIntTests: XCTestCase {

    private var rollingInt: RollingEightDaysInt!

    override func setUp() {
        super.setUp()
        rollingInt = RollingEightDaysInt()
    }

    override func tearDown() {
        rollingInt = nil
        super.tearDown()
    }

    func testInitialization() {
        XCTAssertEqual(rollingInt.values.count, 8)
        XCTAssertNil(rollingInt.lastDay)
    }

    func testIncrementFirstTime() {
        let beforeDate = Date()

        rollingInt.increment()

        let afterDate = Date()

        // Should set lastDay to current date
        XCTAssertNotNil(rollingInt.lastDay)
        if let lastDay = rollingInt.lastDay {
            XCTAssertGreaterThanOrEqual(lastDay, beforeDate)
            XCTAssertLessThanOrEqual(lastDay, afterDate)
        }

        // Should append 1 to the array
        XCTAssertEqual(rollingInt.allValues, [1])
        XCTAssertEqual(rollingInt.count, 1)
        XCTAssertEqual(rollingInt.last, 1)
    }

    func testIncrementSameDay() {
        // Set up initial state
        rollingInt.increment()
        let initialLastDay = rollingInt.lastDay

        // Call increment again on same day
        rollingInt.increment()
        rollingInt.increment()

        // Should increment the last value, not add new entries
        XCTAssertEqual(rollingInt.count, 1)
        XCTAssertEqual(rollingInt.allValues, [3])
        XCTAssertEqual(rollingInt.last, 3)
        XCTAssertEqual(rollingInt.lastDay, initialLastDay)
    }

    func testIncrementDifferentDay() {
        // Set up initial state with a past date
        let pastDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        rollingInt.lastDay = pastDate
        rollingInt.append(5)

        let initialCount = rollingInt.count

        // Call increment (should be different day)
        rollingInt.increment()

        // Should increment count and append new value
        XCTAssertEqual(rollingInt.count, initialCount + 1)
        XCTAssertEqual(rollingInt.allValues, [5, 1])
        XCTAssertEqual(rollingInt.last, 1)

        // Should update lastDay to current date
        XCTAssertNotNil(rollingInt.lastDay)
        if let lastDay = rollingInt.lastDay {
            XCTAssertTrue(Calendar.current.isDateInToday(lastDay))
        }
    }

    func testPast7DaysAverageEmptyArray() {
        XCTAssertEqual(rollingInt.past7DaysAverage, 0)
    }

    func testPast7DaysAverageWithValues() {
        // Add values to fill some slots (including today)
        for i in 1...8 {
            rollingInt.append(i)
        }

        // past7DaysAverage should exclude the last value (today)
        // Values: [1, 2, 3, 4, 5, 6, 7], average = (1+2+3+4+5+6+7)/7 = 4
        let expectedAverage = Int((Float(1+2+3+4+5+6+7) / Float(rollingInt.count-1)).rounded(.toNearestOrAwayFromZero))
        XCTAssertEqual(rollingInt.past7DaysAverage, expectedAverage)
    }

    // Discussion still ongoing, the average will need to be adjusted

//    func testPast7DaysAverageWithUnknownValues() {
//        // Add some values and leave some unknown
//        rollingInt.append(3)
//        rollingInt.append(7)
//        rollingInt.append(11)
//        rollingInt.append(0)
//
//        // past7DaysAverage should only count known values (excluding today)
//        // Values excluding last: [10, 20, 30], average = (3+7+11)/2 = 10.5
//        XCTAssertEqual(rollingInt.past7DaysAverage, 11)
//    }
//
//    func testPast7DaysAverageRoundingBehavior() {
//        // Test specific rounding cases
//        rollingInt.append(1)  // Will be excluded (today)
//        rollingInt[0] = 6     // 6
//        rollingInt[1] = 7     // 7
//
//        // Average = (6+7)/2 = 6.5, rounded = 7
//        XCTAssertEqual(rollingInt.past7DaysAverage, 7)
//
//        // Test rounding down case
//        rollingInt[2] = 5     // 5
//
//        // Average = (6+7+5)/3 = 6, no rounding needed
//        XCTAssertEqual(rollingInt.past7DaysAverage, 6)
//    }

    func testCountPast7DaysEmptyArray() {
        XCTAssertEqual(rollingInt.countPast7Days, 0)
    }

    func testCountPast7DaysWithValues() {
        // Fill array with values
        for i in 1...8 {
            rollingInt.append(i)
        }

        // Should count all non-unknown values excluding today (last value)
        // Total values = 8, excluding today = 7
        XCTAssertEqual(rollingInt.countPast7Days, 7)
    }

    func testCountPast7DaysWithMixedValues() {
        // Add some values, leave some unknown
        rollingInt.append(1)
        rollingInt.append(2)
        rollingInt[5] = 99  // Manually set a value

        // Should count only non-unknown values excluding today
        // Values excluding last: [unknown, unknown, unknown, unknown, unknown, 99, 1] = 2 non-unknown
        XCTAssertEqual(rollingInt.countPast7Days, 2)
    }

    func testMultipleDaysSequenceWithIncrements() {
        let currentDate = Date()

        // Simulate multiple days with different increment counts
        let dailyIncrements = [3, 1, 5, 2, 4, 1, 3, 2, 1]

        for (dayIndex, increments) in dailyIncrements.enumerated() {
            // Set lastDay to simulate different days
            if dayIndex > 0 {
                rollingInt.lastDay = currentDate.addingTimeInterval(-.day)
            }

            // Perform multiple increments on same day
            for _ in 0..<increments {
                rollingInt.increment()
            }

            // Verify the last value matches expected increments
            XCTAssertEqual(rollingInt.last, increments)

            // Verify count doesn't exceed 8 (rolling behavior)
            XCTAssertLessThanOrEqual(rollingInt.count, 8)
        }

        // Should have exactly 8 values (due to rolling)
        XCTAssertEqual(rollingInt.count, 8)

        // Last 8 daily totals: [1, 5, 2, 4, 1, 3, 2, 1]
        let expectedValues = [1, 5, 2, 4, 1, 3, 2, 1]
        XCTAssertEqual(rollingInt.allValues, expectedValues)
    }

    func testIsSameDayFunctionality() {
        // Test inherited isSameDay functionality
        XCTAssertFalse(rollingInt.isSameDay(Date()))

        let testDate = Date()
        rollingInt.lastDay = testDate

        XCTAssertTrue(rollingInt.isSameDay(testDate))

        let differentDay = Calendar.current.date(byAdding: .day, value: 1, to: testDate)!
        XCTAssertFalse(rollingInt.isSameDay(differentDay))
    }
}
