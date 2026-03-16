//
//  DataClearingPixelsReporterTests.swift
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

import OSLog
import PixelKit
import PixelKitTestingUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DataClearingPixelsReporterTests: XCTestCase {

    private static let logger = Logger(subsystem: "DataClearingPixelsReporterTests", category: "Tests")

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
        sut.fireRetriggerPixelIfNeeded()

        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should fire on first call")
    }

    @MainActor
    func testWhenCalledTwiceWithin20SecondsThenRetriggerPixelIsFired() {
        // Given - first call sets lastFireTime
        sut.fireRetriggerPixelIfNeeded()

        // When - second call within 20 seconds
        currentTime += 10
        sut.fireRetriggerPixelIfNeeded()

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    @MainActor
    func testWhenCalledExactlyAt20SecondsThenRetriggerPixelIsFired() {
        // Given
        let startTime = currentTime!
        Self.logger.info("[👀 DIAGNOSTIC] Initial time: \(startTime, format: .fixed(precision: 17))")
        sut.fireRetriggerPixelIfNeeded()

        // When - at 20 seconds
        currentTime += 20.0
        let endTime = currentTime!
        let elapsed = endTime - startTime
        Self.logger.info("[👀 DIAGNOSTIC] After increment - currentTime: \(endTime, format: .fixed(precision: 17)), elapsed: \(elapsed, format: .fixed(precision: 17))")

        sut.fireRetriggerPixelIfNeeded()

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    @MainActor
    func testWhenCalledAfter20SecondsThenNoRetriggerPixelIsFired() {
        // Given
        sut.fireRetriggerPixelIfNeeded()

        // When - after 20 seconds
        currentTime += 21
        sut.fireRetriggerPixelIfNeeded()

        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should fire after window expires")
    }

    @MainActor
    func testWhenCalledMultipleTimesWithinWindowThenRetriggerPixelFiredEachTime() {
        // Given
        sut.fireRetriggerPixelIfNeeded()

        // When - multiple rapid calls within window
        currentTime += 5
        sut.fireRetriggerPixelIfNeeded()

        currentTime += 5
        sut.fireRetriggerPixelIfNeeded()

        currentTime += 5
        sut.fireRetriggerPixelIfNeeded()

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard),
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard),
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    // MARK: - Nil PixelFiring Tests

    @MainActor
    func testWhenPixelFiringIsNilThenNoPixelIsFiredAndNoCrash() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: nil)

        // When - should not crash
        sut.fireRetriggerPixelIfNeeded()
        sut.fireRetriggerPixelIfNeeded()

        // Then - no crash
    }
}
