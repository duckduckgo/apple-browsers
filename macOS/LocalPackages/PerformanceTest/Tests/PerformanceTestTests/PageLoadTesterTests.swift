//
//  PageLoadTesterTests.swift
//  PerformanceTestTests
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//

import XCTest
import WebKit
@testable import PerformanceTest

final class PageLoadTesterTests: XCTestCase {

    var mockWebView: MockWebView!
    var tester: PageLoadTester!

    override func setUp() {
        super.setUp()
        mockWebView = MockWebView(frame: .zero, configuration: WKWebViewConfiguration())
        tester = PageLoadTester(webView: mockWebView)
    }

    override func tearDown() {
        mockWebView = nil
        tester = nil
        super.tearDown()
    }

    // MARK: - Basic Load Tests

    func testMeasuresPageLoadTime() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        mockWebView.shouldSucceed = true
        mockWebView.loadDuration = 1.5

        // When
        let result = try await tester.measurePageLoad(url: url)

        // Then
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.metrics)
        XCTAssertEqual(result.url, url)
        XCTAssertEqual(result.metrics?.loadTime ?? 0, 1.5, accuracy: 0.1)
    }

    func testMeasuresMultipleLoads() async throws {
        // Given
        let urls = [
            URL(string: "https://example1.com")!,
            URL(string: "https://example2.com")!,
            URL(string: "https://example3.com")!
        ]
        mockWebView.shouldSucceed = true
        mockWebView.loadDuration = 1.0

        // When
        var results: [TestResult] = []
        for url in urls {
            let result = try await tester.measurePageLoad(url: url)
            results.append(result)
        }

        // Then
        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(results.allSatisfy { $0.success })
        XCTAssertEqual(mockWebView.loadedURLs, urls)
    }

    // MARK: - Timeout Tests

    func testHandlesTimeoutCorrectly() async {
        // Given
        let url = URL(string: "https://slow-site.com")!
        mockWebView.shouldTimeout = true
        mockWebView.loadDuration = 0.1 // Quick timeout for testing

        // When
        do {
            _ = try await tester.measurePageLoad(url: url, timeout: 5.0)
            XCTFail("Should have thrown timeout error")
        } catch {
            // Then
            XCTAssertTrue(error is PageLoadError)
            if case PageLoadError.timeout = error {
                // Success - correct error type
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        }
    }

    func testRespectsCustomTimeout() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        mockWebView.shouldSucceed = true
        mockWebView.loadDuration = 0.5

        // When
        let result = try await tester.measurePageLoad(url: url, timeout: 10.0)

        // Then
        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.metrics)
    }

    // MARK: - Navigation Event Tests

    func testReportsNavigationEvents() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        mockWebView.shouldSucceed = true

        var progressUpdates: [Double] = []
        tester.progressHandler = { progress in
            progressUpdates.append(progress)
        }

        // When
        _ = try await tester.measurePageLoad(url: url)

        // Then
        XCTAssertGreaterThan(progressUpdates.count, 0)
        XCTAssertTrue(progressUpdates.contains(where: { $0 > 0 && $0 < 1 }))
    }

    func testCallsCompletionOnSuccess() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        mockWebView.shouldSucceed = true

        let expectation = XCTestExpectation(description: "Completion called")
        var completedResult: TestResult?

        tester.completionHandler = { result in
            completedResult = result
            expectation.fulfill()
        }

        // When
        let result = try await tester.measurePageLoad(url: url)

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(completedResult)
        XCTAssertEqual(completedResult?.url, result.url)
    }

    // MARK: - Cancellation Tests

    func testCancellationStopsTest() async {
        // Given
        let url = URL(string: "https://example.com")!
        mockWebView.shouldSucceed = true
        mockWebView.loadDuration = 2.0 // Long enough to cancel

        // When
        let task = Task {
            try await tester.measurePageLoad(url: url)
        }

        // Cancel after short delay
        Task {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            task.cancel()
        }

        // Then
        do {
            _ = try await task.value
            XCTFail("Should have been cancelled")
        } catch {
            XCTAssertTrue(Task.isCancelled || error is CancellationError)
        }
    }

    func testCancellationCleansUpResources() async {
        // Given
        let url = URL(string: "https://example.com")!
        mockWebView.shouldSucceed = true
        mockWebView.loadDuration = 2.0

        // When
        let task = Task {
            try await tester.measurePageLoad(url: url)
        }

        task.cancel()

        // Then
        do {
            _ = try await task.value
        } catch {
            // Expected cancellation
        }

        // Verify cleanup
        XCTAssertFalse(mockWebView.isLoading)
    }

    // MARK: - Error Handling Tests

    func testErrorHandlingForInvalidURL() async {
        // Given
        let url = URL(string: "not-a-valid-url://")!
        mockWebView.shouldSucceed = false

        // When
        do {
            _ = try await tester.measurePageLoad(url: url)
            XCTFail("Should have thrown error")
        } catch {
            // Then
            XCTAssertNotNil(error)
        }
    }

    func testHandlesNetworkError() async {
        // Given
        let url = URL(string: "https://unreachable.com")!
        mockWebView.shouldSucceed = false

        // When
        do {
            _ = try await tester.measurePageLoad(url: url)
            XCTFail("Should have thrown error")
        } catch {
            // Then
            XCTAssertTrue(error is PageLoadError)
        }
    }

    // MARK: - Sequential Tests

    func testMultipleTestsRunSequentially() async throws {
        // Given
        let urls = [
            URL(string: "https://site1.com")!,
            URL(string: "https://site2.com")!
        ]
        mockWebView.shouldSucceed = true
        mockWebView.loadDuration = 0.5

        // When
        let start = Date()
        for url in urls {
            _ = try await tester.measurePageLoad(url: url)
        }
        let duration = Date().timeIntervalSince(start)

        // Then
        // Tests should run sequentially, so total time should be >= sum of load times
        XCTAssertGreaterThanOrEqual(duration, Double(urls.count) * 0.5 * 0.9) // Allow 10% variance
    }

    // MARK: - Metrics Collection Tests

    func testCollectsPerformanceMetrics() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        mockWebView.shouldSucceed = true
        mockWebView.loadDuration = 1.0

        // When
        let result = try await tester.measurePageLoad(url: url)

        // Then
        XCTAssertNotNil(result.metrics)
        XCTAssertNotNil(result.metrics?.firstContentfulPaint)
        XCTAssertNotNil(result.metrics?.largestContentfulPaint)
        XCTAssertNotNil(result.metrics?.timeToFirstByte)

        // Verify metrics are reasonable
        if let metrics = result.metrics {
            XCTAssertGreaterThan(metrics.loadTime, 0)
            XCTAssertLessThanOrEqual(metrics.firstContentfulPaint ?? 0, metrics.loadTime * 1000)
            XCTAssertLessThanOrEqual(metrics.largestContentfulPaint ?? 0, metrics.loadTime * 1000)
        }
    }

    func testRetriesOnTransientFailure() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        var attemptCount = 0

        // Fail first attempt, succeed second
        tester.beforeLoadHandler = {
            attemptCount += 1
            self.mockWebView.shouldSucceed = attemptCount > 1
        }

        // When
        let result = try await tester.measurePageLoad(url: url, maxRetries: 2)

        // Then
        XCTAssertTrue(result.success)
        XCTAssertEqual(attemptCount, 2)
    }
}

// MARK: - Error Types for Testing

enum PageLoadError: LocalizedError {
    case timeout(duration: TimeInterval)
    case networkError(message: String)
    case invalidURL
    case cancelled

    var errorDescription: String? {
        switch self {
        case .timeout(let duration):
            return "Page load timed out after \(duration) seconds"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidURL:
            return "Invalid URL"
        case .cancelled:
            return "Page load was cancelled"
        }
    }
}
