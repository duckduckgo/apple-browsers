//
//  IOSEventHubPixelFiringTests.swift
//  DuckDuckGo
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

import Common
import EventHub
import PixelKit
import XCTest

@testable import DuckDuckGo

/// Pins the exact pixel name EventHub telemetry goes out under. PixelKit rewrites names after the fact —
/// which marker it appends, and whether it prepends the legacy `m_`, depends on how the event declares
/// itself — so asserting on the name PixelKit actually requests, not the name we pass in, is what keeps
/// these in sync with `event_hub.json5`.
final class IOSEventHubPixelFiringTests: XCTestCase {

    private var firedNames: [String] = []
    private var firedParameters: [[String: String]] = []

    override func setUp() {
        super.setUp()
        firedNames = []
        firedParameters = []
    }

    override func tearDown() {
        PixelKit.tearDown()
        firedNames = []
        firedParameters = []
        super.tearDown()
    }

    func testFiredNameCarriesThePhoneSuffixAndNoLegacyPrefix() {
        setUpPixelKit(source: .iOS)

        IOSEventHubPixelFiring().enqueueFirePixel(named: "webTelemetry_youtube_staticAd_day", parameters: [:])

        XCTAssertEqual(firedNames, ["webTelemetry_youtube_staticAd_day_ios_phone"])
    }

    func testFiredNameCarriesTheTabletSuffixOnIPad() {
        setUpPixelKit(source: .iPadOS)

        IOSEventHubPixelFiring().enqueueFirePixel(named: "webTelemetry_youtube_staticAd_day", parameters: [:])

        XCTAssertEqual(firedNames, ["webTelemetry_youtube_staticAd_day_ios_tablet"])
    }

    func testParametersArePassedThrough() {
        setUpPixelKit(source: .iOS)

        IOSEventHubPixelFiring().enqueueFirePixel(named: "some_telemetry",
                                                 parameters: ["count": "1+", "attributionPeriod": "1769126400"])

        XCTAssertEqual(firedParameters.first?["count"], "1+")
        XCTAssertEqual(firedParameters.first?["attributionPeriod"], "1769126400")
    }

    // MARK: - Debug events

    func testDebugEventFiresDailyAndCountWithThePhoneSuffix() {
        setUpPixelKit(source: .iOS)

        IOSEventHubDebugEventMapping().fire(.pixelStatePersistenceFailed(operation: .write))

        XCTAssertEqual(firedNames, ["eventhub_pixel_state_persistence_failed_ios_phone_daily",
                                    "eventhub_pixel_state_persistence_failed_ios_phone_count"])
    }

    func testDebugEventCarriesTheTabletSuffixOnIPad() {
        setUpPixelKit(source: .iPadOS)

        IOSEventHubDebugEventMapping().fire(.consentStripFailed)

        XCTAssertEqual(firedNames, ["eventhub_consent_strip_failed_ios_tablet_daily",
                                    "eventhub_consent_strip_failed_ios_tablet_count"])
    }

    func testDebugEventCarriesTheFailingOperation() {
        setUpPixelKit(source: .iOS)

        IOSEventHubDebugEventMapping().fire(.pixelStatePersistenceFailed(operation: .decode))

        XCTAssertEqual(firedParameters.first?["operation"], "decode")
    }

    func testDebugEventCarriesTheUnderlyingError() {
        setUpPixelKit(source: .iOS)
        let error = NSError(domain: "TestDomain", code: 42)

        IOSEventHubDebugEventMapping().fire(.pixelStatePersistenceFailed(operation: .read), error: error)

        XCTAssertEqual(firedParameters.first?["d"], "TestDomain")
        XCTAssertEqual(firedParameters.first?["e"], "42")
    }

    // MARK: - Helpers

    /// `dryRun: false` — PixelKit deliberately skips `fireRequest` entirely when dry-running. `source` is
    /// what `platformSuffix` reads, so it has to be set explicitly rather than inherited from the device.
    /// The defaults suite is cleared first: the debug-event pixels fire `.dailyAndCount`, and PixelKit
    /// records the last daily fire there — a suite surviving from an earlier run would suppress the
    /// `_daily` half and make these assertions depend on when they last ran.
    private func setUpPixelKit(source: PixelKit.Source) {
        let suiteName = "\(type(of: self))"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        PixelKit.setUp(dryRun: false,
                       appVersion: "1.0.0",
                       source: source.rawValue,
                       session: "test",
                       defaultHeaders: [:],
                       defaults: defaults) { name, _, parameters, _, _, _ in
            self.firedNames.append(name)
            self.firedParameters.append(parameters)
        }
    }
}
