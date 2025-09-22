//
//  TestResultTests.swift
//  PerformanceTestTests
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//

import XCTest
@testable import PerformanceTest

final class TestResultTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitializesWithSuccess() {
        // Given
        let url = URL(string: "https://example.com")!
        let metrics = PerformanceMetrics(loadTime: 1.5)
        let timestamp = Date()

        // When
        let result = TestResult(
            url: url,
            metrics: metrics,
            success: true,
            error: nil,
            timestamp: timestamp
        )

        // Then
        XCTAssertEqual(result.url, url)
        XCTAssertEqual(result.metrics, metrics)
        XCTAssertTrue(result.success)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.timestamp, timestamp)
    }

    func testInitializesWithFailure() {
        // Given
        let url = URL(string: "https://example.com")!
        let error = TestError.timeout(duration: 30.0)
        let timestamp = Date()

        // When
        let result = TestResult(
            url: url,
            metrics: nil,
            success: false,
            error: error,
            timestamp: timestamp
        )

        // Then
        XCTAssertEqual(result.url, url)
        XCTAssertNil(result.metrics)
        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.timestamp, timestamp)
    }

    // MARK: - Duration Calculation Tests

    func testCalculatesDuration() {
        // Given
        let url = URL(string: "https://example.com")!
        let startTime = Date()
        let endTime = startTime.addingTimeInterval(2.5)
        let metrics = PerformanceMetrics(loadTime: 2.5)

        // When
        let result = TestResult(
            url: url,
            metrics: metrics,
            success: true,
            error: nil,
            timestamp: startTime,
            endTime: endTime
        )

        // Then
        XCTAssertEqual(result.duration ?? 0, 2.5, accuracy: 0.01)
    }

    func testDurationIsNilForIncompleteTest() {
        // Given
        let url = URL(string: "https://example.com")!
        let timestamp = Date()

        // When
        let result = TestResult(
            url: url,
            metrics: nil,
            success: false,
            error: TestError.cancelled,
            timestamp: timestamp
        )

        // Then
        XCTAssertNil(result.duration)
    }

    // MARK: - Display Properties Tests

    func testDisplayStatus() {
        // Given
        let successResult = TestResult(
            url: URL(string: "https://example.com")!,
            metrics: PerformanceMetrics(loadTime: 1.0),
            success: true,
            error: nil,
            timestamp: Date()
        )

        let failureResult = TestResult(
            url: URL(string: "https://example.com")!,
            metrics: nil,
            success: false,
            error: TestError.timeout(duration: 30.0),
            timestamp: Date()
        )

        // Then
        XCTAssertEqual(successResult.displayStatus, "✅ Success")
        XCTAssertEqual(failureResult.displayStatus, "❌ Failed")
    }

    func testDisplayDuration() {
        // Given
        let resultWithMetrics = TestResult(
            url: URL(string: "https://example.com")!,
            metrics: PerformanceMetrics(loadTime: 2.5),
            success: true,
            error: nil,
            timestamp: Date()
        )

        let resultWithoutMetrics = TestResult(
            url: URL(string: "https://example.com")!,
            metrics: nil,
            success: false,
            error: TestError.timeout(duration: 30.0),
            timestamp: Date()
        )

        // Then
        XCTAssertEqual(resultWithMetrics.displayDuration, "2.50s")
        XCTAssertEqual(resultWithoutMetrics.displayDuration, "Failed")
    }

    func testSiteName() {
        // Given
        let result = TestResult(
            url: URL(string: "https://www.example.com/page")!,
            metrics: PerformanceMetrics(loadTime: 1.0),
            success: true,
            error: nil,
            timestamp: Date()
        )

        // Then
        XCTAssertEqual(result.siteName, "example.com")
    }

    // MARK: - Codable Tests

    func testSerializesToJSON() throws {
        // Given
        let result = TestResult(
            url: URL(string: "https://example.com")!,
            metrics: PerformanceMetrics(loadTime: 1.5),
            success: true,
            error: nil,
            timestamp: Date()
        )

        // When
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(result)

        // Then
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data.count, 0)

        // Verify JSON structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["url"])
        XCTAssertNotNil(json?["success"])
        XCTAssertNotNil(json?["timestamp"])
    }

    func testDeserializesFromJSON() throws {
        // Given
        let originalResult = TestResult(
            url: URL(string: "https://example.com")!,
            metrics: PerformanceMetrics(loadTime: 1.5, firstContentfulPaint: 0.8),
            success: true,
            error: nil,
            timestamp: Date()
        )

        // When
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(originalResult)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedResult = try decoder.decode(TestResult.self, from: data)

        // Then
        XCTAssertEqual(originalResult.url, decodedResult.url)
        XCTAssertEqual(originalResult.success, decodedResult.success)
        XCTAssertEqual(originalResult.metrics, decodedResult.metrics)
    }

    // MARK: - Error Handling Tests

    func testHandlesVariousErrors() {
        // Given
        let timeoutError = TestError.timeout(duration: 30.0)

        let timeoutResult = TestResult(
            url: URL(string: "https://example.com")!,
            metrics: nil,
            success: false,
            error: timeoutError,
            timestamp: Date()
        )

        // Then
        XCTAssertEqual(timeoutResult.error?.localizedDescription, "Test timed out after 30.0 seconds")
    }

    // MARK: - Equatable Tests

    func testEquatableConformance() {
        // Given
        let timestamp = Date()
        let url = URL(string: "https://example.com")!
        let metrics = PerformanceMetrics(loadTime: 1.5)

        let result1 = TestResult(
            url: url,
            metrics: metrics,
            success: true,
            error: nil,
            timestamp: timestamp
        )

        let result2 = TestResult(
            url: url,
            metrics: metrics,
            success: true,
            error: nil,
            timestamp: timestamp
        )

        let result3 = TestResult(
            url: URL(string: "https://different.com")!,
            metrics: metrics,
            success: true,
            error: nil,
            timestamp: timestamp
        )

        // Then
        XCTAssertEqual(result1, result2)
        XCTAssertNotEqual(result1, result3)
    }
}

// MARK: - Test Error Definition (for testing purposes)

