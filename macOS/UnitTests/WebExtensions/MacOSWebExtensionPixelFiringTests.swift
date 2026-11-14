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
    func testUpdatePixelsUseOnlyAllowedParameters() throws {
        for pixelExtension in WebExtensionPixelExtension.allCases {
            var cases: [(WebExtensionPixelEvent, String, [String: String])] = [
                (.updateVerified(extension: pixelExtension), "web_extension_update_verified_macos", ["extension": pixelExtension.parameterValue]),
                (.updateApplied(extension: pixelExtension), "web_extension_update_success_macos", ["extension": pixelExtension.parameterValue])
            ]
            cases += WebExtensionUpdateDownloadFailure.allCases.map { outcome in
                (.updateDownloadFailed(extension: pixelExtension, outcome: outcome), "web_extension_update_download_failed_macos",
                 ["extension": pixelExtension.parameterValue, "outcome": outcome.rawValue])
            }
            cases += WebExtensionUpdateVerificationFailure.allCases.map { outcome in
                (.updateVerificationFailed(extension: pixelExtension, outcome: outcome), "web_extension_update_verification_failed_macos",
                 ["extension": pixelExtension.parameterValue, "outcome": outcome.rawValue])
            }
            cases += WebExtensionUpdateInstallFailure.allCases.map { outcome in
                (.updateInstallFailed(extension: pixelExtension, outcome: outcome), "web_extension_update_failure_macos",
                 ["extension": pixelExtension.parameterValue, "outcome": outcome.rawValue])
            }

            for (event, name, parameters) in cases {
                let pixels = PixelKitMock()
                MacOSWebExtensionPixelFiring(pixelFiring: pixels).fire(event)
                XCTAssertEqual(pixels.actualFireCalls.count, 1)
                let call = try XCTUnwrap(pixels.actualFireCalls.first)
                XCTAssertEqual(call.pixel.name, name)
                XCTAssertEqual(call.pixel.parameters, parameters)
                XCTAssertEqual(call.frequency, .dailyAndCount)
                XCTAssertEqual(call.pixel.namePrefix, .none)
                XCTAssertEqual(call.pixel.standardParameters, [.pixelSource])
                XCTAssertNil(call.pixel.error)
                XCTAssertNil(call.additionalParameters)
                XCTAssertTrue(call.includeAppVersionParameter)
            }
        }
    }

    func testUpdateWireNamesMatchDefinitions() throws {
        let pixelExtension: WebExtensionPixelExtension = .catalog(.bitwarden)
        let cases: [(WebExtensionPixelEvent, String)] = [
            (.updateDownloadFailed(extension: pixelExtension, outcome: .networkFailure), "web_extension_update_download_failed_macos"),
            (.updateVerificationFailed(extension: pixelExtension, outcome: .invalidPackage), "web_extension_update_verification_failed_macos"),
            (.updateVerified(extension: pixelExtension), "web_extension_update_verified_macos"),
            (.updateApplied(extension: pixelExtension), "web_extension_update_success_macos"),
            (.updateInstallFailed(extension: pixelExtension, outcome: .loadFailure), "web_extension_update_failure_macos")
        ]
        for (event, expectedName) in cases {
            let suite = "\(#function)-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var names: [String] = []
            let pixelKit = PixelKit(dryRun: false, appVersion: "1.0.0", source: PixelKit.Source.macDMG.rawValue,
                                    defaultHeaders: [:], pixelCalendar: nil, defaults: defaults) { name, _, _, _, _, completion in
                names.append(name)
                completion(true, nil)
            }
            let pixels = PixelKitMock()
            MacOSWebExtensionPixelFiring(pixelFiring: pixels).fire(event)
            let call = try XCTUnwrap(pixels.actualFireCalls.first)
            pixelKit.fire(call.pixel, frequency: call.frequency)
            XCTAssertEqual(names, [expectedName + "_daily", expectedName + "_count"])
        }
    }

    func testUpdateCheckOutcomesUseBoundedParametersAndDailyAndCount() throws {
        let pixelExtension: WebExtensionPixelExtension = .catalog(.bitwarden)
        for outcome in WebExtensionUpdateCheckOutcome.allCases {
            let pixels = PixelKitMock()
            MacOSWebExtensionPixelFiring(pixelFiring: pixels).fire(.updateCheck(extension: pixelExtension, outcome: outcome))

            XCTAssertEqual(pixels.actualFireCalls.count, 1)
            let call = try XCTUnwrap(pixels.actualFireCalls.first)
            let expectedName: String
            let expectedParameters: [String: String]
            switch outcome {
            case .updateFound:
                expectedName = "web_extension_update_found_macos"
                expectedParameters = ["extension": "bitwarden"]
            case .googleFlagged:
                expectedName = "web_extension_update_skipped_macos"
                expectedParameters = ["extension": "bitwarden"]
            default:
                expectedName = "web_extension_update_check_failed_macos"
                expectedParameters = ["extension": "bitwarden", "outcome": outcome.rawValue]
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

    func testUpdateCheckUsesEveryCatalogValueAndOther() throws {
        for pixelExtension in WebExtensionPixelExtension.allCases {
            let pixels = PixelKitMock()
            MacOSWebExtensionPixelFiring(pixelFiring: pixels).fire(.updateCheck(extension: pixelExtension, outcome: .networkFailure))
            let call = try XCTUnwrap(pixels.actualFireCalls.first)
            XCTAssertEqual(call.pixel.parameters, ["extension": pixelExtension.parameterValue, "outcome": "network_failure"])
        }
    }

    func testUpdateCheckWireNamesMatchDefinitions() throws {
        for (outcome, expectedName) in [(WebExtensionUpdateCheckOutcome.updateFound, "web_extension_update_found_macos"),
                                        (.googleFlagged, "web_extension_update_skipped_macos"),
                                        (.networkFailure, "web_extension_update_check_failed_macos")] {
            let suite = "\(#function)-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var names: [String] = []
            let pixelExtension: WebExtensionPixelExtension = .catalog(.bitwarden)
            let pixelKit = PixelKit(dryRun: false, appVersion: "1.0.0", source: PixelKit.Source.macDMG.rawValue,
                                    defaultHeaders: [:], pixelCalendar: nil, defaults: defaults) { name, _, _, _, _, completion in
                names.append(name)
                completion(true, nil)
            }
            let pixels = PixelKitMock()
            MacOSWebExtensionPixelFiring(pixelFiring: pixels).fire(.updateCheck(extension: pixelExtension, outcome: outcome))
            let call = try XCTUnwrap(pixels.actualFireCalls.first)
            pixelKit.fire(call.pixel, frequency: call.frequency)
            XCTAssertEqual(names, [expectedName + "_daily", expectedName + "_count"])
        }
    }

    func testExtensionManagementEventsUseDailyAndCount() throws {
        let events: [WebExtensionPixelEvent] = [
            .enabled(extension: .catalog(.bitwarden)),
            .disabled(extension: .catalog(.bitwarden)),
            .remotelyDisabled(extension: .catalog(.bitwarden))
        ]
        for event in events {
            let pixels = PixelKitMock()
            MacOSWebExtensionPixelFiring(pixelFiring: pixels).fire(event)
            XCTAssertEqual(try XCTUnwrap(pixels.actualFireCalls.first).frequency, .dailyAndCount, "\(event)")
        }
    }

    func testRetentionEventsUseStandard() throws {
        let events: [WebExtensionPixelEvent] = [
            .retained14Days(extension: .catalog(.bitwarden)),
            .churned14Days(extension: .catalog(.bitwarden))
        ]
        for event in events {
            let pixels = PixelKitMock()
            MacOSWebExtensionPixelFiring(pixelFiring: pixels).fire(event)
            XCTAssertEqual(try XCTUnwrap(pixels.actualFireCalls.first).frequency, .standard, "\(event)")
        }
    }

    func testInstalledCountIsDaily() throws {
        let pixels = PixelKitMock()
        MacOSWebExtensionPixelFiring(pixelFiring: pixels).fire(.installedCount(installed: 1, enabled: 0))

        let call = try XCTUnwrap(pixels.actualFireCalls.first)
        XCTAssertEqual(call.frequency, .daily)
        XCTAssertEqual(call.pixel.parameters, ["count": "1", "enabled_count": "0"])
    }
}
