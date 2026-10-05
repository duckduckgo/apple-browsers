//
//  DeviceLaunchPixelReporterTests.swift
//  DuckDuckGoTests
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
@testable import DuckDuckGo

final class DeviceLaunchPixelReporterTests: XCTestCase {
    func testMatchingDeviceFiresDailyPixelWithExactName() throws {
        let pixelFiring = PixelKitMock()
        let reporter = DeviceLaunchPixelReporter(machineIdentifier: { "iPhone19,4" }, pixelFiring: pixelFiring)

        reporter.reportLaunch()

        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1)
        let call = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(call.pixel.name, "iphone-duo-launched")
        XCTAssertEqual(call.frequency, .daily)
        XCTAssertEqual(call.pixel.namePrefix, .platformDefault)
        XCTAssertEqual(call.pixel.platformSuffixPolicy, .standard)
        XCTAssertNil(call.pixel.parameters)
        XCTAssertNil(call.pixel.standardParameters)
    }

    func testPixelKitSendsExactNameOncePerDay() throws {
        let suiteName = "DeviceLaunchPixelReporterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        var names = [String]()
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                source: PixelKit.Source.iOS.rawValue,
                                defaultHeaders: [:],
                                dateGenerator: { date },
                                defaults: defaults) { name, _, _, _, _, completion in
            names.append(name)
            completion(true, nil)
        }
        let reporter = DeviceLaunchPixelReporter(machineIdentifier: { "iPhone19,4" }, pixelFiring: pixelKit)

        reporter.reportLaunch()
        reporter.reportLaunch()
        XCTAssertEqual(names, ["iphone-duo-launched_daily_ios_phone"])

        date.addTimeInterval(24 * 60 * 60)
        reporter.reportLaunch()
        XCTAssertEqual(names, ["iphone-duo-launched_daily_ios_phone", "iphone-duo-launched_daily_ios_phone"])
    }

    func testOtherDevicesDoNotFirePixel() {
        for identifier in ["iPhone19,3", "iPhone19,40", "iPad16,1", "arm64", ""] {
            let pixelFiring = PixelKitMock()
            let reporter = DeviceLaunchPixelReporter(machineIdentifier: { identifier }, pixelFiring: pixelFiring)

            reporter.reportLaunch()

            XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty, identifier)
        }
    }

    func testFailedLookupDoesNotFirePixel() {
        let pixelFiring = PixelKitMock()
        let reporter = DeviceLaunchPixelReporter(machineIdentifier: { nil }, pixelFiring: pixelFiring)

        reporter.reportLaunch()

        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testHardwareMachineReturnsNonemptyValue() throws {
        let identifier = try XCTUnwrap(DeviceLaunchPixelReporter.hardwareMachine())
        XCTAssertFalse(identifier.isEmpty)
        XCTAssertFalse(identifier.contains("\0"))
    }
}
