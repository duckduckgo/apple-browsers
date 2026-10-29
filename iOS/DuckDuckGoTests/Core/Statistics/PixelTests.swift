//
//  PixelTests.swift
//  UnitTests
//
//  Copyright © 2018 DuckDuckGo. All rights reserved.
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
@testable import Core
import PixelKit

/// Pins PixelKit's default naming on iOS to what the legacy `Pixel` produced, so a pixel written
/// against PixelKit lands on the wire with the same shape as the pixels around it.
final class PixelKitLegacyNamingParityTests: XCTestCase {

    /// The legacy wire name: `Pixel.fire(pixelNamed:)` appended `_ios_<formFactor>` while building the
    /// URL, after `DailyPixel` had already appended the frequency suffix to the name.
    private func legacyWireName(_ name: String, formFactor: String) -> String {
        URL.makePixelURL(pixelName: name, formFactor: formFactor, includeATB: false)
            .lastPathComponent
    }

    /// An event with no naming customisation at all.
    private struct DefaultEvent: PixelKit.Event {
        let name: String
        let parameters: [String: String]? = nil
        let standardParameters: [PixelKitStandardParameter]? = nil
    }

    private func pixelKitNames(_ name: String,
                               frequency: PixelKit.Frequency,
                               source: PixelKit.Source) -> [String] {
        let defaults = UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!
        var names: [String] = []
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                source: source.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                defaults: defaults) { firedName, _, _, _, _, _ in
            names.append(firedName)
        }
        pixelKit.fire(DefaultEvent(name: name), frequency: frequency)
        return names
    }

    func testDefaultStandardPixelMatchesLegacy() {
        XCTAssertEqual(pixelKitNames("m_example", frequency: .standard, source: .iOS),
                       [legacyWireName("m_example", formFactor: "phone")])
    }

    func testDefaultDailyAndCountPixelMatchesLegacy() {
        XCTAssertEqual(pixelKitNames("m_example", frequency: .dailyAndCount, source: .iOS),
                       [legacyWireName("m_example_daily", formFactor: "phone"),
                        legacyWireName("m_example_count", formFactor: "phone")])
    }

    func testDefaultLegacyDailyAndCountPixelMatchesLegacy() {
        XCTAssertEqual(pixelKitNames("m_example", frequency: .legacyDailyAndCount, source: .iOS),
                       [legacyWireName("m_example_d", formFactor: "phone"),
                        legacyWireName("m_example_c", formFactor: "phone")])
    }

    func testDefaultPixelMatchesLegacyOnTablet() {
        XCTAssertEqual(pixelKitNames("m_example", frequency: .dailyAndCount, source: .iPadOS),
                       [legacyWireName("m_example_daily", formFactor: "tablet"),
                        legacyWireName("m_example_count", formFactor: "tablet")])
    }

    /// The legacy system added no prefix of its own; names carry their own `m_`. PixelKit's default
    /// must not add one either.
    func testDefaultPixelAddsNoPrefixOfItsOwn() {
        let names = pixelKitNames("mf_bp", frequency: .standard, source: .iOS)

        XCTAssertEqual(names, ["mf_bp_ios_phone"])
        XCTAssertEqual(names, [legacyWireName("mf_bp", formFactor: "phone")])
    }
}
