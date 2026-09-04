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
@_spi(Testing) import PixelKit
import os.log

final class PixelKitTests: XCTestCase {

    private func userDefaults() -> UserDefaults {
        UserDefaults(suiteName: "testing_\(UUID().uuidString)")!
    }

    /// Test events for convenience

    private enum TestEvent: String, PixelKit.Event {

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

    private enum TestEventV2: String, PixelKit.Event {

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

    /// `.debounce(seconds:)` suppresses re-firing the same pixel within the window, anchored to the
    /// last *actual* fire (a suppressed call must not extend the window), and fires again once at least
    /// `seconds` have elapsed since the last fire.
    func testDebounceSuppressesWithinWindowAndFiresAfterWindow() {
        let appVersion = "1.0.5"
        let event = TestEventV2.testEventWithoutParameters
        let userDefaults = userDefaults()
        let timeMachine = TimeMachine()

        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")
        fireCallbackCalled.expectedFulfillmentCount = 2
        fireCallbackCalled.assertForOverFulfill = true

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                source: PixelKit.Source.macDMG.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                dateGenerator: timeMachine.now,
                                defaults: userDefaults) { _, _, _, _, _, _ in
            fireCallbackCalled.fulfill()
        }

        pixelKit.fire(event, frequency: .debounce(seconds: 5))   // t0 — Fired
        timeMachine.travel(by: .second, value: 2)
        pixelKit.fire(event, frequency: .debounce(seconds: 5))   // t0+2 — Skipped (within window)
        timeMachine.travel(by: .second, value: 4)
        pixelKit.fire(event, frequency: .debounce(seconds: 5))   // t0+6 — Fired (window elapsed since t0)

        wait(for: [fireCallbackCalled], timeout: 0.5)
    }

    /// `.debounce(seconds: 0)` is an empty window, so it never suppresses and fires every time.
    func testDebounceWithZeroSecondsAlwaysFires() {
        let appVersion = "1.0.5"
        let event = TestEventV2.testEventWithoutParameters
        let userDefaults = userDefaults()
        let timeMachine = TimeMachine()

        let fireCallbackCalled = expectation(description: "Expect the pixel firing callback to be called")
        fireCallbackCalled.expectedFulfillmentCount = 3
        fireCallbackCalled.assertForOverFulfill = true

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: appVersion,
                                source: PixelKit.Source.macDMG.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                dateGenerator: timeMachine.now,
                                defaults: userDefaults) { _, _, _, _, _, _ in
            fireCallbackCalled.fulfill()
        }

        pixelKit.fire(event, frequency: .debounce(seconds: 0))
        pixelKit.fire(event, frequency: .debounce(seconds: 0))
        pixelKit.fire(event, frequency: .debounce(seconds: 0))

        wait(for: [fireCallbackCalled], timeout: 0.5)
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

    // MARK: - Async fire

    private struct AsyncFireSampleError: Error, Equatable {}

    /// Minimal `PixelFiring` conformer that drives the `fireAsync` bridge with fixed completion results,
    /// without involving `PixelKit`'s frequency or retry-queue machinery (and the shared state that comes with it).
    /// Each element of `completions` triggers one `onComplete` call, mimicking multi-request frequencies
    /// such as `.dailyAndCount` when more than one is provided.
    private struct StubPixelFiring: PixelFiring {
        let completions: [(fired: Bool, error: (any Error)?)]

        init(fired: Bool, error: (any Error)?) {
            self.completions = [(fired, error)]
        }

        init(completions: [(fired: Bool, error: (any Error)?)]) {
            self.completions = completions
        }

        func fire(event: PixelKit.Event,
                  frequency: PixelKit.Frequency,
                  options: PixelKit.Options,
                  onComplete: @escaping PixelKit.CompletionBlock) {
            for completion in completions {
                onComplete(completion.fired, completion.error)
            }
        }
    }

    /// `PixelKit` instance backed by an always-succeeding fire request, with a unique defaults suite and
    /// retry-queue session so tests never share persisted frequency or retry state.
    private func makePixelKit(fireRequest: @escaping PixelKit.FireRequest = { _, _, _, _, _, completion in completion(true, nil) }) -> PixelKit {
        PixelKit(dryRun: false,
                 appVersion: "1.0.0",
                 session: UUID().uuidString,
                 defaultHeaders: [:],
                 pixelCalendar: nil,
                 defaults: userDefaults(),
                 fireRequest: fireRequest)
    }

