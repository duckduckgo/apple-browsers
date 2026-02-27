//
//  StartupMetricsPixelTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class StartupMetricsPixelTests: XCTestCase {

    // MARK: - Name

    func testPixelName() {
        let pixel = buildStartupMetricsPixel()

        XCTAssertEqual(pixel.name, "m_mac_startup_performance_metrics")
    }

    // MARK: - Standard Parameters

    func testStandardParametersContainsPixelSource() {
        let pixel = buildStartupMetricsPixel()

        XCTAssertEqual(pixel.standardParameters, [.pixelSource])
    }

    // MARK: - Required Parameters

    func testParametersIncludeBatteryPower() {
        let pixel = buildStartupMetricsPixel(isOnBattery: true)

        XCTAssertEqual(pixel.parameters?["battery_power"], "true")
    }

    func testParametersIncludeArchitecture() {
        let pixel = buildStartupMetricsPixel(architecture: "ARM")

        XCTAssertEqual(pixel.parameters?["architecture"], "ARM")
    }

    // MARK: - Optional Parameters Present

    func testParametersIncludeProcessorCountWhenProvided() {
        let pixel = buildStartupMetricsPixel(activeProcessorCount: 8)

        XCTAssertEqual(pixel.parameters?["active_processor_count"], "8")
    }

    func testParametersIncludeDurationOfAppInitWhenProvided() {
        let pixel = buildStartupMetricsPixel(durationOfAppInit: 0.15)

        XCTAssertEqual(pixel.parameters?["duration_of_app_init"], "100")
    }

    func testParametersIncludeDurationOfAppWillFinishLaunchingWhenProvided() {
        let pixel = buildStartupMetricsPixel(durationOfAppWillFinishLaunching: 0.25)

        XCTAssertEqual(pixel.parameters?["duration_of_app_will_finish_launching"], "200")
    }

    func testParametersIncludeDurationBeforeStateRestorationWhenProvided() {
        let pixel = buildStartupMetricsPixel(durationOfAppDidFinishLaunchingBeforeStateRestoration: 0.35)

        XCTAssertEqual(pixel.parameters?["duration_of_app_did_finish_launching_before_state_restoration"], "300")
    }

    func testParametersIncludeDurationAfterStateRestorationWhenProvided() {
        let pixel = buildStartupMetricsPixel(durationOfAppDidFinishLaunchingAfterStateRestoration: 0.45)

        XCTAssertEqual(pixel.parameters?["duration_of_app_did_finish_launching_after_state_restoration"], "400")
    }

    func testParametersIncludeDurationOfStateRestorationWhenPositive() {
        let pixel = buildStartupMetricsPixel(durationOfAppStateRestoration: 0.75)

        XCTAssertEqual(pixel.parameters?["duration_of_app_state_restoration"], "500")
    }

    func testParametersExcludeDurationOfStateRestorationWhenZero() {
        let pixel = buildStartupMetricsPixel(durationOfAppStateRestoration: 0)

        XCTAssertNil(pixel.parameters?["duration_of_app_state_restoration"])
    }

    func testParametersIncludeDeltaBetweenInitAndWillFinish() {
        let pixel = buildStartupMetricsPixel(deltaBetweenAppInitAndWillFinishLaunching: 0.15)

        XCTAssertEqual(pixel.parameters?["delta_between_app_init_and_app_will_finish_launching"], "100")
    }

    func testParametersIncludeDeltaBetweenWillFinishAndDidFinish() {
        let pixel = buildStartupMetricsPixel(deltaBetweenAppWillFinishAndDidFinishLaunching: 1.5)

        XCTAssertEqual(pixel.parameters?["delta_between_app_will_finish_and_app_did_finish"], "1000")
    }

    func testParametersIncludeDeltaBetweenLaunchAndDidDisplay() {
        let pixel = buildStartupMetricsPixel(deltaBetweenLaunchAndDidDisplayInterface: 2.5)

        XCTAssertEqual(pixel.parameters?["delta_between_launch_and_did_display_interface"], "2000")
    }

    func testParametersIncludeWindowsRestoredWhenProvided() {
        let pixel = buildStartupMetricsPixel(numberOfWindowsRestored: 5)

        XCTAssertEqual(pixel.parameters?["number_of_windows_restored"], "4")
    }

    func testParametersIncludeTabsRestoredWhenProvided() {
        let pixel = buildStartupMetricsPixel(numberOfTabsRestored: 30)

        XCTAssertEqual(pixel.parameters?["number_of_tabs_restored"], "21")
    }

    // MARK: - Optional Parameters Nil

    func testParametersExcludeNilOptionalFields() throws {
        let pixel = buildStartupMetricsPixel()
        let params = try XCTUnwrap(pixel.parameters)

        XCTAssertNil(params["active_processor_count"])
        XCTAssertNil(params["duration_of_app_init"])
        XCTAssertNil(params["duration_of_app_will_finish_launching"])
        XCTAssertNil(params["duration_of_app_did_finish_launching_before_state_restoration"])
        XCTAssertNil(params["duration_of_app_did_finish_launching_after_state_restoration"])
        XCTAssertNil(params["duration_of_app_state_restoration"])
        XCTAssertNil(params["delta_between_app_init_and_app_will_finish_launching"])
        XCTAssertNil(params["delta_between_app_will_finish_and_app_did_finish"])
        XCTAssertNil(params["delta_between_launch_and_did_display_interface"])
        XCTAssertNil(params["number_of_windows_restored"])
        XCTAssertNil(params["number_of_tabs_restored"])
    }

    // MARK: - Bucketing

    func testProcessorCountIsBucketed() {
        let pixel = buildStartupMetricsPixel(activeProcessorCount: 6)

        XCTAssertEqual(pixel.parameters?["active_processor_count"], "4")
    }

    func testDurationsAreBucketedAsMilliseconds() {
        let pixel = buildStartupMetricsPixel(durationOfAppInit: 1.5)

        XCTAssertEqual(pixel.parameters?["duration_of_app_init"], "1000")
    }

    func testWindowCountIsBucketed() {
        let pixel = buildStartupMetricsPixel(numberOfWindowsRestored: 15)

        XCTAssertEqual(pixel.parameters?["number_of_windows_restored"], "11")
    }

    func testTabCountIsBucketed() {
        let pixel = buildStartupMetricsPixel(numberOfTabsRestored: 9)

        XCTAssertEqual(pixel.parameters?["number_of_tabs_restored"], "7")
    }
}

