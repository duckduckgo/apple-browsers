//
//  PixelKitTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
@testable import PixelKit
import os.log

final class PixelKitTests: XCTestCase {

    private func userDefaults() -> UserDefaults {
        UserDefaults(suiteName: "testing_\(UUID().uuidString)")!
    }

    /// Test events for convenience

    private enum TestEvent: String, PixelKitEvent {

        case testEventPrefixed = "m_mac_testEventPrefixed"
        case testEvent

        var name: String {
            return rawValue
        }

        var parameters: [String: String]? {
            return nil
        }

        var error: Error? {
            return nil
        }
    }

    private enum TestEventV2: String, PixelKitEventV2 {

        case testEvent
        case testEventWithoutParameters
        case dailyEvent
        case dailyEventWithoutParameters
        case dailyAndContinuousEvent
        case dailyAndContinuousEventWithoutParameters
        case uniqueEvent = "uniqueEvent_u"
        case nameWithDot = "test.pixel.with.dot"

        var name: String {
            return rawValue
        }

        var parameters: [String: String]? {
            switch self {
            case .testEvent, .dailyEvent, .dailyAndContinuousEvent, .uniqueEvent:
                return [
                    "eventParam1": "eventParamValue1",
                    "eventParam2": "eventParamValue2"
                ]
            default:
                return nil
            }
        }

        var error: Error? {
            return nil
        }

        var frequency: PixelKit.Frequency {
            switch self {
            case .testEvent, .testEventWithoutParameters, .nameWithDot:
                return .standard
            case .uniqueEvent:
                return .uniqueByName
            case .dailyEvent, .dailyEventWithoutParameters:
                return .daily
            case .dailyAndContinuousEvent, .dailyAndContinuousEventWithoutParameters:
                return .legacyDailyAndCount
            }
        }
    }

    /// Test that a dry run won't execute the fire request callback.
    ///
    func testDryRunWontExecuteCallback() async {
        let appVersion = "1.0.5"
        let headers: [String: String] = [:]

        let pixelKit = PixelKit(dryRun: true, appVersion: appVersion, defaultHeaders: headers, dailyPixelCalendar: nil, defaults: userDefaults()) { _, _, _, _, _, _ in

            XCTFail("This callback should not be executed when doing a dry run")
        }

        pixelKit.fire(TestEventV2.testEvent)
    }

