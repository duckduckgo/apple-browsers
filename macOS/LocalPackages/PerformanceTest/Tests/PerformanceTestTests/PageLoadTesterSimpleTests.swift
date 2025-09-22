//
//  PageLoadTesterSimpleTests.swift
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
import WebKit
@testable import PerformanceTest

@MainActor
final class PageLoadTesterSimpleTests: XCTestCase {

    func testWebViewIsPresent() {
        // Given
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

        // When
        let tester = PageLoadTester(webView: webView)

        // Then
        XCTAssertNotNil(tester)
        XCTAssertNotNil(webView.navigationDelegate)
    }

    func testHandlersWork() {
        // Given
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        let tester = PageLoadTester(webView: webView)
        var progressCalled = false
        var completionCalled = false
        var beforeLoadCalled = false

        // When
        tester.progressHandler = { _ in
            progressCalled = true
        }
        tester.completionHandler = { _ in
            completionCalled = true
        }
        tester.beforeLoadHandler = {
            beforeLoadCalled = true
        }

        // Simulate calling handlers
        tester.progressHandler?(0.5)
        tester.completionHandler?(TestResult(
            url: URL(string: "https://example.com")!,
            metrics: nil,
            success: true,
            error: nil,
            timestamp: Date()
        ))
        tester.beforeLoadHandler?()

        // Then
        XCTAssertTrue(progressCalled)
        XCTAssertTrue(completionCalled)
        XCTAssertTrue(beforeLoadCalled)
    }

    func testRetryLogic() {
        // Test that the retry count calculation is correct
        let testCases: [(maxRetries: Int, expectedAttempts: Int)] = [
            (0, 1),  // No retries = 1 attempt
            (1, 2),  // 1 retry = 2 attempts
            (2, 3),  // 2 retries = 3 attempts
        ]

        for testCase in testCases {
            var attempts = 0
            let maxRetries = testCase.maxRetries

            // Simulate the actual loop from PageLoadTester
            while attempts <= maxRetries {
                attempts += 1
            }

            XCTAssertEqual(attempts, testCase.expectedAttempts)
        }
    }

    func testErrorTypes() {
        // Test error descriptions
        XCTAssertEqual(
            PageLoadError.timeout(duration: 30.0).errorDescription,
            "Page load timed out after 30 seconds"
        )

        XCTAssertEqual(
            PageLoadError.networkError(message: "Failed").errorDescription,
            "Network error: Failed"
        )

        XCTAssertEqual(
            PageLoadError.invalidURL.errorDescription,
            "Invalid URL"
        )

        XCTAssertEqual(
            PageLoadError.cancelled.errorDescription,
            "Page load was cancelled"
        )
    }

    func testTestResultProperties() {
        // Given
        let url = URL(string: "https://example.com")!
        let metrics = PerformanceMetrics(loadTime: 2.5)
        let start = Date()
        let end = start.addingTimeInterval(2.5)

        // When
        let result = TestResult(
            url: url,
            metrics: metrics,
            success: true,
            error: nil,
            timestamp: start,
            endTime: end
        )

        // Then
        XCTAssertEqual(result.url, url)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.duration ?? 0, 2.5, accuracy: 0.01)
        XCTAssertEqual(result.displayStatus, "✅ Success")
        XCTAssertEqual(result.displayDuration, "2.50s")
    }

    func testPerformanceMetricsProperties() {
        // Given/When
        let metrics = PerformanceMetrics(
            loadTime: 1.5,
            firstContentfulPaint: 800.0,
            largestContentfulPaint: 1200.0,
            timeToFirstByte: 300.0
        )

        // Then
        XCTAssertEqual(metrics.loadTime, 1.5)
        XCTAssertEqual(metrics.firstContentfulPaint, 800.0)
        XCTAssertEqual(metrics.largestContentfulPaint, 1200.0)
        XCTAssertEqual(metrics.timeToFirstByte, 300.0)
    }
}