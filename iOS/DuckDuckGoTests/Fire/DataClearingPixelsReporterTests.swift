//
//  DataClearingPixelsReporterTests.swift
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

@_spi(Testing) import PixelKit
import XCTest

@testable import DuckDuckGo

final class DataClearingPixelsReporterTests: XCTestCase {

    private var mockPixelFiring: PixelKitMock!
    private var sut: DataClearingPixelsReporter!
    private var currentTime: CFTimeInterval!

    override func setUp() {
        super.setUp()
        mockPixelFiring = PixelKitMock()
        currentTime = 0.0
        sut = DataClearingPixelsReporter(
            pixelFiring: mockPixelFiring,
            timeProvider: { [weak self] in self?.currentTime ?? 0.0 }
        )
    }

    override func tearDown() {
        mockPixelFiring = nil
        sut = nil
        currentTime = nil
        super.tearDown()
    }

    // MARK: - fireRetriggerPixelIfNeeded Tests
    
    @MainActor
    func testWhenFirstFireThenNoRetriggerPixelIsFired() {
        // When
        sut.fireRetriggerPixelIfNeeded(request: FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .settings))
        
        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should fire on first call")
    }
    
    @MainActor
    func testWhenCalledTwiceWithin20SecondsThenRetriggerPixelIsFired() {
        let request = FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .settings)
        // Given - first call sets lastFireTime
        sut.fireRetriggerPixelIfNeeded(request: request)
        
        // When - second call within 20 seconds
        currentTime += 10
        sut.fireRetriggerPixelIfNeeded(request: request)
        
        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }
    
    @MainActor
    func testWhenCalledExactlyAt20SecondsThenRetriggerPixelIsFired() {
        let request = FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .settings)
        // Given
        sut.fireRetriggerPixelIfNeeded(request: request)
        
        // When - exactly at 20 seconds (edge case, <= condition)
        currentTime += 20
        sut.fireRetriggerPixelIfNeeded(request: request)
        
        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }
    
    @MainActor
    func testWhenCalledAfter20SecondsThenNoRetriggerPixelIsFired() {
        let request = FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .settings)
        // Given
        sut.fireRetriggerPixelIfNeeded(request: request)
        
        // When - after 20 seconds
        currentTime += 21
        sut.fireRetriggerPixelIfNeeded(request: request)
        
        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should fire after window expires")
    }
    
    @MainActor
    func testWhenCalledMultipleTimesWithinWindowThenRetriggerPixelFiredEachTime() {
        let request = FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .settings)
        // Given
        sut.fireRetriggerPixelIfNeeded(request: request)

        // When - multiple rapid calls within window
        currentTime += 5
        sut.fireRetriggerPixelIfNeeded(request: request)

        currentTime += 5
        sut.fireRetriggerPixelIfNeeded(request: request)

        currentTime += 5
        sut.fireRetriggerPixelIfNeeded(request: request)

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard),
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard),
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    @MainActor
    func testWhenTriggerIsAutoClearOnLaunchThenNoRetriggerPixelIsFired() {
        // Given
        let autoClearRequest = FireRequest(options: .all, trigger: .autoClearOnLaunch, scope: .all, source: .autoClear)
        sut.fireRetriggerPixelIfNeeded(request: autoClearRequest)

        // When - second call within window with auto-clear trigger
        currentTime += 10
        sut.fireRetriggerPixelIfNeeded(request: autoClearRequest)

        // Then - no pixels should fire because trigger is not manualFire
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should fire for auto-clear on launch triggers")
    }

    @MainActor
    func testWhenTriggerIsAutoClearOnForegroundThenNoRetriggerPixelIsFired() {
        // Given
        let autoClearRequest = FireRequest(options: .all, trigger: .autoClearOnForeground, scope: .all, source: .autoClear)
        sut.fireRetriggerPixelIfNeeded(request: autoClearRequest)

        // When - second call within window with auto-clear foreground trigger
        currentTime += 15
        sut.fireRetriggerPixelIfNeeded(request: autoClearRequest)

        // Then - no pixels should fire because trigger is not manualFire
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should fire for auto-clear on foreground triggers")
    }

    // MARK: - fireUserActionBeforeCompletionPixel Tests

    func testWhenFireUserActionBeforeCompletionPixelCalledThenPixelIsFired() {
        // When
        sut.fireUserActionBeforeCompletionPixel()

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.userActionBeforeCompletion, frequency: .standard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    // MARK: - Data Clearing Completion Pixels

    func testWhenMeasuringThenDurationComesFromTheInjectedClock() {
        // Given
        let measurement = sut.beginMeasurement()

        // When
        currentTime += 1.5

        // Then
        XCTAssertEqual(sut.duration(of: measurement), 1.5)
    }

    func testWhenMeasurementIsNotAdvancedThenDurationIsZero() {
        XCTAssertEqual(sut.duration(of: sut.beginMeasurement()), 0)
    }

    func testWhenCompletionPixelIsFiredThenMeasuredDurationIsSent() {
        // Given
        let measurement = sut.beginMeasurement()
        currentTime += 1.5

        // When
        sut.fireDataClearingCompletionPixel(.allDataCleared(duration: sut.duration(of: measurement), tabCount: 3))

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingCompletionPixels.allDataCleared(duration: 1.5, tabCount: 3), frequency: .standard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    /// Pins the wire contract: `dur` carries seconds as a floating-point string, matching the
    /// `durationSeconds` shared parameter the four definitions declare.
    func testWhenCompletionPixelCarriesDurationThenItIsFloatingPointSeconds() {
        let pixel = DataClearingCompletionPixels.allDataCleared(duration: 1.5, tabCount: 3)

        XCTAssertEqual(pixel.parameters?["dur"], "1.5")
    }

    func testCompletionPixelNames() {
        XCTAssertEqual(DataClearingCompletionPixels.allDataCleared(duration: 0, tabCount: 0).name, "mf_dc")
        XCTAssertEqual(DataClearingCompletionPixels.fireModeDataCleared(duration: 0, tabCount: 0).name,
                       "m_fire-mode_data-cleared")
        XCTAssertEqual(DataClearingCompletionPixels.normalModeDataCleared(duration: 0, tabCount: 0).name,
                       "m_normal-mode_data-cleared")
        XCTAssertEqual(DataClearingCompletionPixels.singleTabDataCleared(duration: 0,
                                                                        tabType: "web",
                                                                        browsingMode: "normal",
                                                                        domainsCount: 0).name,
                       "m_single-tab-data_cleared")
    }

    func testWhenCompletionPixelIsScopedToATabThenItCarriesTheTabParameters() {
        let pixel = DataClearingCompletionPixels.singleTabDataCleared(duration: 2,
                                                                     tabType: "ai",
                                                                     browsingMode: "fire",
                                                                     domainsCount: 7)

        XCTAssertEqual(pixel.parameters, [
            "dur": "2.0",
            "tabType": "ai",
            "browsing_mode": "fire",
            "domainsCount": "7"
        ])
    }

    func testWhenCompletionPixelIsScopedToAModeThenItCarriesTheTabCount() {
        let pixel = DataClearingCompletionPixels.fireModeDataCleared(duration: 2, tabCount: 4)

        XCTAssertEqual(pixel.parameters, ["dur": "2.0", "tc": "4"])
    }

    /// The names already carry their own `m_` prefix, so the custom-prefix conformance exists only
    /// to suppress the default one. The `_ios_phone` / `_ios_tablet` marker comes from
    /// `platformSuffixPolicy`, not from this conformance.
    func testCompletionPixelsAddNoNamePrefix() {
        XCTAssertEqual(DataClearingCompletionPixels.allDataCleared(duration: 0, tabCount: 0).namePrefix, .none)
    }

    /// Unlike `DataClearingPixels`, these four do not declare `pixelSource` in `forget_all.json5`.
    func testCompletionPixelsSendNoStandardParameters() {
        XCTAssertNil(DataClearingCompletionPixels.allDataCleared(duration: 0, tabCount: 0).standardParameters)
    }

    /// The reason these events conform to `PixelKitEventWithCustomPrefix`: without it PixelKit sends
    /// the name verbatim on iOS (`PixelKit.swift:887`), dropping the form-factor suffix these four
    /// have carried since they were fired through `Pixel.fire`. Pins the wire contract that the
    /// migration to PixelKit had to preserve.
    func testWhenCompletionPixelIsFiredThenNameKeepsTheFormFactorSuffix() {
        assertFiredPixelName(source: .iOS, equals: "mf_dc_ios_phone")
        assertFiredPixelName(source: .iPadOS, equals: "mf_dc_ios_tablet")
    }

    private func assertFiredPixelName(source: PixelKit.Source,
                                      equals expectedName: String,
                                      file: StaticString = #file,
                                      line: UInt = #line) {
        let suiteName = "DataClearingCompletionPixelsTests.\(source.rawValue)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fired = expectation(description: "pixel fired")
        let pixelKit = PixelKit(dryRun: false,
                                appVersion: "1.0.0",
                                source: source.rawValue,
                                defaultHeaders: [:],
                                defaults: defaults) { firedName, _, _, _, _, _ in
            XCTAssertEqual(firedName, expectedName, file: file, line: line)
            fired.fulfill()
        }

        pixelKit.fire(DataClearingCompletionPixels.allDataCleared(duration: 0, tabCount: 0))

        wait(for: [fired], timeout: 1)
    }

    // MARK: - Nil PixelFiring Tests
    
    @MainActor
    func testWhenPixelFiringIsNilThenNoPixelIsFiredAndNoCrash() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: nil)

        // When - should not crash
        sut.fireRetriggerPixelIfNeeded(request: FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .settings))
        sut.fireUserActionBeforeCompletionPixel()
        sut.fireDataClearingCompletionPixel(.allDataCleared(duration: 0, tabCount: 0))

        // Then - no crash occurred
    }
}

// MARK: - PixelKitMock assertion helper

/// Local to this test target. PixelKit's testing support deliberately does not link XCTest — a target that
/// does cannot be built as a dynamic framework, so Xcode links it statically and absorbs PixelKit into each
/// test bundle, giving the app and the tests separate `PixelKit.shared` values.
private extension PixelKitMock {

    func verifyExpectations(file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(expectedFireCalls, actualFireCalls, file: file, line: line)
    }
}
