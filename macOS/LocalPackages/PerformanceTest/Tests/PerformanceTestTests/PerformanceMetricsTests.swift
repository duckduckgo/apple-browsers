//
//  PerformanceMetricsTests.swift
//  PerformanceTestTests
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//

import XCTest
@testable import PerformanceTest

final class PerformanceMetricsTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitializesWithLoadTime() {
        // Given
        let loadTime: TimeInterval = 2.5

        // When
        let metrics = PerformanceMetrics(loadTime: loadTime)

        // Then
        XCTAssertEqual(metrics.loadTime, loadTime, "Load time should be set correctly")
    }

    func testInitializesWithAllMetrics() {
        // Given
        let loadTime: TimeInterval = 1.5
        let firstContentfulPaint: TimeInterval = 0.8
        let largestContentfulPaint: TimeInterval = 1.2
        let timeToFirstByte: TimeInterval = 0.3

        // When
        let metrics = PerformanceMetrics(
            loadTime: loadTime,
            firstContentfulPaint: firstContentfulPaint,
            largestContentfulPaint: largestContentfulPaint,
            timeToFirstByte: timeToFirstByte
        )

        // Then
        XCTAssertEqual(metrics.loadTime, loadTime)
        XCTAssertEqual(metrics.firstContentfulPaint, firstContentfulPaint)
        XCTAssertEqual(metrics.largestContentfulPaint, largestContentfulPaint)
        XCTAssertEqual(metrics.timeToFirstByte, timeToFirstByte)
    }

    // MARK: - Performance Score Tests

    func testCalculatesPerformanceScoreForFastLoad() {
        // Given
        let metrics = PerformanceMetrics(loadTime: 0.5) // Very fast

        // When
        let score = metrics.performanceScore

        // Then
        XCTAssertGreaterThanOrEqual(score, 90, "Fast load should have high score")
        XCTAssertLessThanOrEqual(score, 100, "Score should not exceed 100")
    }

    func testCalculatesPerformanceScoreForAverageLoad() {
        // Given
        let metrics = PerformanceMetrics(loadTime: 2.0) // Average

        // When
        let score = metrics.performanceScore

        // Then
        XCTAssertGreaterThanOrEqual(score, 50, "Average load should have medium score")
        XCTAssertLessThan(score, 90, "Average load should not have high score")
    }

    func testCalculatesPerformanceScoreForSlowLoad() {
        // Given
        let metrics = PerformanceMetrics(loadTime: 5.0) // Slow

        // When
        let score = metrics.performanceScore

        // Then
        XCTAssertLessThan(score, 50, "Slow load should have low score")
        XCTAssertGreaterThanOrEqual(score, 0, "Score should not be negative")
    }

    // MARK: - Display Formatting Tests

    func testFormatsDisplayTimeForShortDuration() {
        // Given
        let metrics = PerformanceMetrics(loadTime: 0.75)

        // When
        let displayTime = metrics.displayTime

        // Then
        XCTAssertEqual(displayTime, "0.75s", "Should format with 2 decimal places and 's' suffix")
    }

    func testFormatsDisplayTimeForLongDuration() {
        // Given
        let metrics = PerformanceMetrics(loadTime: 10.5)

        // When
        let displayTime = metrics.displayTime

        // Then
        XCTAssertEqual(displayTime, "10.50s", "Should format with 2 decimal places")
    }

    func testFormatsDisplayTimeForVeryShortDuration() {
        // Given
        let metrics = PerformanceMetrics(loadTime: 0.123)

        // When
        let displayTime = metrics.displayTime

        // Then
        XCTAssertEqual(displayTime, "123ms", "Should use milliseconds for durations under 1 second")
    }

    // MARK: - Performance Grade Tests

    func testPerformanceGradeA() {
        // Given
        let metrics = PerformanceMetrics(loadTime: 0.5)

        // When
        let grade = metrics.performanceGrade

        // Then
        XCTAssertEqual(grade, "A", "Score >= 90 should be grade A")
    }

    func testPerformanceGradeB() {
        // Given
        let metrics = PerformanceMetrics(loadTime: 1.5)

        // When
        let grade = metrics.performanceGrade

        // Then
        XCTAssertEqual(grade, "B", "Score 70-89 should be grade B")
    }

    func testPerformanceGradeC() {
        // Given
        let metrics = PerformanceMetrics(loadTime: 2.5)

        // When
        let grade = metrics.performanceGrade

        // Then
        XCTAssertEqual(grade, "C", "Score 50-69 should be grade C")
    }

    func testPerformanceGradeF() {
        // Given
        let metrics = PerformanceMetrics(loadTime: 10.0)

        // When
        let grade = metrics.performanceGrade

        // Then
        XCTAssertEqual(grade, "F", "Score < 50 should be grade F")
    }

    // MARK: - Invalid Metrics Tests

    func testHandlesNegativeLoadTime() {
        // Given
        let metrics = PerformanceMetrics(loadTime: -1.0)

        // When
        let score = metrics.performanceScore

        // Then
        XCTAssertEqual(score, 0, "Negative load time should result in score of 0")
    }

    func testHandlesZeroLoadTime() {
        // Given
        let metrics = PerformanceMetrics(loadTime: 0.0)

        // When
        let score = metrics.performanceScore

        // Then
        XCTAssertEqual(score, 100, "Zero load time should result in perfect score")
    }

    // MARK: - Comparison Tests

    func testComparesMetrics() {
        // Given
        let fastMetrics = PerformanceMetrics(loadTime: 1.0)
        let slowMetrics = PerformanceMetrics(loadTime: 3.0)

        // When
        let comparison = fastMetrics.isFasterThan(slowMetrics)

        // Then
        XCTAssertTrue(comparison, "Fast metrics should be faster than slow metrics")
    }

    func testEquatableConformance() {
        // Given
        let metrics1 = PerformanceMetrics(loadTime: 1.5, firstContentfulPaint: 0.5)
        let metrics2 = PerformanceMetrics(loadTime: 1.5, firstContentfulPaint: 0.5)
        let metrics3 = PerformanceMetrics(loadTime: 2.0, firstContentfulPaint: 0.5)

        // Then
        XCTAssertEqual(metrics1, metrics2, "Identical metrics should be equal")
        XCTAssertNotEqual(metrics1, metrics3, "Different metrics should not be equal")
    }

    // MARK: - Codable Tests

    func testEncodingAndDecoding() throws {
        // Given
        let originalMetrics = PerformanceMetrics(
            loadTime: 2.5,
            firstContentfulPaint: 1.2,
            largestContentfulPaint: 1.8,
            timeToFirstByte: 0.3
        )

        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalMetrics)

        let decoder = JSONDecoder()
        let decodedMetrics = try decoder.decode(PerformanceMetrics.self, from: data)

        // Then
        XCTAssertEqual(originalMetrics, decodedMetrics, "Metrics should survive encoding/decoding")
    }
}
