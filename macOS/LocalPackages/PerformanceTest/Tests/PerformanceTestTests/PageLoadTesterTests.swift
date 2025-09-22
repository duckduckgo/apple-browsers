//
//  PageLoadTesterTests.swift
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
final class PageLoadTesterTests: XCTestCase {

    // MARK: - Properties

    private var webView: WKWebView!
    private var tester: PageLoadTester!
    private var navigationDelegate: MockNavigationDelegate!

    // MARK: - Setup/Teardown

    override func setUp() async throws {
        try await super.setUp()

        // Create web view with test configuration
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)

        // Create tester
        tester = PageLoadTester(webView: webView)

        // Create mock delegate to capture navigation
        navigationDelegate = MockNavigationDelegate()
    }

    override func tearDown() async throws {
        webView = nil
        tester = nil
        navigationDelegate = nil
        try await super.tearDown()
    }

    // MARK: - Tests

    func testSuccessfulPageLoad() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        let expectation = XCTestExpectation(description: "Page load completes")

        tester.completionHandler = { result in
            // Then
            XCTAssertTrue(result.success)
            XCTAssertNil(result.error)
            XCTAssertEqual(result.url, url)
            XCTAssertNotNil(result.metrics)
            XCTAssertGreaterThan(result.metrics?.loadTime ?? 0, 0)
            expectation.fulfill()
        }

        // When
        Task {
            do {
                _ = try await tester.measurePageLoad(url: url, timeout: 30.0, maxRetries: 0)
            } catch {
                XCTFail("Page load should not throw: \(error)")
            }
        }

        await fulfillment(of: [expectation], timeout: 35.0)
    }

    func testTimeoutHandling() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        let shortTimeout: TimeInterval = 0.1

        // Override navigation to never complete
        webView.navigationDelegate = navigationDelegate
        navigationDelegate.shouldNeverComplete = true

        // When/Then
        do {
            _ = try await tester.measurePageLoad(url: url, timeout: shortTimeout, maxRetries: 0)
            XCTFail("Should have thrown timeout error")
        } catch let error as PageLoadError {
            switch error {
            case .timeout(let duration):
                XCTAssertEqual(duration, shortTimeout)
            default:
                XCTFail("Expected timeout error, got: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRetryLogic() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        var attemptCount = 0

        tester.beforeLoadHandler = {
            attemptCount += 1
        }

        // When
        do {
            _ = try await tester.measurePageLoad(url: url, timeout: 0.1, maxRetries: 2)
        } catch {
            // Expected to fail
        }

        // Then - with maxRetries: 2, should attempt 3 times total (initial + 2 retries)
        XCTAssertEqual(attemptCount, 3)
    }

    func testInvalidURLHandling() async throws {
        // Given - create an invalid URL scenario by setting nil URL internally
        let url = URL(string: "https://invalid.example.com")!
        let expectation = XCTestExpectation(description: "Error handler called")

        tester.completionHandler = { result in
            // Then
            XCTAssertFalse(result.success)
            XCTAssertNotNil(result.error)
            expectation.fulfill()
        }

        // Simulate navigation failure
        webView.navigationDelegate = navigationDelegate
        navigationDelegate.shouldFailImmediately = true
        navigationDelegate.errorToReturn = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)

        // When
        Task {
            do {
                _ = try await tester.measurePageLoad(url: url, timeout: 30.0, maxRetries: 0)
            } catch {
                // Expected
            }
        }

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testProgressCallbacks() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        var progressValues: [Double] = []
        let progressExpectation = XCTestExpectation(description: "Progress callbacks")

        tester.progressHandler = { progress in
            progressValues.append(progress)
            if progress == 1.0 {
                progressExpectation.fulfill()
            }
        }

        // When
        Task {
            do {
                _ = try await tester.measurePageLoad(url: url, timeout: 30.0, maxRetries: 0)
            } catch {
                // Handle error
            }
        }

        await fulfillment(of: [progressExpectation], timeout: 35.0)

        // Then
        XCTAssertTrue(progressValues.contains(0.1)) // didStartProvisionalNavigation
        XCTAssertTrue(progressValues.contains(0.3)) // didCommit
        XCTAssertTrue(progressValues.contains(0.9)) // didFinish
        XCTAssertTrue(progressValues.contains(1.0)) // Complete
    }

    func testCancellationHandling() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        let task = Task {
            try await tester.measurePageLoad(url: url, timeout: 30.0, maxRetries: 0)
        }

        // When - cancel immediately
        task.cancel()

        // Then
        do {
            _ = try await task.value
            XCTFail("Should have been cancelled")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testNetworkErrorHandling() async throws {
        // Given
        let url = URL(string: "https://unreachable.example.com")!

        // Simulate network error
        webView.navigationDelegate = navigationDelegate
        navigationDelegate.shouldFailImmediately = true
        navigationDelegate.errorToReturn = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)

        // When/Then
        do {
            _ = try await tester.measurePageLoad(url: url, timeout: 30.0, maxRetries: 0)
            XCTFail("Should have thrown network error")
        } catch let error as PageLoadError {
            switch error {
            case .networkError(let message):
                XCTAssertFalse(message.isEmpty)
            default:
                XCTFail("Expected network error, got: \(error)")
            }
        }
    }

    func testBeforeLoadHandlerCalled() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        var handlerCalled = false
        let expectation = XCTestExpectation(description: "Handler called")

        tester.beforeLoadHandler = {
            handlerCalled = true
            expectation.fulfill()
        }

        // When
        Task {
            do {
                _ = try await tester.measurePageLoad(url: url, timeout: 30.0, maxRetries: 0)
            } catch {
                // Handle error
            }
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        // Then
        XCTAssertTrue(handlerCalled)
    }

    func testMetricsCollection() async throws {
        // Given
        let url = URL(string: "https://example.com")!
        let expectation = XCTestExpectation(description: "Metrics collected")

        tester.completionHandler = { result in
            // Then
            XCTAssertNotNil(result.metrics)
            if let metrics = result.metrics {
                XCTAssertGreaterThanOrEqual(metrics.loadTime, 0)
                // Other metrics may be nil depending on JavaScript execution
            }
            expectation.fulfill()
        }

        // When
        Task {
            do {
                _ = try await tester.measurePageLoad(url: url, timeout: 30.0, maxRetries: 0)
            } catch {
                // Handle error
            }
        }

        await fulfillment(of: [expectation], timeout: 35.0)
    }

    func testConcurrentPageLoads() async throws {
        // Given
        let urls = [
            URL(string: "https://example.com")!,
            URL(string: "https://example.org")!,
            URL(string: "https://example.net")!
        ]

        // When - Create multiple testers for concurrent loads
        let tasks = urls.map { url in
            Task {
                let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
                let tester = PageLoadTester(webView: webView)
                return try await tester.measurePageLoad(url: url, timeout: 30.0, maxRetries: 0)
            }
        }

        // Then - All should complete without crashes
        for task in tasks {
            do {
                let result = try await task.value
                XCTAssertNotNil(result)
            } catch {
                // Some may fail, but shouldn't crash
            }
        }
    }
}

// MARK: - Mock Navigation Delegate

@MainActor
private class MockNavigationDelegate: NSObject, WKNavigationDelegate {
    var shouldNeverComplete = false
    var shouldFailImmediately = false
    var errorToReturn: Error?

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if shouldFailImmediately, let error = errorToReturn {
            // Simulate immediate failure
            DispatchQueue.main.async {
                self.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Pass through to original delegate if it exists
        if let originalDelegate = webView.navigationDelegate as? PageLoadTester {
            originalDelegate.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !shouldNeverComplete {
            // Pass through to original delegate if it exists
            if let originalDelegate = webView.navigationDelegate as? PageLoadTester {
                originalDelegate.webView(webView, didFinish: navigation)
            }
        }
    }
}