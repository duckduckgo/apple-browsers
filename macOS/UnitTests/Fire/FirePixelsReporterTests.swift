//
//  FirePixelsReporterTests.swift
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

    override func setUp() {
        super.setUp()
        mockPixelFiring = PixelKitMock()
    }

    override func tearDown() {
        mockPixelFiring = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - fireRetriggerPixelIfNeeded Tests

    @MainActor
    func testWhenFirstFireThenNoRetriggerPixelIsFired() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: mockPixelFiring)
        let baseDate = Date()

        // When
        sut.fireRetriggerPixelIfNeeded(dateProvider: { baseDate })

        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should fire on first call")
    }

    @MainActor
    func testWhenCalledTwiceWithin20SecondsThenRetriggerPixelIsFired() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: mockPixelFiring)
        let baseDate = Date()
        sut.fireRetriggerPixelIfNeeded(dateProvider: { baseDate })

        // When - second call within 20 seconds
        let secondCallDate = baseDate.addingTimeInterval(10)
        sut.fireRetriggerPixelIfNeeded(dateProvider: { secondCallDate })

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    @MainActor
    func testWhenCalledExactlyAt20SecondsThenRetriggerPixelIsFired() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: mockPixelFiring)
        let baseDate = Date()
        sut.fireRetriggerPixelIfNeeded(dateProvider: { baseDate })

        // When - exactly at 20 seconds (edge case, <= condition)
        let secondCallDate = baseDate.addingTimeInterval(20)
        sut.fireRetriggerPixelIfNeeded(dateProvider: { secondCallDate })

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    @MainActor
    func testWhenCalledAfter20SecondsThenNoRetriggerPixelIsFired() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: mockPixelFiring)
        let baseDate = Date()
        sut.fireRetriggerPixelIfNeeded(dateProvider: { baseDate })

        // When - after 20 seconds
        let secondCallDate = baseDate.addingTimeInterval(21)
        sut.fireRetriggerPixelIfNeeded(dateProvider: { secondCallDate })

        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty, "No pixel should fire after window expires")
    }

    @MainActor
    func testWhenCalledMultipleTimesWithinWindowThenRetriggerPixelFiredEachTime() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: mockPixelFiring)
        let baseDate = Date()
        sut.fireRetriggerPixelIfNeeded(dateProvider: { baseDate })

        // When - multiple rapid calls within window
        sut.fireRetriggerPixelIfNeeded(dateProvider: { baseDate.addingTimeInterval(5) })
        sut.fireRetriggerPixelIfNeeded(dateProvider: { baseDate.addingTimeInterval(10) })
        sut.fireRetriggerPixelIfNeeded(dateProvider: { baseDate.addingTimeInterval(15) })

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard),
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard),
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    @MainActor
    func testWhenWindowExpiresAndNewSequenceStartsThenNoPixelOnFirstCallOfNewSequence() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: mockPixelFiring)
        let baseDate = Date()
        
        // First sequence
        sut.fireRetriggerPixelIfNeeded(dateProvider: { baseDate })
        sut.fireRetriggerPixelIfNeeded(dateProvider: { baseDate.addingTimeInterval(10) }) // fires pixel
        
        // Window expires
        let expiredDate = baseDate.addingTimeInterval(35)
        sut.fireRetriggerPixelIfNeeded(dateProvider: { expiredDate }) // no pixel (> 20s from last)

        // Then - only one pixel fired (from 10s call)
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.retriggerIn20s, frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    // MARK: - fireErrorPixel Tests

    func testWhenFireErrorPixelCalledThenPixelIsFired() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: mockPixelFiring)
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
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: mockPixelFiring)

        // When
        sut.fireResiduePixel(.burnHistoryHasResidue)

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.burnHistoryHasResidue, frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    // MARK: - fireResiduePixelIfNeeded Tests

    func testWhenResidueCheckReturnsTrueThenPixelIsFired() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: mockPixelFiring)

        // When
        sut.fireResiduePixelIfNeeded(.burnVisitsHasResidue) { true }

        // Then
        mockPixelFiring.expectedFireCalls = [
            .init(pixel: DataClearingPixels.burnVisitsHasResidue, frequency: .dailyAndStandard)
        ]
        mockPixelFiring.verifyExpectations(file: #file, line: #line)
    }

    func testWhenResidueCheckReturnsFalseThenNoPixelIsFired() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: mockPixelFiring)

        // When
        sut.fireResiduePixelIfNeeded(.burnVisitsHasResidue) { false }

        // Then
        XCTAssertTrue(mockPixelFiring.actualFireCalls.isEmpty)
    }

    // MARK: - fireDurationPixel Tests

    func testWhenFireDurationPixelCalledThenPixelIsFiredWithCorrectDuration() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: mockPixelFiring)
        let startTime = Date()
        
        // When - Note: This will use Date() internally, so duration will be ~0
        sut.fireDurationPixel(DataClearingPixels.burnWebCacheDuration, from: startTime)

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1)
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.frequency, .dailyAndStandard)
    }

    func testWhenFireDurationPixelWithEntityCalledThenPixelIsFired() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: mockPixelFiring)
        let startTime = Date()

        // When
        sut.fireDurationPixel(DataClearingPixels.burnHistoryDuration, from: startTime, entity: "history")

        // Then
        XCTAssertEqual(mockPixelFiring.actualFireCalls.count, 1)
        XCTAssertEqual(mockPixelFiring.actualFireCalls.first?.frequency, .dailyAndStandard)
    }

    // MARK: - Nil PixelFiring

    @MainActor
    func testWhenPixelFiringIsNilThenNoPixelIsFiredAndNoCrash() {
        // Given
        sut = DataClearingPixelsReporter(pixelFiring: nil)

        // When - should not crash
        sut.fireRetriggerPixelIfNeeded(dateProvider: { Date() })
        sut.fireRetriggerPixelIfNeeded(dateProvider: { Date() })
        sut.fireErrorPixel(.burnWebCacheError(NSError(domain: "test", code: 1)))
        sut.fireResiduePixel(.burnHistoryHasResidue)

        // Then - nothing happens
    }
}
