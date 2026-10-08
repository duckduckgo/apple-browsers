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

import FeatureFlags_iOS
import XCTest
@_spi(Testing) import PixelKit
@testable import DuckDuckGo

/// Verify device eligibility, daily limits, and launch-timing privacy measures.
final class DeviceLaunchPixelReporterTests: XCTestCase {
    func testMatchingDeviceFiresDailyPixelWithExactName() throws {
        let pixelFiring = PixelKitMock()
        let reporter = DeviceLaunchPixelReporter(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.iPhoneDuoLaunchReporting]),
                                                 machineIdentifier: { "iPhone19,4" }, pixelFiring: pixelFiring, schedule: { _, action in action() })

        reporter.reportLaunch()

        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1)
        let call = try XCTUnwrap(pixelFiring.actualFireCalls.first)
        XCTAssertEqual(call.pixel.name, "iphone-duo-launched")
        XCTAssertEqual(call.frequency, .daily)
        XCTAssertEqual(call.pixel.namePrefix, .platformDefault)
        XCTAssertEqual(call.pixel.platformSuffixPolicy, .standard)
        XCTAssertEqual(call.pixel.parameters, ["petal": "randomize"])
        XCTAssertNil(call.pixel.standardParameters)
    }

    func testPixelKitSendsDailyWithPetalAcrossRecreatedStorage() throws {
        let suiteName = "DeviceLaunchPixelReporterTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPhoneDuoLaunchReporting])
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        var names = [String]()
        var parameters = [[String: String]]()

        func makeReporter() throws -> DeviceLaunchPixelReporter {
            let pixelKit = PixelKit(dryRun: false,
                                    appVersion: "1.0.0",
                                    source: PixelKit.Source.iOS.rawValue,
                                    defaultHeaders: [:],
                                    dateGenerator: { date },
                                    defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName))) { name, _, params, _, _, completion in
                names.append(name)
                parameters.append(params)
                completion(true, nil)
            }
            return DeviceLaunchPixelReporter(featureFlagger: featureFlagger,
                                              machineIdentifier: { "iPhone19,4" }, pixelFiring: pixelKit,
                                              schedule: { _, action in action() })
        }

        let reporter = try makeReporter()
        reporter.reportLaunch()
        reporter.reportLaunch()
        XCTAssertEqual(names, ["iphone-duo-launched_daily_ios_phone"])
        XCTAssertEqual(parameters.first?["petal"], "randomize")

        let relaunchedReporter = try makeReporter()
        relaunchedReporter.reportLaunch()
        XCTAssertEqual(names.count, 1)

        featureFlagger.enabledFeatureFlags = []
        reporter.reportLaunch()
        featureFlagger.enabledFeatureFlags = [.iPhoneDuoLaunchReporting]
        reporter.reportLaunch()
        XCTAssertEqual(names.count, 1)

        date.addTimeInterval(24 * 60 * 60)
        relaunchedReporter.reportLaunch()
        XCTAssertEqual(names, ["iphone-duo-launched_daily_ios_phone", "iphone-duo-launched_daily_ios_phone"])
        XCTAssertEqual(parameters.map { $0["petal"] }, ["randomize", "randomize"])
    }

    func testPixelWaitsForRandomDelayBetweenOneAndThirtySeconds() throws {
        let pixelFiring = PixelKitMock()
        var scheduledDelay: TimeInterval?
        var pendingAction: (() -> Void)?
        let reporter = DeviceLaunchPixelReporter(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.iPhoneDuoLaunchReporting]),
                                                 machineIdentifier: { "iPhone19,4" }, pixelFiring: pixelFiring,
                                                 schedule: { delay, action in
            scheduledDelay = delay
            pendingAction = action
        })

        reporter.reportLaunch()

        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
        XCTAssertTrue((1...30).contains(try XCTUnwrap(scheduledDelay)))
        try XCTUnwrap(pendingAction)()
        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1)
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.frequency, .daily)
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.parameters, ["petal": "randomize"])
    }

    func testFlagDisabledDuringDelayPreventsPixel() throws {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.iPhoneDuoLaunchReporting])
        let pixelFiring = PixelKitMock()
        var pendingAction: (() -> Void)?
        let reporter = DeviceLaunchPixelReporter(featureFlagger: featureFlagger,
                                                 machineIdentifier: { "iPhone19,4" }, pixelFiring: pixelFiring,
                                                 schedule: { _, action in pendingAction = action })

        reporter.reportLaunch()
        featureFlagger.enabledFeatureFlags = []
        try XCTUnwrap(pendingAction)()

        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testOtherDevicesDoNotFirePixel() {
        for identifier in ["iPhone19,3", "iPhone19,40", "iPad16,1", "arm64", ""] {
            let pixelFiring = PixelKitMock()
            let reporter = DeviceLaunchPixelReporter(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.iPhoneDuoLaunchReporting]),
                                                     machineIdentifier: { identifier }, pixelFiring: pixelFiring, schedule: { _, action in action() })

            reporter.reportLaunch()

            XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty, identifier)
        }
    }

    func testFailedLookupDoesNotFirePixel() {
        let pixelFiring = PixelKitMock()
        let reporter = DeviceLaunchPixelReporter(featureFlagger: MockFeatureFlagger(enabledFeatureFlags: [.iPhoneDuoLaunchReporting]),
                                                 machineIdentifier: { nil }, pixelFiring: pixelFiring, schedule: { _, action in action() })

        reporter.reportLaunch()

        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testDisabledFlagSkipsLookupAndPixel() {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let pixelFiring = PixelKitMock()
        var lookupCount = 0
        let reporter = DeviceLaunchPixelReporter(featureFlagger: featureFlagger,
                                                 machineIdentifier: {
            lookupCount += 1
            return "iPhone19,4"
        }, pixelFiring: pixelFiring, schedule: { _, action in action() })

        reporter.reportLaunch()

        XCTAssertEqual(lookupCount, 0)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    func testFlagChangesApplyToExistingReporter() {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        let pixelFiring = PixelKitMock()
        let reporter = DeviceLaunchPixelReporter(featureFlagger: featureFlagger,
                                                 machineIdentifier: { "iPhone19,4" }, pixelFiring: pixelFiring, schedule: { _, action in action() })

        reporter.reportLaunch()
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)

        featureFlagger.enabledFeatureFlags = [.iPhoneDuoLaunchReporting]
        reporter.reportLaunch()
        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1)

        featureFlagger.enabledFeatureFlags = []
        reporter.reportLaunch()
        XCTAssertEqual(pixelFiring.actualFireCalls.count, 1)

        featureFlagger.enabledFeatureFlags = [.iPhoneDuoLaunchReporting]
        reporter.reportLaunch()
        XCTAssertEqual(pixelFiring.actualFireCalls.count, 2)
    }

    func testHardwareMachineReturnsNonemptyValue() throws {
        let identifier = try XCTUnwrap(DeviceLaunchPixelReporter.hardwareMachine())
        XCTAssertFalse(identifier.isEmpty)
        XCTAssertFalse(identifier.contains("\0"))
    }
}
