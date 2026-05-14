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

import PixelKit
import PixelKitTestingUtilities
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

    // MARK: - Nil PixelFiring Tests
    
    @MainActor
    func testWhenPixelFiringIsNilThenNoPixelIsFiredAndNoCrash() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: nil)

        // When - should not crash
        sut.fireRetriggerPixelIfNeeded(request: FireRequest(options: .all, trigger: .manualFire, scope: .all, source: .settings))
        sut.fireUserActionBeforeCompletionPixel()

        // Then - no crash occurred
    }
}
