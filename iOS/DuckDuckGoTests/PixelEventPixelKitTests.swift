//
//  PixelEventPixelKitTests.swift
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

import XCTest
import PixelKit
@testable import Core

/// Pins the naming contract the whole migration rests on: a `Pixel.Event` fired through PixelKit
/// must produce the byte-identical name legacy `Pixel` produced.
///
/// Legacy `Pixel` built `<name><frequencySuffix>` and `URL.makePixelURL` then appended
/// `_ios_<formFactor>`. These tests assert PixelKit reproduces that for every frequency the
/// migration assigns.
final class PixelEventPixelKitTests: XCTestCase {

    /// `.appLaunch` is the reference case: a short legacy name with no interpolation, so the
    /// expected strings below are readable.
    private let event = Pixel.Event.appLaunch
    // Named `pixelName`, not `name`: XCTestCase already declares an inherited `name` property,
    // and a stored property here would conflict with it.
    private let pixelName = "ml"

    private func firedNames(for event: PixelKit.Event,
                            frequency: PixelKit.Frequency,
                            source: PixelKit.Source = .iOS) -> [String] {
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
        pixelKit.fire(event, frequency: frequency)
        return names
    }

    private func firedParameters(for event: PixelKit.Event) -> [String: String] {
        let defaults = UserDefaults(suiteName: "\(#function)-\(UUID().uuidString)")!
        var parameters: [String: String] = [:]
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                source: PixelKit.Source.iOS.rawValue,
                                defaultHeaders: [:],
                                pixelCalendar: nil,
                                defaults: defaults) { _, _, firedParameters, _, _, _ in
            parameters = firedParameters
        }
        pixelKit.fire(event)
        return parameters
    }

    // MARK: - The naming contract

    func testStandardFrequencyAppendsOnlyThePlatformMarker() {
        XCTAssertEqual(firedNames(for: event, frequency: .standard), ["\(pixelName)_ios_phone"])
    }

    func testTabletsAreMarkedSeparately() {
        XCTAssertEqual(firedNames(for: event, frequency: .standard, source: .iPadOS),
                       ["\(pixelName)_ios_tablet"])
    }

    func testLegacyDailyNoSuffixMatchesDailyPixelFire() {
        // `DailyPixel.fire` appended no suffix at all.
        XCTAssertEqual(firedNames(for: event, frequency: .legacyDailyNoSuffix), ["\(pixelName)_ios_phone"])
    }

    func testDailyAndCountMatchesTheDefaultDailyPixelSuffixes() {
        // DailyPixel.Constant.dailyPixelSuffixes == ("_daily", "_count")
        XCTAssertEqual(firedNames(for: event, frequency: .dailyAndCount),
                       ["\(pixelName)_daily_ios_phone", "\(pixelName)_count_ios_phone"])
    }

    func testLegacyDailyAndCountMatchesTheLegacyDailyPixelSuffixes() {
        // DailyPixel.Constant.legacyDailyPixelSuffixes == ("_d", "_c")
        XCTAssertEqual(firedNames(for: event, frequency: .legacyDailyAndCount),
                       ["\(pixelName)_d_ios_phone", "\(pixelName)_c_ios_phone"])
    }

    func testDailyAndStandardMatchesTheDailyAndStandardSuffixes() {
        // DailyPixel.Constant.dailyAndStandardSuffixes == ("_daily", "")
        XCTAssertEqual(firedNames(for: event, frequency: .dailyAndStandard),
                       ["\(pixelName)_daily_ios_phone", "\(pixelName)_ios_phone"])
    }

    func testLegacyInitialAppendsOnlyThePlatformMarker() {
        // The frequency `_unique`-suffixed pixels use, because PixelKit's `.uniqueByName`
        // hard-requires a `_u` suffix and refuses to fire without it.
        XCTAssertEqual(firedNames(for: event, frequency: .legacyInitial), ["\(pixelName)_ios_phone"])
    }

    func testUniqueByNameAppendsOnlyThePlatformMarker() {
        let unique = Pixel.Event.networkProtectionNewUser  // "m_netp_daily_active_u"
        XCTAssertEqual(firedNames(for: unique, frequency: .uniqueByName),
                       ["m_netp_daily_active_u_ios_phone"])
    }

    // MARK: - Wrappers

    func testWithoutPlatformSuffixOmitsTheMarker() {
        // Reproduces legacy `Pixel.fire(pixel:forDeviceType: nil)`.
        XCTAssertEqual(firedNames(for: event.withoutPlatformSuffix, frequency: .standard), [pixelName])
    }

    func testWithErrorAttachesTheErrorParameters() {
        let error = NSError(domain: "TestDomain", code: 42)
        let parameters = firedParameters(for: event.withError(error))

        XCTAssertEqual(parameters["e"], "42")
        XCTAssertEqual(parameters["d"], "TestDomain")
    }

    func testWithErrorPreservesTheName() {
        let error = NSError(domain: "TestDomain", code: 42)
        XCTAssertEqual(firedNames(for: event.withError(error), frequency: .dailyAndCount),
                       ["\(pixelName)_daily_ios_phone", "\(pixelName)_count_ios_phone"])
    }

    func testWithNilErrorAttachesNothing() {
        let parameters = firedParameters(for: event.withError(nil))

        XCTAssertNil(parameters["e"])
        XCTAssertNil(parameters["d"])
    }

    func testLegacyNamedPixelUsesTheGivenNameVerbatim() {
        // Reproduces legacy `Pixel.fire(pixelNamed:)`.
        XCTAssertEqual(firedNames(for: LegacyNamedPixel(name: "m_raw_name"), frequency: .standard),
                       ["m_raw_name_ios_phone"])
    }

    // MARK: - An event carries no parameters of its own

    func testAnEventContributesNoParametersOfItsOwn() {
        // Legacy `Pixel.Event` had no parameters; they always came from the call site. Anything
        // else here would mean the reflection-based `error` default had found an associated value.
        XCTAssertNil(event.parameters)
        XCTAssertNil(event.error)
    }
}
