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

    func testParametersIncludeSessionRestoration() {
        let pixel = buildStartupMetricsPixel(sessionRestoration: true)

        XCTAssertEqual(pixel.parameters?["session_restoration"], "true")
    }

    // MARK: - Optional Parameters Present

    func testParametersIncludeProcessorCountWhenProvided() {
        let pixel = buildStartupMetricsPixel(activeProcessorCount: 8)

        XCTAssertEqual(pixel.parameters?["active_processor_count"], "8")
    }

    func testParametersIncludeAppDelegateInitWhenProvided() {
        let pixel = buildStartupMetricsPixel(appDelegateInit: 0.151)

        XCTAssertEqual(pixel.parameters?["app_delegate_init"], "150")
    }

    func testParametersIncludeMainMenuInitWhenProvided() {
        let pixel = buildStartupMetricsPixel(mainMenuInit: 0.157)

        XCTAssertEqual(pixel.parameters?["main_menu_init"], "155")
    }

    func testParametersIncludeAppWillFinishLaunchingWhenProvided() {
        let pixel = buildStartupMetricsPixel(appWillFinishLaunching: 0.25)

        XCTAssertEqual(pixel.parameters?["app_will_finish_launching"], "250")
    }

    func testParametersIncludeAppDidFinishLaunchingBeforeStateRestorationWhenProvided() {
        let pixel = buildStartupMetricsPixel(appDidFinishLaunchingBeforeStateRestoration: 0.35)

        XCTAssertEqual(pixel.parameters?["app_did_finish_launching_before_state_restoration"], "350")
    }

    func testParametersIncludeAppDidFinishLaunchingAfterStateRestorationWhenProvided() {
        let pixel = buildStartupMetricsPixel(appDidFinishLaunchingAfterStateRestoration: 0.459)

        XCTAssertEqual(pixel.parameters?["app_did_finish_launching_after_state_restoration"], "455")
    }

    func testParametersIncludeAppStateRestorationWhenPositive() {
        let pixel = buildStartupMetricsPixel(appStateRestoration: 0.75)

        XCTAssertEqual(pixel.parameters?["app_state_restoration"], "750")
    }

    func testParametersExcludeAppStateRestorationWhenZero() {
        let pixel = buildStartupMetricsPixel(appStateRestoration: 0)

        XCTAssertNil(pixel.parameters?["app_state_restoration"])
    }

    func testParametersIncludeInitToWillFinishLaunching() {
        let pixel = buildStartupMetricsPixel(initToWillFinishLaunching: 0.15)

        XCTAssertEqual(pixel.parameters?["init_to_will_finish_launching"], "150")
    }

    func testParametersIncludeAppWillFinishToDidFinishLaunching() {
        let pixel = buildStartupMetricsPixel(appWillFinishToDidFinishLaunching: 1.5)

        XCTAssertEqual(pixel.parameters?["app_will_finish_to_app_did_finish_launching"], "1500")
    }

    func testParametersIncludeTimeToInteractive() {
        let pixel = buildStartupMetricsPixel(timeToInteractive: 2.529)

        XCTAssertEqual(pixel.parameters?["time_to_interactive"], "2525")
    }

    func testParametersIncludeWindowsWhenProvided() {
        let pixel = buildStartupMetricsPixel(windows: 5)

        XCTAssertEqual(pixel.parameters?["windows"], "4")
    }

    func testParametersIncludeStandardTabsWhenProvided() {
        let pixel = buildStartupMetricsPixel(standardTabs: 30)

        XCTAssertEqual(pixel.parameters?["standard_tabs"], "21")
    }

    func testParametersIncludePinnedTabsWhenProvided() {
        let pixel = buildStartupMetricsPixel(pinnedTabs: 30)

        XCTAssertEqual(pixel.parameters?["pinned_tabs"], "15")
    }

    // MARK: - Optional Parameters Nil

    func testParametersExcludeNilOptionalFields() throws {
        let pixel = buildStartupMetricsPixel()
        let params = try XCTUnwrap(pixel.parameters)

        XCTAssertNil(params["active_processor_count"])
        XCTAssertNil(params["app_delegate_init"])
        XCTAssertNil(params["main_menu_init"])
        XCTAssertNil(params["app_will_finish_launching"])
        XCTAssertNil(params["app_did_finish_launching_before_state_restoration"])
        XCTAssertNil(params["app_did_finish_launching_after_state_restoration"])
        XCTAssertNil(params["app_state_restoration"])
        XCTAssertNil(params["init_to_will_finish_launching"])
        XCTAssertNil(params["app_will_finish_to_app_did_finish_launching"])
        XCTAssertNil(params["time_to_interactive"])
        XCTAssertNil(params["windows"])
        XCTAssertNil(params["standard_tabs"])
        XCTAssertNil(params["pinned_tabs"])
    }

    // MARK: - Bucketing

    func testProcessorCountIsBucketed() {
        let pixel = buildStartupMetricsPixel(activeProcessorCount: 6)

        XCTAssertEqual(pixel.parameters?["active_processor_count"], "4")
    }

    func testDurationsAreRoundedToFiveMilliseconds() {
        let pixel = buildStartupMetricsPixel(appDelegateInit: 1.508)

        XCTAssertEqual(pixel.parameters?["app_delegate_init"], "1505")
    }

    func testWindowCountIsBucketed() {
        let pixel = buildStartupMetricsPixel(windows: 15)

        XCTAssertEqual(pixel.parameters?["windows"], "11")
    }

    func testStandardTabCountIsBucketed() {
        let pixel = buildStartupMetricsPixel(standardTabs: 9)

        XCTAssertEqual(pixel.parameters?["standard_tabs"], "7")
    }

    func testPinnedTabCountIsBucketed() {
        let pixel = buildStartupMetricsPixel(pinnedTabs: 9)

        XCTAssertEqual(pixel.parameters?["pinned_tabs"], "7")
    }
}

