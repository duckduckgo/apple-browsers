//
//  MacOSWebExtensionPixelFiringTests.swift
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
@_spi(Testing) import PixelKit
import WebExtensions
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
final class MacOSWebExtensionPixelFiringTests: XCTestCase {
    func testUpdateCheckOutcomesUseBoundedParametersAndDailyAndCount() throws {
        let identifier = ChromeWebStoreID.bitwarden.rawValue
        for outcome in WebExtensionUpdateCheckOutcome.allCases {
            let pixels = PixelKitMock()
            MacOSWebExtensionPixelFiring(pixelFiring: pixels).fire(.updateCheck(extensionID: identifier, outcome: outcome))

            XCTAssertEqual(pixels.actualFireCalls.count, 1)
            let call = try XCTUnwrap(pixels.actualFireCalls.first)
            let expectedName: String
            let expectedParameters: [String: String]
            switch outcome {
            case .updateFound:
                expectedName = "web_extension_update_found_macos"
                expectedParameters = ["extension_id": identifier]
            case .googleFlagged:
                expectedName = "web_extension_update_skipped_macos"
                expectedParameters = ["extension_id": identifier]
            default:
                expectedName = "web_extension_update_check_failed_macos"
                expectedParameters = ["extension_id": identifier, "outcome": outcome.rawValue]
            }
            XCTAssertEqual(call.pixel.name, expectedName)
            XCTAssertEqual(call.pixel.parameters, expectedParameters)
            XCTAssertEqual(call.frequency, .dailyAndCount)
            XCTAssertEqual(call.pixel.namePrefix, .none)
            XCTAssertEqual(call.pixel.standardParameters, [.pixelSource])
            XCTAssertNil(call.pixel.error)
            XCTAssertNil(call.additionalParameters)
            XCTAssertTrue(call.includeAppVersionParameter)
        }
    }

    func testUpdateCheckRejectsInvalidExtensionIdentifiers() {
        let pixels = PixelKitMock()
        let firing = MacOSWebExtensionPixelFiring(pixelFiring: pixels)
        for identifier in ["", "bitwarden", String(repeating: "a", count: 31), String(repeating: "z", count: 32), "https://example.com"] {
            firing.fire(.updateCheck(extensionID: identifier, outcome: .networkFailure))
        }
        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
    }

    func testUpdateCheckWireNamesMatchDefinitions() throws {
        for (outcome, expectedName) in [(WebExtensionUpdateCheckOutcome.updateFound, "web_extension_update_found_macos"),
                                        (.googleFlagged, "web_extension_update_skipped_macos"),
                                        (.networkFailure, "web_extension_update_check_failed_macos")] {
            let suite = "\(#function)-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var names: [String] = []
            let identifier = ChromeWebStoreID.bitwarden.rawValue
            let pixelKit = PixelKit(dryRun: false, appVersion: "1.0.0", source: PixelKit.Source.macDMG.rawValue,
                                    defaultHeaders: [:], pixelCalendar: nil, defaults: defaults) { name, _, _, _, _, completion in
                names.append(name)
                completion(true, nil)
            }
            let pixels = PixelKitMock()
            MacOSWebExtensionPixelFiring(pixelFiring: pixels).fire(.updateCheck(extensionID: identifier, outcome: outcome))
            let call = try XCTUnwrap(pixels.actualFireCalls.first)
            pixelKit.fire(call.pixel, frequency: call.frequency)
            XCTAssertEqual(names, [expectedName + "_daily", expectedName + "_count"])
        }
    }

    func testRecoveryApplicationUsesDailyAndCountWithoutCustomParameters() throws {
        let pixels = PixelKitMock()
        MacOSWebExtensionPixelFiring(pixelFiring: pixels).fire(.cpmNetworkProcessRecoveryApplied)

        XCTAssertEqual(pixels.actualFireCalls.count, 1)
        let call = try XCTUnwrap(pixels.actualFireCalls.first)
        XCTAssertEqual(call.pixel.name, "web_extension_cpm_network_process_recovery_applied")
        XCTAssertEqual(call.frequency, .dailyAndCount)
        XCTAssertEqual(call.pixel.namePrefix, .none)
        XCTAssertNil(call.pixel.parameters)
        XCTAssertEqual(call.pixel.standardParameters, [.pixelSource])
        XCTAssertNil(call.additionalParameters)
        XCTAssertTrue(call.includeAppVersionParameter)
    }

    func testRecoveryApplicationWireNamesMatchDefinitions() throws {
        let sources: [PixelKit.Source] = [.macDMG, .macStore]
        for source in sources {
            let pixels = PixelKitMock()
            MacOSWebExtensionPixelFiring(pixelFiring: pixels).fire(.cpmNetworkProcessRecoveryApplied)
            let call = try XCTUnwrap(pixels.actualFireCalls.first)
            let suite = "\(#function)-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var names: [String] = []
            let pixelKit = PixelKit(dryRun: false,
                                    appVersion: "1.0.0",
                                    source: source.rawValue,
                                    defaultHeaders: [:],
                                    pixelCalendar: nil,
                                    defaults: defaults) { name, _, _, _, _, completion in
                names.append(name)
                completion(true, nil)
            }
            pixelKit.fire(call.pixel, frequency: call.frequency)
            XCTAssertEqual(names, ["web_extension_cpm_network_process_recovery_applied_daily", "web_extension_cpm_network_process_recovery_applied_count"])
        }
    }
}
