//
//  PageLoadTester.swift
//  PerformanceTest
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//

import Foundation
import WebKit
import os.log

/// Measures page load performance using WebKit
@MainActor
public class PageLoadTester: NSObject {

    // MARK: - Properties

    private let webView: WKWebView
    private let logger = Logger(subsystem: "com.duckduckgo.macos.browser.performancetest", category: "PageLoadTester")

    /// Progress callback for UI updates (0.0 to 1.0)
    public var progressHandler: ((Double) -> Void)?

    /// Completion callback for results
    public var completionHandler: ((TestResult) -> Void)?

    /// Hook for test setup
    public var beforeLoadHandler: (() -> Void)?

    // Navigation tracking
    private var navigationStartTime: Date?
    private var currentURL: URL?
    private var continuation: CheckedContinuation<TestResult, Error>?

    // MARK: - Initialization

    public init(webView: WKWebView) {
        self.webView = webView
        super.init()
        self.webView.navigationDelegate = self
    }

    // MARK: - Public Methods

    /// Measure page load performance for a URL
    public func measurePageLoad(
        url: URL,
        timeout: TimeInterval = 30.0,
        maxRetries: Int = 1
    ) async throws -> TestResult {
        var lastError: Error?
        var attempts = 0

        while attempts < maxRetries {
            attempts += 1

            // Call setup hook if provided
            beforeLoadHandler?()

            do {
                let result = try await performSingleTest(url: url, timeout: timeout)
                return result
            } catch {
                lastError = error
                logger.warning("Test attempt \(attempts) failed: \(error.localizedDescription)")

                // Only retry on transient errors
                if case PageLoadError.timeout = error {
                    continue
                } else if case PageLoadError.networkError = error {
                    continue
                } else {
                    throw error
                }
            }
        }

        // All retries exhausted
        throw lastError ?? PageLoadError.networkError(message: "All retry attempts failed")
    }

    // MARK: - Private Methods

    private func performSingleTest(url: URL, timeout: TimeInterval) async throws -> TestResult {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.currentURL = url
                self.navigationStartTime = Date()

                // Start loading
                let request = URLRequest(url: url)
                self.webView.load(request)

                // Set timeout
                Task {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    if self.continuation != nil {
                        self.continuation?.resume(throwing: PageLoadError.timeout(duration: timeout))
                        self.continuation = nil
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.continuation?.resume(throwing: CancellationError())
                self.continuation = nil
                self.webView.stopLoading()
            }
        }
    }

    private func collectPerformanceMetrics() async throws -> PerformanceMetrics? {
        // Use JavaScript to collect performance metrics
        let script = """
            (function() {
                const perf = performance.getEntriesByType('navigation')[0];
                const paintEntries = performance.getEntriesByType('paint');
                const fcp = paintEntries.find(e => e.name === 'first-contentful-paint');
                const lcp = performance.getEntriesByType('largest-contentful-paint')[0];

                return {
                    loadTime: perf ? perf.loadEventEnd - perf.fetchStart : null,
                    firstContentfulPaint: fcp ? fcp.startTime : null,
                    largestContentfulPaint: lcp ? lcp.startTime : null,
                    timeToFirstByte: perf ? perf.responseStart - perf.fetchStart : null
                };
            })();
        """

        do {
            let result = try await webView.evaluateJavaScript(script)
            guard let metrics = result as? [String: Any] else { return nil }

            // Convert milliseconds to seconds for loadTime
            let loadTimeMs = metrics["loadTime"] as? Double ?? 0
            let loadTime = loadTimeMs / 1000.0

            return PerformanceMetrics(
                loadTime: loadTime,
                firstContentfulPaint: metrics["firstContentfulPaint"] as? Double,
                largestContentfulPaint: metrics["largestContentfulPaint"] as? Double,
                timeToFirstByte: metrics["timeToFirstByte"] as? Double
            )
        } catch {
            logger.warning("Failed to collect performance metrics: \(error)")
            return nil
        }
    }
}

// MARK: - WKNavigationDelegate

extension PageLoadTester: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        logger.debug("Navigation started for: \(self.currentURL?.absoluteString ?? "unknown")")
        progressHandler?(0.1)
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        progressHandler?(0.3)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.debug("Navigation finished for: \(self.currentURL?.absoluteString ?? "unknown")")
        progressHandler?(0.9)

        guard let startTime = navigationStartTime,
              let url = currentURL else {
            continuation?.resume(throwing: PageLoadError.invalidURL)
            continuation = nil
            return
        }

        let endTime = Date()
        let loadTime = endTime.timeIntervalSince(startTime)

        Task {
            // Collect additional metrics
            let metrics = try? await collectPerformanceMetrics()

            // Use JavaScript metrics if available, otherwise fall back to navigation timing
            let finalMetrics = metrics ?? PerformanceMetrics(loadTime: loadTime)

            let result = TestResult(
                url: url,
                metrics: finalMetrics,
                success: true,
                error: nil,
                timestamp: startTime,
                endTime: endTime
            )

            progressHandler?(1.0)
            completionHandler?(result)
            continuation?.resume(returning: result)
            continuation = nil
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    private func handleNavigationError(_ error: Error) {
        logger.error("Navigation failed: \(error.localizedDescription)")

        guard let startTime = navigationStartTime,
              let url = currentURL else {
            continuation?.resume(throwing: PageLoadError.invalidURL)
            continuation = nil
            return
        }

        let nsError = error as NSError
        let testError: PageLoadError

        switch nsError.code {
        case NSURLErrorTimedOut:
            testError = .timeout(duration: 30.0)
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
            testError = .networkError(message: error.localizedDescription)
        case NSURLErrorCancelled:
            testError = .cancelled
        default:
            testError = .networkError(message: error.localizedDescription)
        }

        let result = TestResult(
            url: url,
            metrics: nil,
            success: false,
            error: TestError.otherError(message: testError.localizedDescription),
            timestamp: startTime,
            endTime: Date()
        )

        completionHandler?(result)
        continuation?.resume(throwing: testError)
        continuation = nil
    }
}

// MARK: - Error Types

public enum PageLoadError: LocalizedError {
    case timeout(duration: TimeInterval)
    case networkError(message: String)
    case invalidURL
    case cancelled

    public var errorDescription: String? {
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
