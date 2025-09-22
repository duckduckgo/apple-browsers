//
//  ModelsTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import PerformanceTest

final class ModelsTests: XCTestCase {

    // MARK: - PerformanceMetrics Tests

    func testPerformanceMetricsInitialization() {
        // Given
        let loadTime = 2.5
        let fcp = 1.2
        let lcp = 1.8
        let ttfb = 0.3

        // When
        let metrics = PerformanceMetrics(
            loadTime: loadTime,
            firstContentfulPaint: fcp,
            largestContentfulPaint: lcp,
            timeToFirstByte: ttfb
        )

        // Then
        XCTAssertEqual(metrics.loadTime, loadTime)
        XCTAssertEqual(metrics.firstContentfulPaint, fcp)
        XCTAssertEqual(metrics.largestContentfulPaint, lcp)
        XCTAssertEqual(metrics.timeToFirstByte, ttfb)
    }

    func testPerformanceMetricsWithNilValues() {
        // Given/When
        let metrics = PerformanceMetrics(loadTime: 1.0)

        // Then
        XCTAssertEqual(metrics.loadTime, 1.0)
        XCTAssertNil(metrics.firstContentfulPaint)
        XCTAssertNil(metrics.largestContentfulPaint)
        XCTAssertNil(metrics.timeToFirstByte)
    }

    // MARK: - TestResult Tests

    func testTestResultSuccess() {
        // Given
        let url = URL(string: "https://example.com")!
        let metrics = PerformanceMetrics(loadTime: 2.0)
        let startTime = Date()
        let endTime = Date().addingTimeInterval(2.0)

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
        XCTAssertEqual(result.url, url)
        XCTAssertNotNil(result.metrics)
        XCTAssertTrue(result.success)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.timestamp, startTime)
        XCTAssertEqual(result.endTime, endTime)
    }

    func testTestResultFailure() {
        // Given
        let url = URL(string: "https://example.com")!
        let error = TestError.networkError(message: "Connection failed")
        let startTime = Date()
        let endTime = Date()

        // When
        let result = TestResult(
            url: url,
            metrics: nil,
            success: false,
            error: error,
            timestamp: startTime,
            endTime: endTime
        )

        // Then
        XCTAssertEqual(result.url, url)
        XCTAssertNil(result.metrics)
        XCTAssertFalse(result.success)
        XCTAssertNotNil(result.error)
        XCTAssertEqual(result.timestamp, startTime)
        XCTAssertEqual(result.endTime, endTime)
    }

    // MARK: - PageLoadError Tests

    func testPageLoadErrorTimeout() {
        // Given
        let duration: TimeInterval = 30.0
        let error = PageLoadError.timeout(duration: duration)

        // Then
        XCTAssertEqual(error.errorDescription, "Page load timed out after 30 seconds")
    }

    func testPageLoadErrorNetwork() {
        // Given
        let message = "Host not found"
        let error = PageLoadError.networkError(message: message)

        // Then
        XCTAssertEqual(error.errorDescription, "Network error: Host not found")
    }

    func testPageLoadErrorInvalidURL() {
        // Given
        let error = PageLoadError.invalidURL

        // Then
        XCTAssertEqual(error.errorDescription, "Invalid URL")
    }

    func testPageLoadErrorCancelled() {
        // Given
        let error = PageLoadError.cancelled

        // Then
        XCTAssertEqual(error.errorDescription, "Page load was cancelled")
    }

    // MARK: - TestError Tests

    func testTestErrorTimeout() {
        // Given
        let duration: TimeInterval = 15.0
        let error = TestError.timeout(duration: duration)

        // Then
        XCTAssertEqual(error.localizedDescription, "Test timed out after 15.0 seconds")
    }

    func testTestErrorNetworkError() {
        // Given
        let message = "DNS lookup failed"
        let error = TestError.networkError(message: message)

        // Then
        XCTAssertEqual(error.localizedDescription, "Network error: DNS lookup failed")
    }

    func testTestErrorMetricsUnavailable() {
        // Given
        let error = TestError.metricsUnavailable

        // Then
        XCTAssertEqual(error.localizedDescription, "Performance metrics unavailable")
    }

    func testTestErrorOtherError() {
        // Given
        let message = "Unexpected error occurred"
        let error = TestError.otherError(message: message)

        // Then
        XCTAssertEqual(error.localizedDescription, "Unexpected error occurred")
    }
}