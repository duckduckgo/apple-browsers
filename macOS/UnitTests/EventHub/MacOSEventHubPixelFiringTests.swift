//
//  MacOSEventHubPixelFiringTests.swift
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

@testable import DuckDuckGo_Privacy_Browser

/// Pins the exact pixel name EventHub telemetry goes out under. PixelKit rewrites macOS pixel names
/// after the fact (prepending `m_mac_` unless told not to), so asserting on the name PixelKit actually
/// requests — not the name we pass in — is what keeps these in sync with `event_hub.json5`.
final class MacOSEventHubPixelFiringTests: XCTestCase {

    private static let suiteName = "MacOSEventHubPixelFiringTests"

    private var firedNames: [String] = []
    private var firedParameters: [[String: String]] = []

    override func setUp() {
        super.setUp()
        firedNames = []
        firedParameters = []
        // Cleared per test: the debug-event pixels fire `.dailyAndCount`, and PixelKit records the last
        // daily fire in these defaults — a suite surviving from an earlier run would suppress the
        // `_daily` half and make the assertions below depend on when they last ran.
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        // `dryRun: false` — PixelKit deliberately skips `fireRequest` entirely when dry-running.
        PixelKit.setUp(dryRun: false,
                       appVersion: "1.0.0",
                       session: "test",
                       defaultHeaders: [:],
                       defaults: defaults) { name, _, parameters, _, _, _ in
            self.firedNames.append(name)
            self.firedParameters.append(parameters)
        }
    }

    override func tearDown() {
        PixelKit.tearDown()
        firedNames = []
        firedParameters = []
        super.tearDown()
    }

    func testFiredNameCarriesMacOSSuffixAndNoMacPrefix() {
        MacOSEventHubPixelFiring().enqueueFirePixel(named: "webTelemetry_youtube_staticAd_day", parameters: [:])

        XCTAssertEqual(firedNames, ["webTelemetry_youtube_staticAd_day_macos"])
    }

    func testParametersArePassedThrough() {
        MacOSEventHubPixelFiring().enqueueFirePixel(named: "some_telemetry",
                                                    parameters: ["count": "1+", "attributionPeriod": "1769126400"])

        XCTAssertEqual(firedParameters.first?["count"], "1+")
        XCTAssertEqual(firedParameters.first?["attributionPeriod"], "1769126400")
    }

    // MARK: - Debug events

    func testDebugEventFiresDailyAndCountUnderTheMacOSName() {
        MacOSEventHubDebugEventMapping().fire(.pixelStatePersistenceFailed(operation: .write))

        XCTAssertEqual(firedNames, ["eventhub_pixel_state_persistence_failed_macos_daily",
                                    "eventhub_pixel_state_persistence_failed_macos_count"])
    }

    func testDebugEventCarriesTheFailingOperation() {
        MacOSEventHubDebugEventMapping().fire(.pixelStatePersistenceFailed(operation: .decode))

        XCTAssertEqual(firedParameters.first?["operation"], "decode")
    }

    func testDebugEventCarriesTheUnderlyingError() {
        let error = NSError(domain: "TestDomain", code: 42)

        MacOSEventHubDebugEventMapping().fire(.pixelStatePersistenceFailed(operation: .read), error: error)

        XCTAssertEqual(firedParameters.first?["d"], "TestDomain")
        XCTAssertEqual(firedParameters.first?["e"], "42")
    }

    func testConsentStripFailedFiresUnderItsOwnName() {
        MacOSEventHubDebugEventMapping().fire(.consentStripFailed)

        XCTAssertEqual(firedNames, ["eventhub_consent_strip_failed_macos_daily",
                                    "eventhub_consent_strip_failed_macos_count"])
    }
}
