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

    private struct TestEvent: PixelKit.Event {
        let namePrefix: PixelKitNamePrefix = .none
        let name = "m_test_event"
        let parameters: [String: String]? = nil
        let standardParameters: [PixelKitStandardParameter]? = nil
        let platformSuffixPolicy: PixelKitPlatformSuffixPolicy
    }

    /// An event that says nothing about naming, to pin down what a newly written pixel gets.
    private struct UnannotatedEvent: PixelKit.Event {
        let namePrefix: PixelKitNamePrefix = .none
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

// MARK: - README worked examples

/// Pins the worked-examples table in `README.md` under "How a pixel name is built".
final class PixelNameBuildingExamplesTests: XCTestCase {

    private struct Event: PixelKit.Event {
        let name: String
        let namePrefix: PixelKitNamePrefix
        let platformSuffixPolicy: PixelKitPlatformSuffixPolicy
        let parameters: [String: String]? = nil
        let standardParameters: [PixelKitStandardParameter]? = nil
    }

    private func firedNames(_ event: PixelKit.Event,
                            _ frequency: PixelKit.Frequency,
                            source: PixelKit.Source) -> [String] {
        let defaults = UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!
        var names: [String] = []
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                source: source.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                defaults: defaults) { name, _, _, _, _, _ in
            names.append(name)
        }
        pixelKit.fire(event, frequency: frequency)
        return names
    }

    func testCustomPrefixStandardPolicyDailyAndCount() {
        let event = Event(name: "example", namePrefix: .custom("m_"), platformSuffixPolicy: .standard)

        XCTAssertEqual(firedNames(event, .dailyAndCount, source: .iOS),
                       ["m_example_daily_ios_phone", "m_example_count_ios_phone"])
    }

    func testNoPrefixStandardPolicyDaily() {
        let event = Event(name: "m_example", namePrefix: .none, platformSuffixPolicy: .standard)

        XCTAssertEqual(firedNames(event, .daily, source: .iOS), ["m_example_daily_ios_phone"])
    }

    func testNoPrefixOmittedPolicyDaily() {
        let event = Event(name: "m_example", namePrefix: .none, platformSuffixPolicy: .legacyOmitted)

        XCTAssertEqual(firedNames(event, .daily, source: .iOS), ["m_example_daily"])
    }

    /// `.platformDefault` is a compile-time branch, so only the current platform's row is checkable.
    func testPlatformDefaultPrefix() {
        let event = Event(name: "example", namePrefix: .platformDefault, platformSuffixPolicy: .standard)

#if os(macOS)
        XCTAssertEqual(firedNames(event, .standard, source: .macDMG), ["m_mac_example"])
#else
        XCTAssertEqual(firedNames(event, .standard, source: .iOS), ["example_ios_phone"])
#endif
    }

    /// The platform-marker grid in "Step 4 — platform marker".
    func testPlatformMarkerGrid() {
        let expected: [PixelKitPlatformSuffixPolicy: [PixelKit.Source: String]] = [
            .standard: [.macDMG: "m_example_count",
                        .iOS: "m_example_count_ios_phone",
                        .iPadOS: "m_example_count_ios_tablet"],
            .legacyBeforeFrequencySuffix: [.macDMG: "m_example_count",
                                           .iOS: "m_example_ios_phone_count",
                                           .iPadOS: "m_example_ios_tablet_count"],
            .legacyOmitted: [.macDMG: "m_example_count",
                             .iOS: "m_example_count",
                             .iPadOS: "m_example_count"]
        ]

        for (policy, bySource) in expected {
            let event = Event(name: "m_example", namePrefix: .none, platformSuffixPolicy: policy)
            for (source, countName) in bySource {
                let names = firedNames(event, .dailyAndCount, source: source)

                XCTAssertEqual(names.count, 2, "\(policy) / \(source)")
                XCTAssertEqual(names.last, countName, "\(policy) / \(source)")
            }
        }
    }

    /// The frequency-suffix table in the same section.
    func testFrequencySuffixes() {
        let event = Event(name: "m_example", namePrefix: .none, platformSuffixPolicy: .legacyOmitted)
        let cases: [(PixelKit.Frequency, [String])] = [
            (.standard, ["m_example"]),
            (.daily, ["m_example_daily"]),
            (.monthly, ["m_example_monthly"]),
            (.dailyAndCount, ["m_example_daily", "m_example_count"]),
            (.dailyAndStandard, ["m_example_daily", "m_example"]),
            (.legacyDaily, ["m_example_d"]),
            (.legacyDailyAndCount, ["m_example_d", "m_example_c"]),
            (.legacyDailyNoSuffix, ["m_example"]),
            (.sample(percentage: 100), ["m_example_sample100"])
        ]

        for (frequency, expected) in cases {
            XCTAssertEqual(firedNames(event, frequency, source: .iOS), expected, "\(frequency)")
        }
    }
}
