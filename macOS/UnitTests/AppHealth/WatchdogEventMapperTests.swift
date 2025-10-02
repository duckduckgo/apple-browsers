//
//  WatchdogEventMapperTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import PixelKit
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class WatchdogEventMapperTests: XCTestCase {

    var pixelKit: PixelKit!
    var mockDiagnosticProvider: MockWatchdogDiagnosticProvider!
    var eventMapper: WatchdogEventMapper!
    var firedPixels: [(name: String, parameters: [String: String]?)]? = []

    override func setUp() {
        super.setUp()
        mockDiagnosticProvider = MockWatchdogDiagnosticProvider()
        setupMockPixelKit()

        eventMapper = WatchdogEventMapper(diagnosticProvider: mockDiagnosticProvider, pixelKit: pixelKit)
        firedPixels = []
    }

    override func tearDown() {
        mockDiagnosticProvider?.reset()
        mockDiagnosticProvider = nil
        pixelKit = nil
        eventMapper = nil
        firedPixels = nil

        super.tearDown()
    }

    private func setupMockPixelKit() {
        let mockFireRequest: PixelKit.FireRequest = { [weak self] pixelName, headers, parameters, allowedQueryReservedCharacters, callBackOnMainThread, onComplete in
            guard let self else { return }

            self.firedPixels?.append((name: pixelName, parameters: parameters))

            DispatchQueue.main.async {
                onComplete(true, nil)
            }
        }

        pixelKit = PixelKit(
            dryRun: false,
            appVersion: "1.0.0",
            source: "test",
            defaultHeaders: [:],
            dateGenerator: Date.init,
            defaults: UserDefaults(suiteName: "testHangWatchdog_\(UUID().uuidString)")!,
            fireRequest: mockFireRequest
        )
    }

    // MARK: - Helper methods

    private func setupMockDiagnostics(isOnBattery: Bool = true) {
        mockDiagnosticProvider.reset()

        mockDiagnosticProvider.diagnosticsToReturn = WatchdogDiagnostics(
            isInForeground: true,
            isAnyWindowVisible: true,
            isOnBattery: isOnBattery,
            openBrowserWindowCount: 2,
            openBrowserTabCount: 5
        )
    }

    // MARK: - Hang event mapping tests

    func testRecoveredHangEventToPixelMapping() {
        // Given
        let event = Watchdog.Event.uiHangRecovered(durationSeconds: 1)
        setupMockDiagnostics()

        // When
        let expectation = XCTestExpectation(description: "Pixel fired")
        eventMapper.fire(event) { _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then
        guard let pixel = firedPixels?.first else {
            XCTFail("No pixel fired")
            return
        }

        XCTAssertEqual(mockDiagnosticProvider.collectDiagnosticsCallCount, 1)
        XCTAssert(pixel.name.hasPrefix("m_mac_ui_hang_recovered"))
        XCTAssertEqual(pixel.parameters?["duration_seconds"], "1")
        XCTAssertEqual(pixel.parameters?["in_foreground"], "true")
        XCTAssertEqual(pixel.parameters?["any_window_visible"], "true")
        XCTAssertEqual(pixel.parameters?["battery_power"], "on-battery")
        XCTAssertEqual(pixel.parameters?["open_browser_window_count"], "2")
        XCTAssertEqual(pixel.parameters?["open_browser_tab_count"], "5")
    }

    func testNotRecoveredHangEventToPixelMapping() {
        // Given
        let event = Watchdog.Event.uiHangNotRecovered(durationSeconds: 5)
        setupMockDiagnostics()

        // When
        let expectation = XCTestExpectation(description: "Pixel fired")
        eventMapper.fire(event) { _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then
        guard let pixel = firedPixels?.first else {
            XCTFail("No pixel fired")
            return
        }

        XCTAssertEqual(mockDiagnosticProvider.collectDiagnosticsCallCount, 1)
        XCTAssert(pixel.name.hasPrefix("m_mac_ui_hang_not-recovered"))
    }

    func testBatteryPowerMappingOnBattery() {
        // Given
        let event = Watchdog.Event.uiHangRecovered(durationSeconds: 1)
        setupMockDiagnostics(isOnBattery: true)

        // When
        let expectation = XCTestExpectation(description: "Pixel fired")
        eventMapper.fire(event) { _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then
        guard let pixel = firedPixels?.first else {
            XCTFail("No pixel fired")
            return
        }

        XCTAssertEqual(mockDiagnosticProvider.collectDiagnosticsCallCount, 1)
        XCTAssertEqual(pixel.parameters?["battery_power"], "on-battery")
    }

    func testBatteryPowerMappingPluggedIn() {
        // Given
        let event = Watchdog.Event.uiHangRecovered(durationSeconds: 1)
        setupMockDiagnostics(isOnBattery: false)

        // When
        let expectation = XCTestExpectation(description: "Pixel fired")
        eventMapper.fire(event) { _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then
        guard let pixel = firedPixels?.first else {
            XCTFail("No pixel fired")
            return
        }
        XCTAssertEqual(mockDiagnosticProvider.collectDiagnosticsCallCount, 1)
        XCTAssertEqual(pixel.parameters?["battery_power"], "plugged-in")
    }
}