    /// `fireAsync` returns `.sent` and resolves once the underlying request reports success.
    func testAsyncFireReturnsSentWhenRequestSucceeds() async throws {
        let pixelKit = makePixelKit()

        let result = try await pixelKit.fireAsync(TestEventV2.testEvent)

        XCTAssertEqual(result, .sent)
    }

    /// `fireAsync` returns `.suppressed` (without throwing) when a daily pixel is suppressed by frequency rules.
    func testAsyncFireReturnsSuppressedWhenSuppressedByDailyFrequency() async throws {
        let pixelKit = makePixelKit()

        let firstFire = try await pixelKit.fireAsync(TestEventV2.dailyEvent, frequency: .daily)
        let secondFire = try await pixelKit.fireAsync(TestEventV2.dailyEvent, frequency: .daily)

        XCTAssertEqual(firstFire, .sent)
        XCTAssertEqual(secondFire, .suppressed)
    }

    /// Legacy frequencies are suppressed inside their handlers (not the early frequency pre-checks);
    /// before those handlers reported suppression to the completion, this second `await` hung forever.
    func testAsyncFireReturnsSuppressedWhenSuppressedByLegacyDailyFrequency() async throws {
        let pixelKit = makePixelKit()

        let firstFire = try await pixelKit.fireAsync(TestEventV2.dailyEvent, frequency: .legacyDaily)
        let secondFire = try await pixelKit.fireAsync(TestEventV2.dailyEvent, frequency: .legacyDaily)

        XCTAssertEqual(firstFire, .sent)
        XCTAssertEqual(secondFire, .suppressed)
    }

    /// `.dailyAndCount` fires two requests (`_daily` and `_count`), completing once per request:
    /// `fireAsync` waits for both before returning, so both have fired by the time it resumes and
    /// no expectation is needed to observe them.
    func testAsyncFireWithDailyAndCountWaitsForBothLegs() async throws {
        let namesLock = NSLock()
        var firedPixelNames = [String]()

        let pixelKit = makePixelKit { pixelName, _, _, _, _, completion in
            namesLock.lock()
            firedPixelNames.append(pixelName)
            namesLock.unlock()
            completion(true, nil)
        }

        let result = try await pixelKit.fireAsync(TestEventV2.dailyEvent, frequency: .dailyAndCount)

        XCTAssertEqual(result, .sent)
        namesLock.lock()
        let names = firedPixelNames
        namesLock.unlock()
        XCTAssertTrue(names.contains { $0.hasSuffix("_daily") },
                      "the _daily leg must have fired before fireAsync resumed")
        XCTAssertTrue(names.contains { $0.hasSuffix("_count") },
                      "the _count leg must have fired before fireAsync resumed")
    }

    /// The second fire of the day suppresses the `_daily` leg and sends only `_count`. The
    /// suppressed leg still completes, so waiting for every leg must not hang.
    func testAsyncFireWithDailyAndCountResolvesWhenTheDailyLegIsThrottled() async throws {
        let pixelKit = makePixelKit()

        let firstFire = try await pixelKit.fireAsync(TestEventV2.dailyEvent, frequency: .dailyAndCount)
        let secondFire = try await pixelKit.fireAsync(TestEventV2.dailyEvent, frequency: .dailyAndCount)

        XCTAssertEqual(firstFire, .sent)
        XCTAssertEqual(secondFire, .sent, "the _count leg still sends once the _daily leg is throttled")
    }

    /// `.suppressed` only when every leg was suppressed.
    func testAsyncFireWithTwoLegsReturnsSuppressedOnlyWhenEveryLegIsSuppressed() async throws {
        let allSuppressed = StubPixelFiring(completions: [(fired: false, error: nil),
                                                          (fired: false, error: nil)])
        let oneSent = StubPixelFiring(completions: [(fired: false, error: nil),
                                                    (fired: true, error: nil)])

        let suppressedResult = try await allSuppressed.fireAsync(TestEventV2.dailyEvent, frequency: .dailyAndCount)
        let sentResult = try await oneSent.fireAsync(TestEventV2.dailyEvent, frequency: .dailyAndCount)

        XCTAssertEqual(suppressedResult, .suppressed)
        XCTAssertEqual(sentResult, .sent)
    }