    func testNonStandardEvent() {
        func testReportBrokenSitePixel() {
            fire(NonStandardEvent(TestEventV2.testEvent),
                 frequency: .standard,
                 and: .expect(pixelName: TestEventV2.testEvent.name),
                 file: #filePath,
                 line: #line)
        }
    }

    func testDebugEventPrefixed() {
        let appVersion = "1.0.5"
        let headers = ["a": "2", "b": "3", "c": "2000"]
        let event = DebugEvent(TestEvent.testEventPrefixed)
        let userDefaults = userDefaults()

        // Set expectations
        let expectedPixelName = TestEvent.testEventPrefixed.name
        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")

        // Prepare mock to validate expectations
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                defaultHeaders: headers,
                                dailyPixelCalendar: nil,
                                defaults: userDefaults) { firedPixelName, firedHeaders, parameters, _, _, _ in

            fireCallbackCalled.fulfill()
            XCTAssertEqual(expectedPixelName, firedPixelName)
        }
        // Run test
        pixelKit.fire(event)
        // Wait for expectations to be fulfilled
        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    func testDebugEventNotPrefixed() {
        let appVersion = "1.0.5"
        let headers = ["a": "2", "b": "3", "c": "2000"]
        let event = DebugEvent(TestEvent.testEvent)
        let userDefaults = userDefaults()

        // Set expectations
        let expectedPixelName = "m_mac_debug_\(TestEvent.testEvent.name)"
        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")

        // Prepare mock to validate expectations
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                defaultHeaders: headers,
                                dailyPixelCalendar: nil,
                                defaults: userDefaults) { firedPixelName, firedHeaders, parameters, _, _, _ in

            fireCallbackCalled.fulfill()
            XCTAssertEqual(expectedPixelName, firedPixelName)
        }
        // Run test
        pixelKit.fire(event)
        // Wait for expectations to be fulfilled
        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    func testDebugEventDaily() {
        let appVersion = "1.0.5"
        let headers = ["a": "2", "b": "3", "c": "2000"]
        let event = DebugEvent(TestEvent.testEvent)
        let userDefaults = userDefaults()

        // Set expectations
        let expectedPixelName = "m_mac_debug_\(TestEvent.testEvent.name)_d"
        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")

        // Prepare mock to validate expectations
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                defaultHeaders: headers,
                                dailyPixelCalendar: nil,
                                defaults: userDefaults) { firedPixelName, firedHeaders, parameters, _, _, _ in

            fireCallbackCalled.fulfill()
            XCTAssertEqual(expectedPixelName, firedPixelName)
        }
        // Run test
        pixelKit.fire(event, frequency: .legacyDaily)
        // Wait for expectations to be fulfilled
        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    /// Tests firing a sample pixel and ensuring that all fields are properly set in the fire request callback.
    ///
    func testFiringASamplePixel() {
        // Prepare test parameters
        let appVersion = "1.0.5"
        let headers = ["a": "2", "b": "3", "c": "2000"]
        let event = TestEventV2.testEvent
        let userDefaults = userDefaults()

        // Set expectations
        let expectedPixelName = "m_mac_\(event.name)"
        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")

        // Prepare mock to validate expectations
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                source: PixelKit.Source.macDMG.rawValue,
                                defaultHeaders: headers,
                                dailyPixelCalendar: nil,
                                defaults: userDefaults) { firedPixelName, firedHeaders, parameters, _, _, _ in

            fireCallbackCalled.fulfill()

            XCTAssertEqual(expectedPixelName, firedPixelName)
            XCTAssertTrue(headers.allSatisfy({ key, value in
                firedHeaders[key] == value
            }))

            XCTAssertEqual(firedHeaders[PixelKit.Header.moreInfo], "See \(PixelKit.duckDuckGoMorePrivacyInfo)")

            XCTAssertEqual(parameters[PixelKit.Parameters.appVersion], appVersion)
#if DEBUG
            XCTAssertEqual(parameters[PixelKit.Parameters.test], PixelKit.Values.test)
#else
            XCTAssertNil(parameters[PixelKit.Parameters.test])
#endif
        }

        // Run test
        pixelKit.fire(event)

        // Wait for expectations to be fulfilled
        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    /// We test firing a daily pixel for the first time executes the fire request callback with the right parameters
    ///
    func testFiringDailyPixelForTheFirstTime() {
        // Prepare test parameters
        let appVersion = "1.0.5"
        let headers = ["a": "2", "b": "3", "c": "2000"]
        let event = TestEventV2.dailyEvent
        let userDefaults = userDefaults()

        // Set expectations
        let expectedPixelName = "m_mac_\(event.name)_d"
        let expectedMoreInfoString = "See \(PixelKit.duckDuckGoMorePrivacyInfo)"
        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")

        // Prepare mock to validate expectations
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                source: PixelKit.Source.macDMG.rawValue,
                                defaultHeaders: headers,
                                dailyPixelCalendar: nil,
                                defaults: userDefaults) { firedPixelName, firedHeaders, parameters, _, _, _ in

            fireCallbackCalled.fulfill()

            XCTAssertEqual(expectedPixelName, firedPixelName)
            XCTAssertTrue(headers.allSatisfy({ key, value in
                firedHeaders[key] == value
            }))

            XCTAssertEqual(firedHeaders[PixelKit.Header.moreInfo], expectedMoreInfoString)
            XCTAssertEqual(parameters[PixelKit.Parameters.appVersion], appVersion)
#if DEBUG
            XCTAssertEqual(parameters[PixelKit.Parameters.test], PixelKit.Values.test)
#else
            XCTAssertNil(parameters[PixelKit.Parameters.test])
#endif
        }

        // Run test
        pixelKit.fire(event, frequency: .legacyDaily)

        // Wait for expectations to be fulfilled
        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    /// We test firing a daily pixel a second time does not execute the fire request callback.
    ///
    func testDailyPixelDoubleFiringFrequency() {
        // Prepare test parameters
        let appVersion = "1.0.5"
        let headers = ["a": "2", "b": "3", "c": "2000"]
        let event = TestEventV2.dailyEvent
        let userDefaults = userDefaults()

        // Set expectations
        let expectedPixelName = "m_mac_\(event.name)_d"
        let expectedMoreInfoString = "See \(PixelKit.duckDuckGoMorePrivacyInfo)"
        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")
        fireCallbackCalled.expectedFulfillmentCount = 1
        fireCallbackCalled.assertForOverFulfill = true

        // Prepare mock to validate expectations
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                source: PixelKit.Source.macDMG.rawValue,
                                defaultHeaders: headers,
                                dailyPixelCalendar: nil,
                                defaults: userDefaults) { firedPixelName, firedHeaders, parameters, _, _, _ in

            fireCallbackCalled.fulfill()

            XCTAssertEqual(expectedPixelName, firedPixelName)
            XCTAssertTrue(headers.allSatisfy({ key, value in
                firedHeaders[key] == value
            }))

            XCTAssertEqual(firedHeaders[PixelKit.Header.moreInfo], expectedMoreInfoString)
            XCTAssertEqual(parameters[PixelKit.Parameters.appVersion], appVersion)
#if DEBUG
            XCTAssertEqual(parameters[PixelKit.Parameters.test], PixelKit.Values.test)
#else
            XCTAssertNil(parameters[PixelKit.Parameters.test])
#endif
        }

        // Run test
        pixelKit.fire(event, frequency: .legacyDaily)
        pixelKit.fire(event, frequency: .legacyDaily)

        // Wait for expectations to be fulfilled
        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    /// Test firing a daily pixel a few times
    func testDailyPixelFrequency() {
        // Prepare test parameters
        let appVersion = "1.0.5"
        let headers = ["a": "2", "b": "3", "c": "2000"]
        let event = TestEventV2.dailyEvent
        let userDefaults = userDefaults()

        let timeMachine = TimeMachine()

        // Set expectations
        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")
        fireCallbackCalled.expectedFulfillmentCount = 3
        fireCallbackCalled.assertForOverFulfill = true

        // Prepare mock to validate expectations
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                defaultHeaders: headers,
                                dailyPixelCalendar: nil,
                                dateGenerator: timeMachine.now,
                                defaults: userDefaults) { _, _, _, _, _, _ in
            fireCallbackCalled.fulfill()
        }

        // Run test
        pixelKit.fire(event, frequency: .legacyDaily) // Fired
        timeMachine.travel(by: .hour, value: 2)
        pixelKit.fire(event, frequency: .legacyDailyNoSuffix) // Skipped

        timeMachine.travel(by: .day, value: 1)
        timeMachine.travel(by: .hour, value: 2)
        pixelKit.fire(event, frequency: .legacyDailyNoSuffix) // Fired

        timeMachine.travel(by: .hour, value: 10)
        pixelKit.fire(event, frequency: .legacyDailyNoSuffix) // Skipped

        timeMachine.travel(by: .day, value: 1)
        pixelKit.fire(event, frequency: .legacyDailyNoSuffix) // Fired

        // Wait for expectations to be fulfilled
        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    /// Test firing a unique pixel
    func testUniquePixel() {
        // Prepare test parameters
        let appVersion = "1.0.5"
        let headers = ["a": "2", "b": "3", "c": "2000"]
        let event = TestEventV2.uniqueEvent
        let userDefaults = userDefaults()

        let timeMachine = TimeMachine()

        // Set expectations
        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")
        fireCallbackCalled.expectedFulfillmentCount = 1
        fireCallbackCalled.assertForOverFulfill = true

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                defaultHeaders: headers,
                                dailyPixelCalendar: nil,
                                dateGenerator: timeMachine.now,
                                defaults: userDefaults) { _, _, _, _, _, _ in
            fireCallbackCalled.fulfill()
        }

        // Run test
        pixelKit.fire(event, frequency: .uniqueByName) // Fired
        timeMachine.travel(by: .hour, value: 2)
        pixelKit.fire(event, frequency: .uniqueByName) // Skipped (already fired)

        timeMachine.travel(by: .day, value: 1)
        timeMachine.travel(by: .hour, value: 2)
        pixelKit.fire(event, frequency: .uniqueByName) // Skipped (already fired)

        timeMachine.travel(by: .hour, value: 10)
        pixelKit.fire(event, frequency: .uniqueByName) // Skipped (already fired)

        timeMachine.travel(by: .day, value: 1)
        pixelKit.fire(event, frequency: .uniqueByName) // Skipped (already fired)

        // Wait for expectations to be fulfilled
        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    func testUniqueNyNameAndParameterPixel() {
        // Prepare test parameters
        let appVersion = "1.0.5"
        let headers = ["a": "2", "b": "3", "c": "2000"]
        let event = TestEventV2.uniqueEvent
        let userDefaults = userDefaults()

        let timeMachine = TimeMachine()

        // Set expectations
        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")
        fireCallbackCalled.expectedFulfillmentCount = 3
        fireCallbackCalled.assertForOverFulfill = true

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                defaultHeaders: headers,
                                dailyPixelCalendar: nil,
                                dateGenerator: timeMachine.now,
                                defaults: userDefaults) { _, _, _, _, _, _ in
            fireCallbackCalled.fulfill()
        }

        // Run test
        pixelKit.fire(event, frequency: .uniqueByNameAndParameters, withAdditionalParameters: ["a": "100"]) // Fired
        timeMachine.travel(by: .hour, value: 2)
        pixelKit.fire(event, frequency: .uniqueByNameAndParameters, withAdditionalParameters: ["b": "200"]) // Fired
        pixelKit.fire(event, frequency: .uniqueByNameAndParameters, withAdditionalParameters: ["a": "100"]) // Skipped (already fired)

        timeMachine.travel(by: .day, value: 1)
        pixelKit.fire(event, frequency: .uniqueByNameAndParameters, withAdditionalParameters: ["a": "100", "c": "300"]) // Fired
        timeMachine.travel(by: .hour, value: 2)
        pixelKit.fire(event, frequency: .uniqueByNameAndParameters, withAdditionalParameters: ["a": "100"]) // Skipped (already fired)
        pixelKit.fire(event, frequency: .uniqueByNameAndParameters, withAdditionalParameters: ["b": "200"]) // Skipped (already fired)
        pixelKit.fire(event, frequency: .uniqueByNameAndParameters, withAdditionalParameters: ["c": "300", "a": "100"]) // Skipped (already fired)

        timeMachine.travel(by: .hour, value: 10)
        pixelKit.fire(event, frequency: .uniqueByNameAndParameters, withAdditionalParameters: ["a": "100"]) // Skipped (already fired)
        pixelKit.fire(event, frequency: .uniqueByNameAndParameters, withAdditionalParameters: ["b": "200"]) // Skipped (already fired)
        pixelKit.fire(event, frequency: .uniqueByNameAndParameters, withAdditionalParameters: ["a": "100", "c": "300"]) // Skipped (already fired)

        timeMachine.travel(by: .day, value: 1)
        pixelKit.fire(event, frequency: .uniqueByNameAndParameters, withAdditionalParameters: ["a": "100"]) // Skipped (already fired)
        pixelKit.fire(event, frequency: .uniqueByNameAndParameters, withAdditionalParameters: ["b": "200"]) // Skipped (already fired)
        pixelKit.fire(event, frequency: .uniqueByNameAndParameters, withAdditionalParameters: ["a": "100", "c": "300"]) // Skipped (already fired)

        // Wait for expectations to be fulfilled
        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    func testVPNCohort() {
        XCTAssertEqual(PixelKit.cohort(from: nil), "")
        assertCohortEqual(.init(year: 2023, month: 1, day: 1), reportAs: "week-1")
        assertCohortEqual(.init(year: 2024, month: 2, day: 24), reportAs: "week-60")
    }

    private func assertCohortEqual(_ cohort: DateComponents, reportAs reportedCohort: String) {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")

        let cohort = calendar.date(from: cohort)
        let timeMachine = TimeMachine(calendar: calendar, date: cohort)

        PixelKit.setUp(appVersion: "test",
                       defaultHeaders: [:],
                       dailyPixelCalendar: calendar,
                       dateGenerator: timeMachine.now,
                       defaults: userDefaults()) { _, _, _, _, _, _ in }

        // 1st week
        XCTAssertEqual(PixelKit.cohort(from: cohort, dateGenerator: timeMachine.now), reportedCohort)

        // 2nd week
        timeMachine.travel(by: .weekOfYear, value: 1)
        XCTAssertEqual(PixelKit.cohort(from: cohort, dateGenerator: timeMachine.now), reportedCohort)

        // 3rd week
        timeMachine.travel(by: .weekOfYear, value: 1)
        XCTAssertEqual(PixelKit.cohort(from: cohort, dateGenerator: timeMachine.now), reportedCohort)

        // 4th week
        timeMachine.travel(by: .weekOfYear, value: 1)
        XCTAssertEqual(PixelKit.cohort(from: cohort, dateGenerator: timeMachine.now), reportedCohort)

        // 5th week
        timeMachine.travel(by: .weekOfYear, value: 1)
        XCTAssertEqual(PixelKit.cohort(from: cohort, dateGenerator: timeMachine.now), reportedCohort)

        // 6th week
        timeMachine.travel(by: .weekOfYear, value: 1)
        XCTAssertEqual(PixelKit.cohort(from: cohort, dateGenerator: timeMachine.now), reportedCohort)

        // 7th week
        timeMachine.travel(by: .weekOfYear, value: 1)
        XCTAssertEqual(PixelKit.cohort(from: cohort, dateGenerator: timeMachine.now), reportedCohort)

        // 8th week
        timeMachine.travel(by: .weekOfYear, value: 1)
        XCTAssertEqual(PixelKit.cohort(from: cohort, dateGenerator: timeMachine.now), "")
    }
}

private class TimeMachine {
    private var date: Date
    private let calendar: Calendar

    init(calendar: Calendar? = nil, date: Date? = nil) {
        self.calendar = calendar ?? {
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            calendar.locale = Locale(identifier: "en_US_POSIX")
            return calendar
        }()
        self.date = date ?? .init(timeIntervalSince1970: 0)
    }

    func travel(by component: Calendar.Component, value: Int) {
        date = calendar.date(byAdding: component, value: value, to: now())!
    }

    func now() -> Date {
        date
    }
}
