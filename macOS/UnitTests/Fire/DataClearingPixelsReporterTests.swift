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

import PixelKit
import PixelKitTestingUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class DataClearingPixelsReporterTests: XCTestCase {

    private var mockPixelFiring: PixelKitMock!
    private var sut: DataClearingPixelsReporter!
    private var currentDate: Date!

    override func setUp() {
        super.setUp()
        mockPixelFiring = PixelKitMock()
        currentDate = Date()
        sut = DataClearingPixelsReporter(
            pixelFiring: mockPixelFiring,
            endDateProvider: { [weak self] in self?.currentDate ?? Date() }
        )
    }

    override func tearDown() {
        mockPixelFiring = nil
        sut = nil
        currentDate = nil
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
        currentDate = currentDate.addingTimeInterval(10)
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
        sut.fireRetriggerPixelIfNeeded()

        // When - exactly at 20 seconds (edge case, <= condition)
        currentDate = currentDate.addingTimeInterval(20)
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
        currentDate = currentDate.addingTimeInterval(21)
        sut.fireRetriggerPixelIfNeeded()

        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should fire after window expires")
    }

    @MainActor
    func testWhenCalledMultipleTimesWithinWindowThenRetriggerPixelFiredEachTime() {
        // Given
        sut.fireRetriggerPixelIfNeeded()

        // When - multiple rapid calls within window
        currentDate = currentDate.addingTimeInterval(5)
        sut.fireRetriggerPixelIfNeeded()

        currentDate = currentDate.addingTimeInterval(5)
        sut.fireRetriggerPixelIfNeeded()

        currentDate = currentDate.addingTimeInterval(5)
        sut.fireRetriggerPixelIfNeeded()

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard),
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard),
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    // MARK: - fireErrorPixel Tests

    func testWhenFireErrorPixelCalledThenPixelIsFired() {
        // Given
        let testError = NSError(domain: "test", code: 123)

        // When
        sut.fireErrorPixel(.burnWebCacheError(testError))

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.burnWebCacheError(testError), frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    // MARK: - fireResiduePixel Tests

    func testWhenFireResiduePixelCalledThenPixelIsFired() {
        // When
        sut.fireResiduePixel(.burnHistoryHasResidue)

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.burnHistoryHasResidue, frequency: .standard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    // MARK: - fireResiduePixelIfNeeded Tests

    func testWhenResidueCheckReturnsTrueThenPixelIsFired() {
        // When
        sut.fireResiduePixelIfNeeded(.burnVisitsHasResidue) { true }

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.burnVisitsHasResidue, frequency: .standard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    func testWhenResidueCheckReturnsFalseThenNoPixelIsFired() {
        // When
        sut.fireResiduePixelIfNeeded(.burnVisitsHasResidue) { false }

        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty)
    }

    // MARK: - fireDurationPixel Tests

    func testWhenFireDurationPixelCalledThenPixelIsFiredWithCorrectDuration() {
        // Given
        let startTime = currentDate!
        currentDate = currentDate.addingTimeInterval(1.5) // 1.5 seconds = 1500ms

        // When
        sut.fireDurationPixel(DataClearingPixels.burnWebCacheDuration, from: startTime)

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1)
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.frequency, .dailyAndStandard)

        // Verify duration parameter is correct (1500ms)
        if case .burnWebCacheDuration(let duration) = mockPixelFiring.actualFireCalls.first?.pixel as? DataClearingPixels {
            XCTAssertEqual(duration, 1500)
        } else {
            XCTFail("Expected burnWebCacheDuration pixel")
        }
    }

    func testWhenFireDurationPixelWithEntityCalledThenPixelIsFired() {
        // Given
        let startTime = currentDate!
        currentDate = currentDate.addingTimeInterval(2.0) // 2 seconds = 2000ms

        // When
        sut.fireDurationPixel(DataClearingPixels.burnHistoryDuration, from: startTime, entity: "history")

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1)

        if case .burnHistoryDuration(let entity, let duration) = mockPixelFiring.actualFireCalls.first?.pixel as? DataClearingPixels {
            XCTAssertEqual(entity, "history")
            XCTAssertEqual(duration, 2000)
        } else {
            XCTFail("Expected burnHistoryDuration pixel")
        }
    }

    // MARK: - Nil PixelFiring Tests

    @MainActor
    func testWhenPixelFiringIsNilThenNoPixelIsFiredAndNoCrash() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: nil)

        // When - should not crash
        sut.fireRetriggerPixelIfNeeded()
        sut.fireRetriggerPixelIfNeeded()
        sut.fireErrorPixel(.burnWebCacheError(NSError(domain: "test", code: 1)))
        sut.fireResiduePixel(.burnHistoryHasResidue)

        // Then - no crash
    }
}
