//
//  OSDistributionPixelTests.swift
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
import Common
import PersistenceTestingUtils
@testable import PixelKit

final class OSDistributionPixelTests: XCTestCase {

    // MARK: - Name composition (must match the os_distribution pixel definitions)

    func testNameComposition() {
        XCTAssertEqual(
            OSDistributionPixel(metric: .client, osMajorVersion: 15, platform: .iOS, formFactor: "phone").name,
            "os_distribution_client_major_version_15_ios_phone")

        XCTAssertEqual(
            OSDistributionPixel(metric: .searches, osMajorVersion: 18, platform: .iOS, formFactor: "tablet").name,
            "os_distribution_searches_major_version_18_ios_tablet")

        XCTAssertEqual(
            OSDistributionPixel(metric: .activeSubscriptions, osMajorVersion: 26, platform: .macOS, formFactor: "desktop").name,
            "os_distribution_active_subscriptions_major_version_26_macos_desktop")
    }

    // MARK: - Firing

    /// Firing appends the `_monthly` suffix (from `.monthly` frequency), sends `petal=randomize`,
    /// and suppresses the default `appVersion` and `pixelSource` parameters, even when a source is configured.
    func testFiringAppendsMonthlySuffixSendsPetalAndSuppressesDefaultParameters() {
        var firedName: String?
        var firedParameters: [String: String]?
        let fired = expectation(description: "pixel fired")

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.2.3",
                                source: "test-source",
                                defaultHeaders: [:],
                                defaults: InMemoryThrowingKeyValueStore()) { name, _, parameters, _, _, onComplete in
            firedName = name
            firedParameters = parameters
            onComplete(true, nil)
            fired.fulfill()
        }

        pixelKit.fireOSDistributionPixel(
            OSDistributionPixel(metric: .client, osMajorVersion: 15, platform: .macOS, formFactor: "desktop")
        )

        wait(for: [fired], timeout: 1.0)

        XCTAssertEqual(firedName, "os_distribution_client_major_version_15_macos_desktop_monthly")
        XCTAssertEqual(firedParameters?["petal"], "randomize", "petal=randomize must be sent (PETAL pipeline tag)")
        XCTAssertNil(firedParameters?[PixelKit.Parameters.appVersion], "appVersion must be suppressed")
        XCTAssertNil(firedParameters?[PixelKit.Parameters.pixelSource], "pixelSource must not be added")
    }

    /// A second fire within the same calendar month is suppressed for monthly-frequency metrics
    /// (`.client` / `.activeSubscriptions`). (`.searches` is per-event — see `testSearchesFiresEveryTime`.)
    func testSecondFireInSameMonthIsSuppressed() {
        var fireCount = 0
        let defaults = InMemoryThrowingKeyValueStore()

        let makePixelKit: () -> PixelKit = {
            PixelKit(dryRun: false,
                     appVersion: "1.2.3",
                     defaultHeaders: [:],
                     defaults: defaults) { _, _, _, _, _, onComplete in
                fireCount += 1
                onComplete(true, nil)
            }
        }

        let event = OSDistributionPixel(metric: .client, osMajorVersion: 15, platform: .macOS, formFactor: "desktop")
        makePixelKit().fireOSDistributionPixel(event)
        makePixelKit().fireOSDistributionPixel(event)

        XCTAssertEqual(fireCount, 1, "Monthly pixel should only fire once per calendar month")
    }

    /// `.searches` is a per-event traffic pixel (`.standard` frequency): it fires every time, with no
    /// monthly dedup — unlike the monthly `.client` / `.activeSubscriptions`.
    func testSearchesFiresEveryTime() {
        var firedNames: [String] = []
        let defaults = InMemoryThrowingKeyValueStore()

        let makePixelKit: () -> PixelKit = {
            PixelKit(dryRun: false,
                     appVersion: "1.2.3",
                     defaultHeaders: [:],
                     defaults: defaults) { name, _, _, _, _, onComplete in
                firedNames.append(name)
                onComplete(true, nil)
            }
        }

        let event = OSDistributionPixel(metric: .searches, osMajorVersion: 15, platform: .macOS, formFactor: "desktop")
        makePixelKit().fireOSDistributionPixel(event)
        makePixelKit().fireOSDistributionPixel(event)

        XCTAssertEqual(firedNames, [
            "os_distribution_searches_major_version_15_macos_desktop",
            "os_distribution_searches_major_version_15_macos_desktop"
        ], "Searches is per-event: fires every time")
    }

    // MARK: - Metric-based firing

    /// `fireOSDistributionPixel(metric:)` builds the name from the given platform/form factor
    /// (defaulting to the current device). Covers every expected OS-name / form-factor combination.
    func testFiringByMetricCoversAllPlatformAndFormFactorCombinations() {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let combinations: [(platform: DevicePlatform, formFactor: String, expectedSegment: String)] = [
            (.iOS, "phone", "ios_phone"),
            (.iOS, "tablet", "ios_tablet"),
            (.macOS, "desktop", "macos_desktop"),
        ]

        for combination in combinations {
            var firedName: String?
            let pixelKit = PixelKit(dryRun: false,
                                    appVersion: "1.2.3",
                                    defaultHeaders: [:],
                                    defaults: InMemoryThrowingKeyValueStore()) { name, _, _, _, _, onComplete in
                firedName = name
                onComplete(true, nil)
            }

            pixelKit.fireOSDistributionPixel(metric: .client,
                                             platform: combination.platform,
                                             formFactor: combination.formFactor)

            XCTAssertEqual(firedName,
                           "os_distribution_client_major_version_\(major)_\(combination.expectedSegment)_monthly")
        }
    }
}