// MARK: - Helpers

private extension StartupMetricsPixelTests {

    func buildStartupMetricsPixel(
        isOnBattery: Bool = false,
        architecture: String = "ARM",
        activeProcessorCount: Int? = nil,
        durationOfAppInit: TimeInterval? = nil,
        durationOfAppWillFinishLaunching: TimeInterval? = nil,
        durationOfAppDidFinishLaunchingBeforeStateRestoration: TimeInterval? = nil,
        durationOfAppDidFinishLaunchingAfterStateRestoration: TimeInterval? = nil,
        durationOfAppStateRestoration: TimeInterval? = nil,
        deltaBetweenAppInitAndWillFinishLaunching: TimeInterval? = nil,
        deltaBetweenAppWillFinishAndDidFinishLaunching: TimeInterval? = nil,
        deltaBetweenLaunchAndDidDisplayInterface: TimeInterval? = nil,
        numberOfWindowsRestored: Int? = nil,
        numberOfTabsRestored: Int? = nil
    ) -> StartupMetricsPixel {
        StartupMetricsPixel(
            isOnBattery: isOnBattery,
            architecture: architecture,
            activeProcessorCount: activeProcessorCount,
            durationOfAppInit: durationOfAppInit,
            durationOfAppWillFinishLaunching: durationOfAppWillFinishLaunching,
            durationOfAppDidFinishLaunchingBeforeStateRestoration: durationOfAppDidFinishLaunchingBeforeStateRestoration,
            durationOfAppDidFinishLaunchingAfterStateRestoration: durationOfAppDidFinishLaunchingAfterStateRestoration,
            durationOfAppStateRestoration: durationOfAppStateRestoration,
            deltaBetweenAppInitAndWillFinishLaunching: deltaBetweenAppInitAndWillFinishLaunching,
            deltaBetweenAppWillFinishAndDidFinishLaunching: deltaBetweenAppWillFinishAndDidFinishLaunching,
            deltaBetweenLaunchAndDidDisplayInterface: deltaBetweenLaunchAndDidDisplayInterface,
            numberOfWindowsRestored: numberOfWindowsRestored,
            numberOfTabsRestored: numberOfTabsRestored
        )
    }
}