// MARK: - Helpers

private extension StartupMetricsPixelTests {

    func buildStartupMetricsPixel(
        architecture: String = "ARM",
        activeProcessorCount: Int? = nil,
        isOnBattery: Bool = false,
        sessionRestoration: Bool = false,
        windows: Int? = nil,
        standardTabs: Int? = nil,
        pinnedTabs: Int? = nil,
        appDelegateInit: TimeInterval? = nil,
        mainMenuInit: TimeInterval? = nil,
        appWillFinishLaunching: TimeInterval? = nil,
        appDidFinishLaunchingBeforeStateRestoration: TimeInterval? = nil,
        appDidFinishLaunchingAfterStateRestoration: TimeInterval? = nil,
        appStateRestoration: TimeInterval? = nil,
        initToWillFinishLaunching: TimeInterval? = nil,
        appWillFinishToDidFinishLaunching: TimeInterval? = nil,
        timeToInteractive: TimeInterval? = nil
    ) -> StartupMetricsPixel {
        StartupMetricsPixel(
            architecture: architecture,
            activeProcessorCount: activeProcessorCount,
            isOnBattery: isOnBattery,
            sessionRestoration: sessionRestoration,
            windows: windows,
            standardTabs: standardTabs,
            pinnedTabs: pinnedTabs,
            appDelegateInit: appDelegateInit,
            mainMenuInit: mainMenuInit,
            appWillFinishLaunching: appWillFinishLaunching,
            appDidFinishLaunchingBeforeStateRestoration: appDidFinishLaunchingBeforeStateRestoration,
            appDidFinishLaunchingAfterStateRestoration: appDidFinishLaunchingAfterStateRestoration,
            appStateRestoration: appStateRestoration,
            initToWillFinishLaunching: initToWillFinishLaunching,
            appWillFinishToDidFinishLaunching: appWillFinishToDidFinishLaunching,
            timeToInteractive: timeToInteractive
        )
    }
}
