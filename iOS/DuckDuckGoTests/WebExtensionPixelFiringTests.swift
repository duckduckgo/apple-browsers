//
//  WebExtensionPixelFiringTests.swift
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
@_spi(Testing) import PixelKit
import WebExtensions
@testable import DuckDuckGo

@available(iOS 18.4, *)
final class WebExtensionPixelFiringTests: XCTestCase {
    func testBackgroundLoadRestartOutcomesUseCanonicalPixelKitContract() throws {
        for outcome in CPMBackgroundLoadRestartOutcome.allCases {
            let pixels = PixelKitMock()
            iOSWebExtensionPixelFiring(pixelFiring: pixels).fire(.cpmBackgroundLoadRestart(outcome))
            XCTAssertEqual(pixels.actualFireCalls.count, 1)
            let call = try XCTUnwrap(pixels.actualFireCalls.first)
            XCTAssertEqual(call.pixel.name, "web_extension_cpm_background_load_restart")
            XCTAssertEqual(call.pixel.namePrefix, .none)
            XCTAssertEqual(call.frequency, .dailyAndCount)
            XCTAssertEqual(call.pixel.parameters, ["outcome": outcome.rawValue])
            XCTAssertNil(call.pixel.standardParameters)
            XCTAssertNil(call.additionalParameters)
            XCTAssertTrue(call.includeAppVersionParameter)
        }
    }

    func testRecoveryApplicationUsesDailyAndCountWithoutCustomParameters() throws {
        let pixels = PixelKitMock()
        iOSWebExtensionPixelFiring(pixelFiring: pixels).fire(.cpmNetworkProcessRecoveryApplied)

        XCTAssertEqual(pixels.actualFireCalls.count, 1)
        let call = try XCTUnwrap(pixels.actualFireCalls.first)
        XCTAssertEqual(call.pixel.name, "web_extension_cpm_network_process_recovery_applied")
        XCTAssertEqual(call.frequency, .dailyAndCount)
        XCTAssertEqual(call.pixel.namePrefix, .none)
        XCTAssertEqual(call.pixel.parameters, [:])
        XCTAssertNil(call.pixel.standardParameters)
        XCTAssertNil(call.additionalParameters)
        XCTAssertTrue(call.includeAppVersionParameter)
    }

    func testRecoveryApplicationWireNamesMatchDefinitions() throws {
        let sources: [(PixelKit.Source, String)] = [(.iOS, "ios_phone"), (.iPadOS, "ios_tablet")]
        for (source, suffix) in sources {
            let pixels = PixelKitMock()
            iOSWebExtensionPixelFiring(pixelFiring: pixels).fire(.cpmNetworkProcessRecoveryApplied)
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
            XCTAssertEqual(names, ["web_extension_cpm_network_process_recovery_applied_daily_\(suffix)", "web_extension_cpm_network_process_recovery_applied_count_\(suffix)"])
        }
    }
}
