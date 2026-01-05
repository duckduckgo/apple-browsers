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
import AttributedMetricTestsUtils

final class RollingEightDaysBoolTests: XCTestCase {

    private var rollingBool: RollingEightDaysBool!
    /// Fixed reference date for all tests: January 15, 2025, 12:00 UTC
    private let referenceDate = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 12))!

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
        let timeMachine = TimeMachine(date: referenceDate)

        rollingBool.setTodayToTrue(dateProvider: timeMachine)

        // Should set lastDay to current date from TimeMachine
        XCTAssertNotNil(rollingBool.lastDay)
        XCTAssertEqual(rollingBool.lastDay, referenceDate)

        // Should append true to the array
        XCTAssertEqual(rollingBool.allValues, [true])
        XCTAssertEqual(rollingBool.count, 1)
    }

    func testSetTodayToTrueSameDay() {
        let timeMachine = TimeMachine(date: referenceDate)

        // Set up initial state
        rollingBool.setTodayToTrue(dateProvider: timeMachine)
        let initialCount = rollingBool.count
        let initialValues = rollingBool.allValues
        let initialLastDay = rollingBool.lastDay

        // Call again on same day
        rollingBool.setTodayToTrue(dateProvider: timeMachine)

        // Should not change count or values
        XCTAssertEqual(rollingBool.count, initialCount)
        XCTAssertEqual(rollingBool.allValues, initialValues)
        XCTAssertEqual(rollingBool.lastDay, initialLastDay)
    }

    func testSetTodayToTrueDifferentDay() {
        let timeMachine = TimeMachine(date: referenceDate)

        // Set up initial state with a past date (day before reference)
        let pastDate = Calendar.eastern.date(byAdding: .day, value: -1, to: referenceDate)!
        rollingBool.lastDay = pastDate
        rollingBool.append(true)

        let initialCount = rollingBool.count

        // Call setTodayToTrue (should be different day)
        rollingBool.setTodayToTrue(dateProvider: timeMachine)

        // Should increment count and append new value
        XCTAssertEqual(rollingBool.count, initialCount + 1)
        XCTAssertEqual(rollingBool.allValues, [true, true])

        // Should update lastDay to current date from TimeMachine
        XCTAssertNotNil(rollingBool.lastDay)
        XCTAssertEqual(rollingBool.lastDay, referenceDate)
    }

    func testIsSameDayWithNilLastDay() {
        XCTAssertFalse(rollingBool.isSameDay(referenceDate))
        XCTAssertFalse(rollingBool.isSameDay(Date.distantPast))
        XCTAssertFalse(rollingBool.isSameDay(Date.distantFuture))
    }

    func testIsSameDayWithSameDay() {
        rollingBool.lastDay = referenceDate

        XCTAssertTrue(rollingBool.isSameDay(referenceDate))

        // Test with slightly different times on same day
        let sameDay = Calendar.eastern.date(byAdding: .hour, value: 1, to: referenceDate)!
        XCTAssertTrue(rollingBool.isSameDay(sameDay))
    }

    func testIsSameDayWithDifferentDay() {
        rollingBool.lastDay = referenceDate

        let differentDay = Calendar.eastern.date(byAdding: .day, value: 1, to: referenceDate)!
        XCTAssertFalse(rollingBool.isSameDay(differentDay))

        let pastDay = Calendar.eastern.date(byAdding: .day, value: -1, to: referenceDate)!
        XCTAssertFalse(rollingBool.isSameDay(pastDay))
    }

    func testMultipleDaysSequence() {
        let timeMachine = TimeMachine(date: referenceDate)

        // Simulate multiple days of calling setTodayToTrue
        for i in 0..<10 {
            // Set lastDay to previous day to simulate different days
            if i > 0 {
                rollingBool.lastDay = Calendar.eastern.date(byAdding: .day, value: -1, to: timeMachine.now())!
            }

            rollingBool.setTodayToTrue(dateProvider: timeMachine)

            // Verify count doesn't exceed 8 (rolling behaviour)
            XCTAssertLessThanOrEqual(rollingBool.count, 8)

            if i < 8 {
                XCTAssertEqual(rollingBool.count, i + 1)
            } else {
                XCTAssertEqual(rollingBool.count, 8)
            }

            // Advance time machine for next iteration
            timeMachine.travel(by: .day, value: 1)
        }

        // All values should be true
        let allTrue = Array(repeating: true, count: 8)
        XCTAssertEqual(rollingBool.allValues, allTrue)
    }

    // MARK: - Codable Persistence Tests

    func testEncodingAndDecodingPreservesLastDay() throws {
        // Set up state with lastDay
        let testDate = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 20, hour: 14, minute: 45))!
        rollingBool.lastDay = testDate
        rollingBool.append(true)
        rollingBool.append(true)

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(rollingBool)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RollingEightDaysBool.self, from: data)

        // Verify lastDay was persisted
        XCTAssertNotNil(decoded.lastDay)
        XCTAssertEqual(decoded.lastDay, testDate)

        // Verify values were also persisted
        XCTAssertEqual(decoded.allValues, [true, true])
        XCTAssertEqual(decoded.count, 2)
    }

    func testEncodingAndDecodingWithNilLastDay() throws {
        // Set up state without lastDay
        rollingBool.append(true)

        XCTAssertNil(rollingBool.lastDay)

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(rollingBool)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RollingEightDaysBool.self, from: data)

        // Verify lastDay is still nil
        XCTAssertNil(decoded.lastDay)

        // Verify values were persisted
        XCTAssertEqual(decoded.allValues, [true])
    }

    func testSetTodayToTrueAfterDecodingUsesPersistedLastDay() throws {
        // Day 1: Set up initial state
        let day1 = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 20))!
        let timeMachine = TimeMachine(date: day1)
        rollingBool.setTodayToTrue(dateProvider: timeMachine)
        XCTAssertEqual(rollingBool.count, 1)
        XCTAssertNotNil(rollingBool.lastDay)

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(rollingBool)

        // Decode (simulating app restart)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RollingEightDaysBool.self, from: data)

        // Verify lastDay was restored
        XCTAssertNotNil(decoded.lastDay)
        XCTAssertTrue(Calendar.eastern.isDate(decoded.lastDay!, inSameDayAs: day1))

        // Same day: Should not add new value
        let initialCount = decoded.count
        decoded.setTodayToTrue(dateProvider: timeMachine)
        XCTAssertEqual(decoded.count, initialCount) // No change

        // Next day: Should add new value
        let day2 = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 21))!
        let timeMachine2 = TimeMachine(date: day2)
        decoded.setTodayToTrue(dateProvider: timeMachine2)
        XCTAssertEqual(decoded.count, 2) // New value added
        XCTAssertEqual(decoded.allValues, [true, true])
    }

    func testSetTodayToTrueAfterDecodingWithoutLastDayBehavesCorrectly() throws {
        let timeMachine = TimeMachine(date: referenceDate)

        // Create state without lastDay (old data format)
        rollingBool.append(true)

        // Encode
        let encoder = JSONEncoder()
        let data = try encoder.encode(rollingBool)

        // Decode
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(RollingEightDaysBool.self, from: data)

        // lastDay should be nil after decoding old format
        XCTAssertNil(decoded.lastDay)

        // First call should initialize lastDay
        decoded.setTodayToTrue(dateProvider: timeMachine)
        XCTAssertNotNil(decoded.lastDay)
        XCTAssertEqual(decoded.lastDay, referenceDate)
        XCTAssertEqual(decoded.count, 2) // Original value + new value
    }

    func testMultipleEncodeDecodesCyclesPreserveLastDay() throws {
        // Initial state
        let day1 = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 20))!
        let timeMachine = TimeMachine(date: day1)
        rollingBool.setTodayToTrue(dateProvider: timeMachine)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // First cycle
        var data = try encoder.encode(rollingBool)
        var decoded = try decoder.decode(RollingEightDaysBool.self, from: data)
        XCTAssertEqual(decoded.lastDay, rollingBool.lastDay)

        // Second cycle
        let day2 = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 21))!
        let timeMachine2 = TimeMachine(date: day2)
        decoded.setTodayToTrue(dateProvider: timeMachine2)
        data = try encoder.encode(decoded)
        let decoded2 = try decoder.decode(RollingEightDaysBool.self, from: data)
        XCTAssertTrue(Calendar.eastern.isDate(decoded2.lastDay!, inSameDayAs: day2))

        // Third cycle
        let day3 = Calendar.eastern.date(from: DateComponents(year: 2025, month: 1, day: 22))!
        let timeMachine3 = TimeMachine(date: day3)
        decoded2.setTodayToTrue(dateProvider: timeMachine3)
        data = try encoder.encode(decoded2)
        let decoded3 = try decoder.decode(RollingEightDaysBool.self, from: data)
        XCTAssertTrue(Calendar.eastern.isDate(decoded3.lastDay!, inSameDayAs: day3))

        // Verify all values are true
        XCTAssertEqual(decoded3.allValues, [true, true, true])
    }
}
