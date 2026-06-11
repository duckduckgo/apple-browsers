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

        var standardParameters: [PixelKitStandardParameter]? {
            switch self {
            case .testEventPrefixed,
                    .testEvent:
                return [.pixelSource]
            }
        }

    }

    private enum TestEventV2: String, PixelKitEvent {

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

        var standardParameters: [PixelKitStandardParameter]? {
            switch self {
            case .testEvent,
                    .testEventWithoutParameters,
                    .dailyEvent,
                    .dailyEventWithoutParameters,
                    .dailyAndContinuousEvent,
                    .dailyAndContinuousEventWithoutParameters,
                    .uniqueEvent,
                    .nameWithDot:
                return [.pixelSource]
            }
        }
    }

    /// Test that a dry run won't execute the fire request callback.
    ///
    func testDryRunWontExecuteCallback() async {
        let appVersion = "1.0.5"
        let headers: [String: String] = [:]

        let pixelKit = PixelKit(dryRun: true,
                                appVersion: appVersion,
                                defaultHeaders: headers,
                                pixelCalendar: nil,
                                defaults: userDefaults()) { _, _, _, _, _, _ in
            XCTFail("This callback should not be executed when doing a dry run")
        }

        pixelKit.fire(TestEventV2.testEvent)
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
                                pixelCalendar: nil,
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
                                pixelCalendar: nil,
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
                                pixelCalendar: nil,
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
                                pixelCalendar: nil,
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
                                pixelCalendar: nil,
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
                                pixelCalendar: nil,
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

    /// Firing the same pixel name as both `.daily` and `.monthly` must use independent
    /// fire dates: a daily skip-window must not suppress the monthly fire, and a monthly
    /// skip-window must not suppress the daily fire.
    func testDailyAndMonthlyOperateIndependentlyForSamePixelName() {
        let appVersion = "1.0.5"
        let event = TestEventV2.dailyEvent
        let userDefaults = userDefaults()

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        // Start mid-month so we can travel across a day boundary without crossing a month
        // boundary on the next hop.
        let startDate = calendar.date(from: .init(year: 2025, month: 1, day: 15))!
        let timeMachine = TimeMachine(calendar: calendar, date: startDate)

        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")
        fireCallbackCalled.expectedFulfillmentCount = 4
        fireCallbackCalled.assertForOverFulfill = true

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                defaultHeaders: [:],
                                pixelCalendar: calendar,
                                dateGenerator: timeMachine.now,
                                defaults: userDefaults) { _, _, _, _, _, _ in
            fireCallbackCalled.fulfill()
        }

        // Jan 15: first call of each frequency — both Fired (independent storage slots).
        pixelKit.fire(event, frequency: .daily)
        pixelKit.fire(event, frequency: .monthly)

        // Jan 15 retries — both Skipped.
        pixelKit.fire(event, frequency: .daily)
        pixelKit.fire(event, frequency: .monthly)

        // Jan 16: new day, same month.
        timeMachine.travel(by: .day, value: 1)
        pixelKit.fire(event, frequency: .daily)   // Fired (new day) — must not be suppressed by monthly date
        pixelKit.fire(event, frequency: .monthly) // Skipped (same month) — must not be reset by daily fire

        // Feb 1: new month.
        timeMachine.travel(by: .day, value: 16)
        pixelKit.fire(event, frequency: .monthly) // Fired (new month)

        wait(for: [fireCallbackCalled], timeout: 0.5)

        // Storage should carry both entries at the same per-pixel UserDefaults key.
        let storageKey = "com.duckduckgo.network-protection.pixel.m_mac_\(event.name)"
        let map = userDefaults.object(forKey: storageKey) as? [String: Date]
        XCTAssertNotNil(map?["daily"], "Daily fire date missing from storage")
        XCTAssertNotNil(map?["monthly"], "Monthly fire date missing from storage")
        XCTAssertNotEqual(map?["daily"], map?["monthly"], "Daily and monthly should track different dates")
    }

    /// A pixel whose last-fire date was previously stored as a raw `Date` (legacy format)
    /// should still be recognized as fired today AND have its storage migrated to a
    /// `[frequency.mapKey: Date]` map on the next `pixelHasBeenFiredDailyToday` check.
    func testDailyPixelMigratesLegacyRawDateStorageToMap() throws {
        let appVersion = "1.0.5"
        let event = TestEventV2.dailyEvent
        let userDefaults = userDefaults()
        let timeMachine = TimeMachine()

        // The on-disk key matches what PixelKit derives internally for macOS-prefixed pixels.
        let prefixedName = "m_mac_\(event.name)"
        let storageKey = "com.duckduckgo.network-protection.pixel.\(prefixedName)"
        let legacyDate = timeMachine.now()
        userDefaults.set(legacyDate, forKey: storageKey)

        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")
        fireCallbackCalled.isInverted = true

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                source: PixelKit.Source.macDMG.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                dateGenerator: timeMachine.now,
                                defaults: userDefaults) { _, _, _, _, _, _ in
            fireCallbackCalled.fulfill()
        }

        // Firing on the same day as the legacy date — pixel must be skipped.
        pixelKit.fire(event, frequency: .legacyDaily)
        wait(for: [fireCallbackCalled], timeout: 0.2)

        // Storage should now be a [frequency.mapKey: Date] map, preserving the legacy date
        // under the canonical "daily" key shared by all daily-family frequencies.
        let migrated = userDefaults.object(forKey: storageKey) as? [String: Date]
        XCTAssertNotNil(migrated, "Legacy raw-Date storage was not migrated to a map")
        XCTAssertEqual(migrated?["daily"], legacyDate)
    }

    /// Regression test for "Monthly update drops legacy daily date": firing a new frequency
    /// (monthly) on a pixel that still has a legacy raw-`Date` (its daily last-fire date) must
    /// preserve that daily date when upgrading storage to the map, rather than discarding it
    /// (which would let the daily pixel re-fire the same day after the upgrade).
    func testMonthlyFirePreservesLegacyDailyDate() throws {
        let appVersion = "1.0.5"
        let event = TestEventV2.dailyEvent
        let userDefaults = userDefaults()
        let timeMachine = TimeMachine()

        let prefixedName = "m_mac_\(event.name)"
        let storageKey = "com.duckduckgo.network-protection.pixel.\(prefixedName)"
        let legacyDate = timeMachine.now()
        userDefaults.set(legacyDate, forKey: storageKey)

        let fired = expectation(description: "monthly pixel fires")
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                source: PixelKit.Source.macDMG.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                dateGenerator: timeMachine.now,
                                defaults: userDefaults) { _, _, _, _, _, _ in
            fired.fulfill()
        }

        // No prior monthly date, so this fires and upgrades storage from raw Date to the map format.
        pixelKit.fire(event, frequency: .monthly)
        wait(for: [fired], timeout: 0.2)

        let map = userDefaults.object(forKey: storageKey) as? [String: Date]
        XCTAssertEqual(map?["daily"], legacyDate, "Legacy daily last-fire date must survive the monthly upgrade")
        XCTAssertNotNil(map?["monthly"], "Monthly fire date should be recorded")
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
                                pixelCalendar: nil,
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
                                pixelCalendar: nil,
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

    func testUniqueByNameAndParameterPixel() {
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
                                pixelCalendar: nil,
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

        PixelKit.setUp(dryRun: true,
                       appVersion: "test",
                       session: "test",
                       defaultHeaders: [:],
                       pixelCalendar: calendar,
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

    func testWhenChannelIsSetThenPixelIncludesChannelParameter() {
        let fireCallbackCalled = expectation(description: "Pixel fired")

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                channel: "canary",
                                defaultHeaders: [:],
                                defaults: userDefaults()) { _, _, parameters, _, _, completion in
            fireCallbackCalled.fulfill()
            XCTAssertEqual(parameters[PixelKit.Parameters.channel], "canary")
            completion(true, nil)
        }

        pixelKit.fire(TestEventV2.testEvent)
        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    /// We test firing a monthly pixel for the first time executes the fire request callback with the `_monthly` suffix.
    ///
    func testFiringMonthlyPixelForTheFirstTime() {
        let appVersion = "1.0.5"
        let headers = ["a": "2", "b": "3", "c": "2000"]
        let event = TestEventV2.dailyEvent
        let userDefaults = userDefaults()

        let expectedPixelName = "m_mac_\(event.name)_monthly"
        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                source: PixelKit.Source.macDMG.rawValue,
                                defaultHeaders: headers,
                                pixelCalendar: nil,
                                defaults: userDefaults) { firedPixelName, _, _, _, _, _ in
            fireCallbackCalled.fulfill()
            XCTAssertEqual(expectedPixelName, firedPixelName)
        }

        pixelKit.fire(event, frequency: .monthly)

        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    /// We test firing a monthly pixel a second time in the same calendar month does not execute the fire request callback.
    ///
    func testMonthlyPixelDoubleFiringFrequency() {
        let appVersion = "1.0.5"
        let headers = ["a": "2", "b": "3", "c": "2000"]
        let event = TestEventV2.dailyEvent
        let userDefaults = userDefaults()

        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")
        fireCallbackCalled.expectedFulfillmentCount = 1
        fireCallbackCalled.assertForOverFulfill = true

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                source: PixelKit.Source.macDMG.rawValue,
                                defaultHeaders: headers,
                                pixelCalendar: nil,
                                defaults: userDefaults) { _, _, _, _, _, _ in
            fireCallbackCalled.fulfill()
        }

        pixelKit.fire(event, frequency: .monthly)
        pixelKit.fire(event, frequency: .monthly)

        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    /// Test that monthly pixels fire once per calendar month (UTC), not on a rolling 30-day window.
    ///
    func testMonthlyPixelFrequency() {
        let appVersion = "1.0.5"
        let headers = ["a": "2", "b": "3", "c": "2000"]
        let event = TestEventV2.dailyEvent
        let userDefaults = userDefaults()

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        // Start on the 15th of a month so we can travel to month-end and across a year boundary.
        let startDate = calendar.date(from: .init(year: 2025, month: 1, day: 15))!
        let timeMachine = TimeMachine(calendar: calendar, date: startDate)

        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")
        fireCallbackCalled.expectedFulfillmentCount = 3
        fireCallbackCalled.assertForOverFulfill = true

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                defaultHeaders: headers,
                                pixelCalendar: calendar,
                                dateGenerator: timeMachine.now,
                                defaults: userDefaults) { _, _, _, _, _, _ in
            fireCallbackCalled.fulfill()
        }

        // Jan 15: first fire — Fired
        pixelKit.fire(event, frequency: .monthly)

        // Jan 16: same month — Skipped
        timeMachine.travel(by: .day, value: 1)
        pixelKit.fire(event, frequency: .monthly)

        // Jan 31: still January — Skipped
        timeMachine.travel(by: .day, value: 15)
        pixelKit.fire(event, frequency: .monthly)

        // Feb 1: new calendar month — Fired
        timeMachine.travel(by: .day, value: 1)
        pixelKit.fire(event, frequency: .monthly)

        // Feb 28: still February — Skipped
        timeMachine.travel(by: .day, value: 27)
        pixelKit.fire(event, frequency: .monthly)

        // Jan 15 next year: same month-of-year but different year — Fired
        timeMachine.travel(by: .month, value: 11)
        pixelKit.fire(event, frequency: .monthly)

        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    func testWhenChannelIsNilThenPixelOmitsChannelParameter() {
        let fireCallbackCalled = expectation(description: "Pixel fired")

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                defaultHeaders: [:],
                                defaults: userDefaults()) { _, _, parameters, _, _, completion in
            fireCallbackCalled.fulfill()
            XCTAssertNil(parameters[PixelKit.Parameters.channel])
            completion(true, nil)
        }

        pixelKit.fire(TestEventV2.testEvent)
        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    func testWhenChannelIsSetThenItCoexistsWithOtherStandardParameters() {
        let fireCallbackCalled = expectation(description: "Pixel fired")

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "2.0.0",
                                source: "browser-dmg",
                                channel: "canary",
                                defaultHeaders: [:],
                                defaults: userDefaults()) { _, _, parameters, _, _, completion in
            fireCallbackCalled.fulfill()
            XCTAssertEqual(parameters[PixelKit.Parameters.channel], "canary")
            XCTAssertEqual(parameters[PixelKit.Parameters.appVersion], "2.0.0")
            XCTAssertEqual(parameters[PixelKit.Parameters.pixelSource], "browser-dmg")
            completion(true, nil)
        }

        pixelKit.fire(TestEventV2.testEvent)
        wait(for: [fireCallbackCalled], timeout: 0.5)
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
