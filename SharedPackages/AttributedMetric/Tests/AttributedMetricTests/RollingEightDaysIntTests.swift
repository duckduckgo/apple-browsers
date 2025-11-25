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
import AttributedMetricTestsUtils

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
        XCTAssertEqual(rollingInt.count, 0)
        XCTAssertEqual(rollingInt.past7DaysAverage, 0)
        XCTAssertNil(rollingInt.lastDay)
    }

    func testIncrementFirstTime() {
        let beforeDate = Date()

        rollingInt.increment(dateProvider: DefaultDateProvider())

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
        rollingInt.increment(dateProvider: DefaultDateProvider())
        let initialLastDay = rollingInt.lastDay

        // Call increment again on same day
        rollingInt.increment(dateProvider: DefaultDateProvider())
        rollingInt.increment(dateProvider: DefaultDateProvider())

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
        rollingInt.increment(dateProvider: DefaultDateProvider())

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

    func testPast7DaysAverageSingleValue() {
        // Add only one value (today)
        rollingInt.append(10)

        // With only one value, past7DaysAverage should return 0 (no past days to average)
        // This tests the guard clause that prevents division by zero
        XCTAssertEqual(rollingInt.past7DaysAverage, 0)
        XCTAssertEqual(rollingInt.count, 1)
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

    func testPast7DaysAverageWithUnknownValues() {
        // Add some values and leave some unknown
        rollingInt.append(3)
        rollingInt.append(8)
        rollingInt.append(11)
        rollingInt.append(1)
        // past7DaysAverage should only count known values (excluding today)
        XCTAssertEqual(rollingInt.past7DaysAverage, 7) // un-rounded average 7.333...
    }

    func testPast7DaysAverageRoundingBehavior() {
        // Test specific rounding cases
        rollingInt.append(1)  // Will be excluded (today)
        rollingInt[0] = 6     // 6
        rollingInt[1] = 7     // 7

        // Average = (6+7)/2 = 6.5, rounded = 7
        XCTAssertEqual(rollingInt.past7DaysAverage, 7)

        // Test rounding down case
        rollingInt[2] = 5     // 5

        // Average = (6+7+5)/3 = 6, no rounding needed
        XCTAssertEqual(rollingInt.past7DaysAverage, 6)
    }

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
                rollingInt.increment(dateProvider: DefaultDateProvider())
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

    func testIncrementWithMissingDays() {
        // Set up initial state with day 1
        let day1 = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 15))!
        rollingInt.lastDay = day1
        rollingInt.append(5)

        // Set lastDay to 3 days ago to simulate missing days
        rollingInt.lastDay = Calendar.eastern.date(byAdding: .day, value: -3, to: Date())!
        let initialValue = 7
        rollingInt.append(initialValue)

        // Now increment (should add 2 unknown days and then 1)
        rollingInt.increment(dateProvider: DefaultDateProvider())

        // Verify structure: should have removed oldest values and added unknowns
        // The last value should be 1 (new day)
        XCTAssertEqual(rollingInt.last, 1)

        // Count should include the initial value, 2 unknowns, and the new value
        // But we can only reliably check that last is 1 and unknowns exist
        let allValues = rollingInt.allValues
        // Should have fewer values than total slots if unknowns were added
        XCTAssertLessThan(allValues.count, rollingInt.values.count)
    }

    func testIncrementMultipleMissingDays() {
        // Day 1: Add value
        rollingInt.increment(dateProvider: DefaultDateProvider())
        rollingInt.increment(dateProvider: DefaultDateProvider())
        XCTAssertEqual(rollingInt.last, 2)
        XCTAssertEqual(rollingInt.count, 1) // Only one day with data

        // Simulate missing 5 days
        rollingInt.lastDay = Calendar.eastern.date(byAdding: .day, value: -5, to: Date())!

        // Day 7: Increment
        rollingInt.increment(dateProvider: DefaultDateProvider())

        // Should have: [2, unknown, unknown, unknown, unknown, 1]
        XCTAssertEqual(rollingInt.last, 1)

        // Count only non-unknown values
        let nonUnknownCount = rollingInt.allValues.count
        XCTAssertEqual(nonUnknownCount, 2) // Original day (2) and new day (1)

        // Total values including unknowns should be more
        XCTAssertEqual(rollingInt.values.count, 8)

        // Verify the structure contains unknowns
        var unknownCount = 0
        for value in rollingInt.values where value == .unknown {
            unknownCount += 1
        }
        XCTAssertEqual(unknownCount, 6) // 5 missing days + initial 1 unknown slot from initialization, then rolling happened
    }

    func testIncrementSameDayDoesNotAddUnknowns() {
        // Day 1: First increment
        rollingInt.increment(dateProvider: DefaultDateProvider())
        XCTAssertEqual(rollingInt.last, 1)

        let initialValuesCount = rollingInt.values.count

        // Day 1: Same day increments
        rollingInt.increment(dateProvider: DefaultDateProvider())
        rollingInt.increment(dateProvider: DefaultDateProvider())

        // Should increment value without adding unknowns
        XCTAssertEqual(rollingInt.last, 3)
        XCTAssertEqual(rollingInt.values.count, initialValuesCount) // No structural changes
        XCTAssertEqual(rollingInt.count, 1) // Still only one day with data
    }

    // MARK: - Codable Persistence Tests

    func testEncodingAndDecodingPreservesLastDay() throws {
        // Set up state with lastDay
        let testDate = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 12, minute: 30))!
        rollingInt.lastDay = testDate
        rollingInt.append(5)
        rollingInt.append(10)
        rollingInt.append(3)

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(rollingInt)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RollingEightDaysInt.self, from: data)

        // Verify lastDay was persisted
        XCTAssertNotNil(decoded.lastDay)
        XCTAssertEqual(decoded.lastDay, testDate)

        // Verify values were also persisted
        XCTAssertEqual(decoded.allValues, [5, 10, 3])
        XCTAssertEqual(decoded.count, 3)
    }

    func testEncodingAndDecodingWithNilLastDay() throws {
        // Set up state without lastDay
        rollingInt.append(7)
        rollingInt.append(14)

        XCTAssertNil(rollingInt.lastDay)

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(rollingInt)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RollingEightDaysInt.self, from: data)

        // Verify lastDay is still nil
        XCTAssertNil(decoded.lastDay)

        // Verify values were persisted
        XCTAssertEqual(decoded.allValues, [7, 14])
    }

    func testIncrementAfterDecodingUsesPersistedLastDay() throws {
        // Day 1: Set up initial state
        let day1 = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 15))!
        let timeMachine = TimeMachine(date: day1)
        rollingInt.increment(dateProvider: timeMachine)
        rollingInt.increment(dateProvider: timeMachine)
        XCTAssertEqual(rollingInt.last, 2)
        XCTAssertNotNil(rollingInt.lastDay)

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(rollingInt)

        // Decode (simulating app restart)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RollingEightDaysInt.self, from: data)

        // Verify lastDay was restored
        XCTAssertNotNil(decoded.lastDay)
        XCTAssertTrue(Calendar.eastern.isDate(decoded.lastDay!, inSameDayAs: day1))

        // Same day: Increment should update existing value
        decoded.increment(dateProvider: timeMachine)
        XCTAssertEqual(decoded.last, 3)
        XCTAssertEqual(decoded.count, 1) // Still only one day

        // Next day: Increment should add new value
        let day2 = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 16))!
        let timeMachine2 = TimeMachine(date: day2)
        decoded.increment(dateProvider: timeMachine2)
        XCTAssertEqual(decoded.last, 1)
        XCTAssertEqual(decoded.count, 2) // Now two days
    }

    func testIncrementAfterDecodingWithoutLastDayBehavesCorrectly() throws {
        // Create state without lastDay (old data format)
        rollingInt.append(10)

        // Encode only the values (simulate old format without lastDay)
        let encoder = JSONEncoder()
        let data = try encoder.encode(rollingInt)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RollingEightDaysInt.self, from: data)

        // lastDay should be nil after decoding old format
        XCTAssertNil(decoded.lastDay)

        // First increment should initialize lastDay
        decoded.increment(dateProvider: DefaultDateProvider())
        XCTAssertNotNil(decoded.lastDay)
        XCTAssertEqual(decoded.last, 1) // New value added
        XCTAssertEqual(decoded.count, 2) // Original value + new value
    }

    func testMultipleEncodeDecodesCyclesPreserveLastDay() throws {
        // Initial state
        let day1 = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 15))!
        let timeMachine = TimeMachine(date: day1)
        rollingInt.increment(dateProvider: timeMachine)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // First cycle
        var data = try encoder.encode(rollingInt)
        var decoded = try decoder.decode(RollingEightDaysInt.self, from: data)
        XCTAssertEqual(decoded.lastDay, rollingInt.lastDay)

        // Second cycle
        let day2 = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 16))!
        let timeMachine2 = TimeMachine(date: day2)
        decoded.increment(dateProvider: timeMachine2)
        data = try encoder.encode(decoded)
        let decoded2 = try decoder.decode(RollingEightDaysInt.self, from: data)
        XCTAssertTrue(Calendar.eastern.isDate(decoded2.lastDay!, inSameDayAs: day2))

        // Third cycle
        let day3 = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 17))!
        let timeMachine3 = TimeMachine(date: day3)
        decoded2.increment(dateProvider: timeMachine3)
        data = try encoder.encode(decoded2)
        let decoded3 = try decoder.decode(RollingEightDaysInt.self, from: data)
        XCTAssertTrue(Calendar.eastern.isDate(decoded3.lastDay!, inSameDayAs: day3))

        // Verify values
        XCTAssertEqual(decoded3.allValues, [1, 1, 1])
    }
}
