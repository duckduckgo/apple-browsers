//
//  PixelKitPlatformSuffixPolicyTests.swift
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
@testable import PixelKit

/// Covers where the `_ios_phone` / `_ios_tablet` marker lands relative to the frequency suffix.
///
/// Every event here conforms to `PixelKitEventWithCustomPrefix` with an empty prefix so the tests
/// bypass PixelKit's platform-conditional prefix correction and run identically whichever platform
/// the test bundle is built for. The marker itself is driven by `source`, not by `#if os(...)`, so
/// iOS naming is fully reproducible from a macOS test run.
final class PixelKitPlatformSuffixPolicyTests: XCTestCase {

    private struct TestEvent: PixelKit.Event, PixelKitEventWithCustomPrefix {
        let namePrefix = ""
        let name = "m_test_event"
        let parameters: [String: String]? = nil
        let standardParameters: [PixelKitStandardParameter]? = nil
        let platformSuffixPolicy: PixelKitPlatformSuffixPolicy
    }

    /// An event that says nothing about naming, to pin down what a newly written pixel gets.
    private struct UnannotatedEvent: PixelKit.Event, PixelKitEventWithCustomPrefix {
        let namePrefix = ""
        let name = "m_test_event"
        let parameters: [String: String]? = nil
        let standardParameters: [PixelKitStandardParameter]? = nil
    }

    private func firedNames(for event: PixelKit.Event,
                            frequency: PixelKit.Frequency,
                            source: PixelKit.Source) -> [String] {
        let userDefaults = UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!
        var names: [String] = []
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                source: source.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                defaults: userDefaults) { firedPixelName, _, _, _, _, _ in
            names.append(firedPixelName)
        }
        pixelKit.fire(event, frequency: frequency)
        return names
    }

    // MARK: - The correct convention

    func testStandardPolicyPlacesTheMarkerAfterTheFrequencySuffix() {
        let names = firedNames(for: TestEvent(platformSuffixPolicy: .standard),
                               frequency: .dailyAndCount,
                               source: .iOS)

        XCTAssertEqual(names, ["m_test_event_daily_ios_phone", "m_test_event_count_ios_phone"])
    }

    func testStandardPolicyMarksTabletsSeparately() {
        let names = firedNames(for: TestEvent(platformSuffixPolicy: .standard),
                               frequency: .dailyAndCount,
                               source: .iPadOS)

        XCTAssertEqual(names, ["m_test_event_daily_ios_tablet", "m_test_event_count_ios_tablet"])
    }

    func testStandardPolicyMarksAPixelThatHasNoFrequencySuffix() {
        let names = firedNames(for: TestEvent(platformSuffixPolicy: .standard),
                               frequency: .standard,
                               source: .iOS)

        XCTAssertEqual(names, ["m_test_event_ios_phone"])
    }

    /// The point of the whole change: an author who writes a new pixel and never hears about
    /// `PixelKitPlatformSuffixPolicy` still gets a name that says which platform it came from.
    func testAnEventThatDeclaresNoPolicyGetsTheStandardOne() {
        XCTAssertEqual(UnannotatedEvent().platformSuffixPolicy, .standard)

        let names = firedNames(for: UnannotatedEvent(), frequency: .dailyAndCount, source: .iOS)

        XCTAssertEqual(names, ["m_test_event_daily_ios_phone", "m_test_event_count_ios_phone"])
    }

    // MARK: - Frozen legacy shapes

    func testLegacyBeforeFrequencySuffixPolicyKeepsTheMarkerAheadOfTheFrequencySuffix() {
        let names = firedNames(for: TestEvent(platformSuffixPolicy: .legacyBeforeFrequencySuffix),
                               frequency: .dailyAndCount,
                               source: .iOS)

        XCTAssertEqual(names, ["m_test_event_ios_phone_daily", "m_test_event_ios_phone_count"])
    }

    func testLegacyOmittedPolicySendsNoMarkerAtAll() {
        let names = firedNames(for: TestEvent(platformSuffixPolicy: .legacyOmitted),
                               frequency: .dailyAndCount,
                               source: .iOS)

        XCTAssertEqual(names, ["m_test_event_daily", "m_test_event_count"])
    }

    func testLegacyPoliciesAreUnchangedForTheLegacySuffixes() {
        let legacy = firedNames(for: TestEvent(platformSuffixPolicy: .legacyBeforeFrequencySuffix),
                                frequency: .legacyDailyAndCount,
                                source: .iOS)
        XCTAssertEqual(legacy, ["m_test_event_ios_phone_d", "m_test_event_ios_phone_c"])

        let standard = firedNames(for: TestEvent(platformSuffixPolicy: .standard),
                                  frequency: .legacyDailyAndCount,
                                  source: .iOS)
        XCTAssertEqual(standard, ["m_test_event_d_ios_phone", "m_test_event_c_ios_phone"])
    }

    // MARK: - macOS is unaffected

    func testEveryPolicyProducesTheSameNameOnMacOS() {
        for policy in [PixelKitPlatformSuffixPolicy.standard, .legacyBeforeFrequencySuffix, .legacyOmitted] {
            let names = firedNames(for: TestEvent(platformSuffixPolicy: policy),
                                   frequency: .dailyAndCount,
                                   source: .macDMG)

            XCTAssertEqual(names, ["m_test_event_daily", "m_test_event_count"], "policy: \(policy)")
        }
    }

    // MARK: - Throttling

    /// The marker must not reach the throttling key, or the same daily pixel would be allowed to
    /// fire once per form factor.
    func testDailyThrottlingIgnoresTheMarker() {
        let userDefaults = UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!
        var names: [String] = []
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                source: PixelKit.Source.iOS.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                defaults: userDefaults) { firedPixelName, _, _, _, _, _ in
            names.append(firedPixelName)
        }

        let event = TestEvent(platformSuffixPolicy: .standard)
        pixelKit.fire(event, frequency: .daily)
        pixelKit.fire(event, frequency: .daily)

        XCTAssertEqual(names, ["m_test_event_daily_ios_phone"])
    }
}

// MARK: - The one deliberate rename

/// `WideEventFailureEvent` is the single pixel family this change fixes rather than freezes, so
/// pin its resulting names.
final class WideEventFailureEventNamingTests: XCTestCase {

    private func firedNames(source: PixelKit.Source) -> [String] {
        let userDefaults = UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!
        var names: [String] = []
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                source: source.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                defaults: userDefaults) { firedPixelName, _, _, _, _, _ in
            names.append(firedPixelName)
        }
        pixelKit.fire(WideEventFailureEvent.saveFailed(pixelName: "subscription_purchase",
                                                       error: NSError(domain: "test", code: 1)),
                      frequency: .dailyAndCount)
        return names
    }

    /// `WideEventFailureEvent.namePrefix` is a compile-time `#if`, so a macOS test bundle always
    /// sees `m_mac_` regardless of the `source` passed in. Only the suffix half is reproducible
    /// across platforms, and the suffix half is what this change alters.
#if os(macOS)
    private let prefix = "m_mac_"
#else
    private let prefix = "m_"
#endif

    func testFailureNamesMatchTheDeclaredSuffixOrderOnIOS() {
        XCTAssertEqual(firedNames(source: .iOS),
                       ["\(prefix)wide_pixel_save_failed_daily_ios_phone",
                        "\(prefix)wide_pixel_save_failed_count_ios_phone"])
    }

    func testFailureNamesAreUnchangedOnMacOS() {
        XCTAssertEqual(firedNames(source: .macDMG),
                       ["\(prefix)wide_pixel_save_failed_daily",
                        "\(prefix)wide_pixel_save_failed_count"])
    }
}