    /// An error on any leg surfaces, and only once every leg has finished.
    func testAsyncFireWithTwoLegsThrowsTheFirstLegErrorAfterAllLegsFinish() async {
        let expectedError = AsyncFireSampleError()
        // The error arrives on the second leg, so resolving on the first completion would have
        // returned `.sent` and swallowed it.
        let pixelFiring = StubPixelFiring(completions: [(fired: true, error: nil),
                                                        (fired: false, error: expectedError)])

        do {
            _ = try await pixelFiring.fireAsync(TestEventV2.dailyEvent, frequency: .dailyAndCount)
            XCTFail("Expected fireAsync to throw the error reported by the second leg")
        } catch let error as AsyncFireSampleError {
            XCTAssertEqual(error, expectedError)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    /// `PixelKitMock` has to complete once per leg, like the real thing, otherwise `fireAsync`
    /// waits for a leg that never reports and an awaiting caller stays suspended forever.
    func testPixelKitMockCompletesOncePerLeg() {
        for frequency in [PixelKit.Frequency.standard, .daily, .legacyDailyAndCount, .dailyAndCount, .dailyAndStandard] {
            let pixelKitMock = PixelKitMock()
            var completionCount = 0

            pixelKitMock.fire(event: TestEventV2.dailyEvent, frequency: frequency, options: .default) { _, _ in
                completionCount += 1
            }

            XCTAssertEqual(completionCount, frequency.legCount, "\(frequency) completed \(completionCount) times")
            XCTAssertEqual(pixelKitMock.actualFireCalls.count, 1,
                           "the mock records the fire call once, however many legs it completes")
        }
    }

    /// The async path over the mock, which would suspend forever if the mock under-completed.
    func testAsyncFireThroughPixelKitMockResolvesForATwoLegFrequency() async throws {
        let pixelKitMock = PixelKitMock()

        let result = try await pixelKitMock.fireAsync(TestEventV2.dailyEvent, frequency: .legacyDailyAndCount)

        XCTAssertEqual(result, .sent)
    }

    /// A single-leg frequency expects one completion. If the handler somehow over-completes,
    /// `fireAsync` resolves on the first and ignores the rest rather than trapping.
    func testAsyncFireIgnoresCompletionsBeyondTheExpectedLegCount() async throws {
        let pixelFiring = StubPixelFiring(completions: [(fired: true, error: nil),
                                                        (fired: false, error: AsyncFireSampleError())])

        let result = try await pixelFiring.fireAsync(TestEventV2.testEvent)

        XCTAssertEqual(result, .sent)
    }

    /// `fireAsync` rethrows the error reported by the underlying completion handler.
    func testAsyncFireThrowsWhenRequestFails() async {
        let expectedError = AsyncFireSampleError()
        let pixelFiring = StubPixelFiring(fired: false, error: expectedError)

        do {
            _ = try await pixelFiring.fireAsync(TestEventV2.testEvent)
            XCTFail("Expected fireAsync to throw")
        } catch let error as AsyncFireSampleError {
            XCTAssertEqual(error, expectedError)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Options parity

    /// Fires `event` through both the legacy wide-parameter entry point and the new `options:` one,
    /// and returns the resulting (pixelName, parameters) pair from each.
    ///
    /// Headers are captured too. An earlier version of this helper ignored them, which let a
    /// headers-only behaviour difference slip through unnoticed.
    private func firedNameAndParameters(
        legacy: (PixelKit) -> Void,
        options: (PixelKit) -> Void
    ) -> (legacy: (String, [String: String]), options: (String, [String: String])) {
        var captured = [(String, [String: String])]()
        var capturedHeaders = [[String: String]]()
        let lock = NSLock()
        let pixelKit = makePixelKit { pixelName, headers, parameters, _, _, completion in
            lock.lock()
            captured.append((pixelName, parameters))
            capturedHeaders.append(headers)
            lock.unlock()
            completion(true, nil)
        }

        legacy(pixelKit)
        options(pixelKit)

        lock.lock()
        defer { lock.unlock() }
        XCTAssertEqual(captured.count, 2, "Expected exactly one request from each entry point")
        XCTAssertEqual(capturedHeaders.count, 2)
        XCTAssertEqual(capturedHeaders[0], capturedHeaders[1],
                       "Legacy and options paths must send identical headers")
        return (captured[0], captured[1])
    }

    /// The `options:` entry point must produce byte-identical pixel names and parameters to the
    /// legacy wide-parameter one. Pixel names are contractual, so any divergence between the two
    /// entry points would silently rename production pixels.
    func testOptionsPathMatchesLegacyPathForDefaults() {
        let result = firedNameAndParameters(
            legacy: { $0.fire(TestEventV2.testEventWithoutParameters) },
            options: { $0.fire(TestEventV2.testEventWithoutParameters, options: .default) }
        )
        XCTAssertEqual(result.legacy.0, result.options.0)
        XCTAssertEqual(result.legacy.1, result.options.1)
    }

    /// Naming no longer crosses the legacy/options boundary at all: it comes from the event, so
    /// both entry points must agree for an event that states its own prefix.
    func testBothEntryPointsHonourTheEventsOwnPrefix() {
        let result = firedNameAndParameters(
            legacy: { $0.fire(PrefixStatingEvent(namePrefix: .custom("custom_"))) },
            options: { $0.fire(PrefixStatingEvent(namePrefix: .custom("custom_")), options: .default) }
        )
        XCTAssertEqual(result.legacy.0, result.options.0)
        XCTAssertEqual(result.legacy.0, "custom_prefix_stating_event")
        XCTAssertEqual(result.legacy.1, result.options.1)
    }

    func testAnEventCanDeclineAPrefixEntirely() {
        let result = firedNameAndParameters(
            legacy: { $0.fire(PrefixStatingEvent(namePrefix: .none)) },
            options: { $0.fire(PrefixStatingEvent(namePrefix: .none), options: .default) }
        )
        XCTAssertEqual(result.legacy.0, result.options.0)
        XCTAssertEqual(result.legacy.0, "prefix_stating_event")
    }

    /// `prefixed(_:)` is how a shared package applies a host-chosen prefix without putting naming
    /// back into `Options`.
    func testPrefixedDecoratorAppliesThePrefixAndForwardsEverythingElse() {
        let result = firedNameAndParameters(
            legacy: { $0.fire(PrefixStatingEvent(namePrefix: .none).prefixed("m_ios_")) },
            options: { $0.fire(PrefixStatingEvent(namePrefix: .none).prefixed("m_ios_"), options: .default) }
        )
        XCTAssertEqual(result.legacy.0, "m_ios_prefix_stating_event")
        XCTAssertEqual(result.legacy.0, result.options.0)
        XCTAssertEqual(result.legacy.1, result.options.1)
    }

    func testOptionsPathMatchesLegacyPathWithoutAppVersion() {
        let result = firedNameAndParameters(
            legacy: { $0.fire(TestEventV2.testEventWithoutParameters, includeAppVersionParameter: false) },
            options: { $0.fire(TestEventV2.testEventWithoutParameters, options: .withoutAppVersion) }
        )
        XCTAssertEqual(result.legacy.0, result.options.0)
        XCTAssertEqual(result.legacy.1, result.options.1)
        XCTAssertNil(result.options.1["appVersion"], "withoutAppVersion must drop the appVersion parameter")
    }

    func testOptionsPathMatchesLegacyPathForAdditionalParameters() {
        let extra = ["source": "menu", "eventParam1": "overridden"]
        let result = firedNameAndParameters(
            legacy: { $0.fire(TestEventV2.testEvent, withAdditionalParameters: extra) },
            options: { $0.fire(TestEventV2.testEvent, options: .parameters(extra)) }
        )
        XCTAssertEqual(result.legacy.0, result.options.0)
        XCTAssertEqual(result.legacy.1, result.options.1)
        XCTAssertEqual(result.options.1["eventParam1"], "overridden",
                       "additionalParameters must win over the event's own parameters")
    }

    // MARK: - Header semantics

    /// Captures the headers of a single fired request.
    private func firedHeaders(defaultHeaders: [String: String],
                              _ fire: (PixelKit) -> Void) -> [String: String] {
        var captured = [String: String]()
        let lock = NSLock()
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                session: UUID().uuidString,
                                defaultHeaders: defaultHeaders,
                                pixelCalendar: nil,
                                defaults: userDefaults()) { _, headers, _, _, _, completion in
            lock.lock()
            captured = headers
            lock.unlock()
            completion(true, nil)
        }
        fire(pixelKit)
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    /// An event that opts in fires a dotted name without tripping the naming assertion.
    /// Several legacy iOS pixel names interpolate a bucketed value such as `0.5`.
    func testDottedNameFiresWhenTheEventAllowsIt() {
        let userDefaults = UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!
        var firedNames: [String] = []
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                source: PixelKit.Source.iOS.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                defaults: userDefaults) { name, _, _, _, _, _ in
            firedNames.append(name)
        }

        pixelKit.fire(DottedNameTestEvent())

        XCTAssertEqual(firedNames, ["m_debug_app-did-finish-launching-time-0.5_ios_phone"])
    }

    /// `Options.userAgent` reaches the fire request under `Header.userAgent`, which is the key a
    /// host reads in preference to its own pixel user agent.
    func testUserAgentOptionIsDeliveredUnderTheUserAgentHeaderKey() {
        let headers = firedHeaders(defaultHeaders: [:]) {
            $0.fire(TestEventV2.testEventWithoutParameters, options: .userAgent("Custom/1.0"))
        }
        XCTAssertEqual(headers[PixelKit.Header.userAgent], "Custom/1.0")
    }

    /// Without the option the key is absent, so the host falls back to its own pixel user agent.
    func testNoUserAgentHeaderWhenTheOptionIsUnset() {
        let headers = firedHeaders(defaultHeaders: [:]) {
            $0.fire(TestEventV2.testEventWithoutParameters)
        }
        XCTAssertNil(headers[PixelKit.Header.userAgent])
    }

    /// `Options.userAgent` wins over a `User-Agent` in `Options.headers`, so the dedicated option is
    /// always the one that decides.
    func testUserAgentOptionOverridesAUserAgentInHeaders() {
        var options = PixelKit.Options.userAgent("Custom/1.0")
        options.headers = [PixelKit.Header.userAgent: "FromHeaders/9.9"]
        let headers = firedHeaders(defaultHeaders: [:]) {
            $0.fire(TestEventV2.testEventWithoutParameters, options: options)
        }
        XCTAssertEqual(headers[PixelKit.Header.userAgent], "Custom/1.0")
    }

    /// Omitting headers sends the instance's `defaultHeaders`.
    func testOmittingHeadersSendsDefaultHeaders() {
        let headers = firedHeaders(defaultHeaders: ["X-Default": "yes"]) {
            $0.fire(TestEventV2.testEventWithoutParameters)
        }
        XCTAssertEqual(headers["X-Default"], "yes")
    }

    /// Supplying headers *replaces* `defaultHeaders`, it does not merge with them.
    ///
    /// This is long-standing PixelKit behaviour (`headers ?? defaultHeaders` in `fire(pixelNamed:)`)
    /// and is easy to misread as merging. Pinned here so the semantics are explicit, and so that
    /// changing it later is a deliberate decision with a failing test rather than a silent shift in
    /// what every custom-header pixel puts on the wire.
    func testSupplyingHeadersReplacesDefaultHeaders() {
        let headers = firedHeaders(defaultHeaders: ["X-Default": "yes"]) {
            $0.fire(TestEventV2.testEventWithoutParameters, options: .init(headers: ["X-Custom": "1"]))
        }
        XCTAssertEqual(headers["X-Custom"], "1")
        XCTAssertNil(headers["X-Default"], "Supplied headers replace defaultHeaders rather than merging")
    }

    /// The options path must treat headers exactly as the legacy path did.
    func testOptionsHeadersMatchLegacyHeaders() {
        let viaLegacy = firedHeaders(defaultHeaders: ["X-Default": "yes"]) {
            $0.fire(TestEventV2.testEventWithoutParameters, withHeaders: ["X-Custom": "1"])
        }
        let viaOptions = firedHeaders(defaultHeaders: ["X-Default": "yes"]) {
            $0.fire(TestEventV2.testEventWithoutParameters, options: .init(headers: ["X-Custom": "1"]))
        }
        XCTAssertEqual(viaLegacy, viaOptions)
    }

    /// The static entry point must send the same headers as the instance one.
    ///
    /// These used to disagree: the legacy static defaulted `withHeaders` to `[:]` while the instance
    /// defaulted to `nil`, and since `fire(pixelNamed:)` does `headers ?? defaultHeaders`, a
    /// non-nil `[:]` meant static calls dropped `defaultHeaders` entirely. The options-based static
    /// passes `nil`, so both now behave the same. Only observable where `defaultHeaders` is
    /// non-empty, which today is just the macOS VPN packet tunnel.
    func testStaticFireSendsSameHeadersAsInstanceFire() {
        defer { PixelKit.tearDown() }

        let viaInstance = firedHeaders(defaultHeaders: ["X-Default": "yes"]) {
            $0.fire(TestEventV2.testEventWithoutParameters)
        }

        var viaStatic = [String: String]()
        let lock = NSLock()
        PixelKit.setUp(dryRun: false,
                       appVersion: "1.0.0",
                       session: UUID().uuidString,
                       defaultHeaders: ["X-Default": "yes"],
                       defaults: userDefaults()) { _, headers, _, _, _, completion in
            lock.lock()
            viaStatic = headers
            lock.unlock()
            completion(true, nil)
        }
        PixelKit.fire(TestEventV2.testEventWithoutParameters)

        lock.lock()
        let staticHeaders = viaStatic
        lock.unlock()

        XCTAssertEqual(staticHeaders["X-Default"], "yes",
                       "The static entry point must not drop defaultHeaders")
        XCTAssertEqual(staticHeaders, viaInstance)
    }

    /// An event that states its own prefix, which is where naming lives now.
    private struct PrefixStatingEvent: PixelKit.Event {
        let namePrefix: PixelKitNamePrefix
        let name = "prefix_stating_event"
        let parameters: [String: String]? = nil
        let standardParameters: [PixelKitStandardParameter]? = nil
    }

    /// `m_netp_daily_active_d` is a real shipped name whose `_d` is part of the name, not a
    /// frequency suffix PixelKit appended. `.legacyDailyNoSuffix` exists precisely for it.
    private struct LegacyDailyNoSuffixTestEvent: PixelKit.Event {
        let namePrefix: PixelKitNamePrefix = .none
        let name = "m_netp_daily_active_d"
        let parameters: [String: String]? = nil
        let standardParameters: [PixelKitStandardParameter]? = nil
    }

    // MARK: - Options presets

    func testOptionsPresetsMatchTheirMemberwiseEquivalents() {
        XCTAssertEqual(PixelKit.Options.default, PixelKit.Options())
        XCTAssertEqual(PixelKit.Options.withoutAppVersion, PixelKit.Options(includeAppVersionParameter: false))
        XCTAssertEqual(PixelKit.Options.parameters(["a": "b"]),
                       PixelKit.Options(additionalParameters: ["a": "b"]))
        XCTAssertEqual(PixelKit.Options.withRetry, PixelKit.Options(retryOnFailure: true))
    }

    /// Defaults must be the non-intrusive ones: app version included, no retry. Naming is not
    /// represented in `Options` at all any more.
    func testOptionsDefaultsAreConservative() {
        let options = PixelKit.Options()
        XCTAssertTrue(options.includeAppVersionParameter)
        XCTAssertFalse(options.retryOnFailure)
        XCTAssertNil(options.headers)
        XCTAssertNil(options.additionalParameters)
        XCTAssertNil(options.allowedQueryReservedCharacters)
    }

    // MARK: - Sugar forwarding

    /// The defaulted `fire(_:frequency:options:)` sugar must reach the conformer's witness with the
    /// documented defaults applied. This guards the argument-label indirection between the protocol
    /// requirement and the entry point.
    func testSugarForwardsDefaultsToWitness() {
        let recorder = RecordingPixelFiring()

        recorder.fire(TestEventV2.testEvent)

        XCTAssertEqual(recorder.calls.count, 1)
        XCTAssertEqual(recorder.calls.first?.frequency, .standard)
        XCTAssertEqual(recorder.calls.first?.options, .default)
    }

    func testSugarForwardsExplicitArgumentsToWitness() {
        let recorder = RecordingPixelFiring()

        recorder.fire(TestEventV2.testEvent, options: .withoutAppVersion)
        recorder.fire(TestEventV2.testEvent, frequency: .daily)

        XCTAssertEqual(recorder.calls.count, 2)
        // Skipping the middle parameter must still default frequency.
        XCTAssertEqual(recorder.calls[0].frequency, .standard)
        XCTAssertEqual(recorder.calls[0].options, .withoutAppVersion)
        // Omitting options must still default it.
        XCTAssertEqual(recorder.calls[1].frequency, .daily)
        XCTAssertEqual(recorder.calls[1].options, .default)
    }

    // MARK: - Retry opt-in

    /// `PixelKit` instance whose retry queue is backed by an in-memory store, so the opt-in wiring can be
    /// asserted without touching the real Application Support file.
    private func makePixelKit(retryQueueStore: PixelRetryQueueStoring,
                              fireRequest: @escaping PixelKit.FireRequest) -> PixelKit {
        PixelKit(dryRun: false,
                 appVersion: "1.0.0",
                 source: nil,
                 session: UUID().uuidString,
                 channel: nil,
                 defaultHeaders: [:],
                 pixelCalendar: nil,
                 dateGenerator: Date.init,
                 defaults: userDefaults(),
                 retryQueueStore: retryQueueStore,
                 fireRequest: fireRequest)
    }

    /// Fails every send, recording the fully-resolved pixel names it was asked for, so assertions can
    /// compare what was queued against what was actually attempted without restating the platform prefix.
    private final class FailingFireRequestRecorder {
        private(set) var pixelNames = [String]()

        lazy var fireRequest: PixelKit.FireRequest = { [self] pixelName, _, _, _, _, completion in
            pixelNames.append(pixelName)
            completion(false, NSError(domain: "test", code: 1))
        }
    }

    /// Retry is off unless the pixel asks for it, so a plain failed fire leaves nothing behind.
    func testFailedFireIsNotQueuedByDefault() {
        let store = MockPixelRetryQueueStore()
        let recorder = FailingFireRequestRecorder()
        let pixelKit = makePixelKit(retryQueueStore: store, fireRequest: recorder.fireRequest)
        let fired = expectation(description: "fired")

        pixelKit.fire(event: TestEventV2.testEvent, frequency: .standard, options: .default) { _, _ in fired.fulfill() }

        wait(for: [fired], timeout: 1.0)
        XCTAssertEqual(recorder.pixelNames.count, 1)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testFailedFireIsQueuedWhenThePixelOptsIntoRetry() {
        let store = MockPixelRetryQueueStore()
        let recorder = FailingFireRequestRecorder()
        let pixelKit = makePixelKit(retryQueueStore: store, fireRequest: recorder.fireRequest)
        let fired = expectation(description: "fired")

        pixelKit.fire(event: TestEventV2.testEvent, frequency: .standard, options: .withRetry) { _, _ in fired.fulfill() }

        wait(for: [fired], timeout: 1.0)
        XCTAssertEqual(store.items.map(\.pixelName), recorder.pixelNames)
        XCTAssertEqual(store.items.count, 1)
    }

    /// The opt-in has to survive the per-`Frequency` handlers, not just the `.standard` one.
    func testFailedDailyFireIsQueuedWhenThePixelOptsIntoRetry() {
        let store = MockPixelRetryQueueStore()
        let recorder = FailingFireRequestRecorder()
        let pixelKit = makePixelKit(retryQueueStore: store, fireRequest: recorder.fireRequest)
        let fired = expectation(description: "fired")

        pixelKit.fire(event: TestEventV2.dailyEvent, frequency: .daily, options: .withRetry) { _, _ in fired.fulfill() }

        wait(for: [fired], timeout: 1.0)
        XCTAssertEqual(store.items.map(\.pixelName), recorder.pixelNames)
        XCTAssertEqual(store.items.first?.pixelName.hasSuffix("_daily"), true)
    }

    // MARK: - Legacy daily no-suffix frequency

    func testLegacyDailyNoSuffixAcceptsANameThatAlreadyEndsWithTheDailyMarker() {
        let userDefaults = UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!
        var firedNames: [String] = []
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                source: PixelKit.Source.iOS.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                defaults: userDefaults) { name, _, _, _, _, _ in
            firedNames.append(name)
        }

        // `m_netp_daily_active_d` is a real shipped name whose `_d` is part of the name, not a
        // frequency suffix PixelKit appended. `.legacyDailyNoSuffix` exists precisely for it.
        pixelKit.fire(LegacyDailyNoSuffixTestEvent(), frequency: .legacyDailyNoSuffix)

        XCTAssertEqual(firedNames, ["m_netp_daily_active_d_ios_phone"])
    }

    // MARK: - Legacy daily by-error frequency

    private struct LegacyDailyByErrorTestEvent: PixelKit.Event {
        let namePrefix: PixelKitNamePrefix = .none
        let name = "m_secure_vault_init_failed_error"
        let parameters: [String: String]? = nil
        let standardParameters: [PixelKitStandardParameter]? = nil
        /// Stored rather than reflected, so the test controls exactly which error is attached.
        let error: NSError?
    }

    private func makeLegacyDailyByErrorPixelKit(_ onFire: @escaping (String) -> Void) -> PixelKit {
        PixelKit(dryRun: false,
                 appVersion: "1.0.0",
                 source: PixelKit.Source.iOS.rawValue,
                 defaultHeaders: [:],
                 pixelCalendar: nil,
                 defaults: UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!) { name, _, _, _, _, _ in
            onFire(name)
        }
    }

    /// Legacy `DailyPixel.fire(pixel:error:)` folded the error into its once-per-day key, so a second,
    /// different failure of the same pixel still reported that day.
    func testLegacyDailyByErrorFiresOncePerDistinctError() {
        var firedNames: [String] = []
        let pixelKit = makeLegacyDailyByErrorPixelKit { firedNames.append($0) }

        let first = NSError(domain: "TestDomain", code: 1)
        let second = NSError(domain: "TestDomain", code: 2)
        let thirdInAnotherDomain = NSError(domain: "OtherDomain", code: 1)

        pixelKit.fire(LegacyDailyByErrorTestEvent(error: first), frequency: .legacyDailyByError)
        pixelKit.fire(LegacyDailyByErrorTestEvent(error: second), frequency: .legacyDailyByError)
        pixelKit.fire(LegacyDailyByErrorTestEvent(error: thirdInAnotherDomain), frequency: .legacyDailyByError)

        XCTAssertEqual(firedNames.count, 3, "Each distinct error should report once, as it did under DailyPixel")
        XCTAssertEqual(Set(firedNames), ["m_secure_vault_init_failed_error_ios_phone"],
                       "Only the throttling key carries the error - the wire name must stay unsuffixed")
    }

    func testLegacyDailyByErrorThrottlesRepeatsOfTheSameError() {
        var firedNames: [String] = []
        let pixelKit = makeLegacyDailyByErrorPixelKit { firedNames.append($0) }

        let error = NSError(domain: "TestDomain", code: 1)
        pixelKit.fire(LegacyDailyByErrorTestEvent(error: error), frequency: .legacyDailyByError)
        pixelKit.fire(LegacyDailyByErrorTestEvent(error: NSError(domain: "TestDomain", code: 1)),
                      frequency: .legacyDailyByError)

        XCTAssertEqual(firedNames.count, 1, "The same domain and code is the same throttling key, even across NSError instances")
    }

    /// Distinguishes this frequency from `.legacyDailyNoSuffix` only by the error, so with no error
    /// attached it has to throttle on the name alone.
    func testLegacyDailyByErrorWithoutAnErrorThrottlesOnTheNameAlone() {
        var firedNames: [String] = []
        let pixelKit = makeLegacyDailyByErrorPixelKit { firedNames.append($0) }

        pixelKit.fire(LegacyDailyByErrorTestEvent(error: nil), frequency: .legacyDailyByError)
        pixelKit.fire(LegacyDailyByErrorTestEvent(error: nil), frequency: .legacyDailyByError)

        XCTAssertEqual(firedNames, ["m_secure_vault_init_failed_error_ios_phone"])
    }

    /// The by-error keys share the `daily` map with the plain daily frequencies, which is where
    /// `LegacyPixelStateMigration` copies the legacy daily store's keys - composite ones included.
    func testLegacyDailyByErrorHonoursAMigratedLegacyThrottlingKey() {
        let userDefaults = UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!
        var firedNames: [String] = []
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                source: PixelKit.Source.iOS.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                defaults: userDefaults) { name, _, _, _, _, _ in
            firedNames.append(name)
        }

        // What legacy `DailyPixel` wrote for `NSError(domain: "TestDomain", code: 1)`: the error
        // parameter values (`d` then `e`) joined with `;`, appended to the name after a `:`.
        let migratedKey = "com.duckduckgo.network-protection.pixel.m_secure_vault_init_failed_error:TestDomain;1"
        userDefaults.set(["daily": Date()], forKey: migratedKey)

        pixelKit.fire(LegacyDailyByErrorTestEvent(error: NSError(domain: "TestDomain", code: 1)),
                      frequency: .legacyDailyByError)
        pixelKit.fire(LegacyDailyByErrorTestEvent(error: NSError(domain: "TestDomain", code: 2)),
                      frequency: .legacyDailyByError)

        XCTAssertEqual(firedNames.count, 1, "The migrated key should suppress its own error but not a different one")
    }

    // MARK: - Static async entry point

    func testStaticFireAsyncThrowsWhenPixelKitNotConfigured() async {
        PixelKit.tearDown()

        do {
            _ = try await PixelKit.fireAsync(TestEventV2.testEvent)
            XCTFail("Expected fireAsync to throw when PixelKit is not set up")
        } catch let error as PixelKitError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

/// Records what the `PixelFiring` sugar forwards to the single protocol requirement.
private final class RecordingPixelFiring: PixelFiring {
    struct Call {
        let event: PixelKit.Event
        let frequency: PixelKit.Frequency
        let options: PixelKit.Options
    }

    private(set) var calls = [Call]()

    func fire(event: PixelKit.Event,
              frequency: PixelKit.Frequency,
              options: PixelKit.Options,
              onComplete: @escaping PixelKit.CompletionBlock) {
        calls.append(Call(event: event, frequency: frequency, options: options))
        onComplete(true, nil)
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

/// See `testDottedNameFiresWhenTheEventAllowsIt`.
private struct DottedNameTestEvent: PixelKit.Event {
    let namePrefix: PixelKitNamePrefix = .none
    let name = "m_debug_app-did-finish-launching-time-0.5"
    let allowsDotInName = true
    let parameters: [String: String]? = nil
    let standardParameters: [PixelKitStandardParameter]? = nil
}
