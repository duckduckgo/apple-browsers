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
@testable import PixelKit

final class OSDistributionPixelTests: XCTestCase {

    private func userDefaults() -> UserDefaults {
        UserDefaults(suiteName: "testing_\(UUID().uuidString)")!
    }

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

    /// Firing appends the `_monthly` suffix (from `.monthly` frequency) and suppresses the default
    /// `appVersion` and `pixelSource` parameters, even when a source is configured.
    func testFiringAppendsMonthlySuffixAndSuppressesDefaultParameters() {
        var firedName: String?
        var firedParameters: [String: String]?
        let fired = expectation(description: "pixel fired")

        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.2.3",
                                source: "test-source",
                                defaultHeaders: [:],
                                defaults: userDefaults()) { name, _, parameters, _, _, onComplete in
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
        XCTAssertNil(firedParameters?[PixelKit.Parameters.appVersion], "appVersion must be suppressed")
        XCTAssertNil(firedParameters?[PixelKit.Parameters.pixelSource], "pixelSource must not be added")
    }

    /// A second fire within the same calendar month is suppressed (monthly frequency gating).
    func testSecondFireInSameMonthIsSuppressed() {
        var fireCount = 0
        let defaults = userDefaults()

        let makePixelKit: () -> PixelKit = {
            PixelKit(dryRun: false,
                     appVersion: "1.2.3",
                     defaultHeaders: [:],
                     defaults: defaults) { _, _, _, _, _, onComplete in
                fireCount += 1
                onComplete(true, nil)
            }
        }

        let event = OSDistributionPixel(metric: .searches, osMajorVersion: 15, platform: .macOS, formFactor: "desktop")
        makePixelKit().fireOSDistributionPixel(event)
        makePixelKit().fireOSDistributionPixel(event)

        XCTAssertEqual(fireCount, 1, "Monthly pixel should only fire once per calendar month")
    }

    // MARK: - Metric-based firing

    /// `fireOSDistributionPixel(metric:)` resolves platform and form factor for the running device.
    /// These tests run on macOS, so it yields the `macos_desktop` segment.
    func testFiringByMetricUsesCurrentDevicePlatformAndFormFactor() {
        var firedName: String?
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.2.3",
                                defaultHeaders: [:],
                                defaults: userDefaults()) { name, _, _, _, _, onComplete in
            firedName = name
            onComplete(true, nil)
        }

        pixelKit.fireOSDistributionPixel(metric: .client)

        XCTAssertEqual(firedName?.hasPrefix("os_distribution_client_major_version_"), true)
        XCTAssertEqual(firedName?.hasSuffix("_macos_desktop_monthly"), true)
    }
}
