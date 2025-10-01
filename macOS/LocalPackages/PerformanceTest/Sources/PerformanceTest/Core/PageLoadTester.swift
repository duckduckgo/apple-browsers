//
//  PageLoadTester.swift
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

import Foundation
import WebKit
import os.log

public let defaultPageLoadTimeout: TimeInterval = 30.0

@MainActor
public class PageLoadTester: NSObject {

    private enum Constants {
        static let loggerSubsystem = "com.duckduckgo.macos.browser.performancetest"
        static let loggerCategory = "PageLoadTester"
        static let unknownURLString = "unknown"

        // Error Messages
        static let javascriptMetricsError = "JavaScript metrics collection error: "
        static let failedToCollectMetrics = "Failed to collect performance metrics: "
        static let allRetryAttemptsFailed = "All retry attempts failed"
        static let testAttemptFailed = "Test attempt %d failed: "
        static let navigationFailed = "Navigation failed: "

        // Debug Messages
        static let navigationStarted = "Navigation started for: "
        static let navigationFinished = "Navigation finished for: "
    }

    private let webView: WKWebView
    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: Constants.loggerCategory)
    private weak var previousNavigationDelegate: WKNavigationDelegate?

    public var progressHandler: ((Double) -> Void)?

    public var completionHandler: ((TestResult) -> Void)?

    public var beforeLoadHandler: (() -> Void)?

    private var navigationStartTime: Date?
    private var currentURL: URL?
    private var currentTimeout: TimeInterval = defaultPageLoadTimeout
    private var continuation: CheckedContinuation<TestResult, Error>?

    public init(webView: WKWebView) {
        self.webView = webView
        super.init()
        self.previousNavigationDelegate = webView.navigationDelegate
        self.webView.navigationDelegate = self
    }

    deinit {
        // Restore delegate on main thread
        let webView = self.webView
        let previousDelegate = self.previousNavigationDelegate
        Task { @MainActor in
            webView.navigationDelegate = previousDelegate
        }
    }

    public func measurePageLoad(
        url: URL,
        timeout: TimeInterval = defaultPageLoadTimeout,
        maxRetries: Int = 1
    ) async throws -> TestResult {
        var lastError: Error?
        var attempts = 0

        while attempts <= maxRetries {
            attempts += 1

            // Call setup hook if provided
            beforeLoadHandler?()

            do {
                let result = try await performSingleTest(url: url, timeout: timeout)
                return result
            } catch {
                lastError = error
                let attemptError = String(format: Constants.testAttemptFailed, attempts)
                logger.warning("\(attemptError)\(error.localizedDescription)")

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

        throw lastError ?? PageLoadError.networkError(message: Constants.allRetryAttemptsFailed)
    }

    private func performSingleTest(url: URL, timeout: TimeInterval) async throws -> TestResult {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                self.currentURL = url
                self.currentTimeout = timeout
                self.navigationStartTime = Date()

                let request = URLRequest(url: url)
                self.webView.load(request)

                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    guard let self = self else { return }
                    if let continuation = self.continuation {
                        self.continuation = nil
                        continuation.resume(throwing: PageLoadError.timeout(duration: timeout))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let continuation = self.continuation {
                    self.continuation = nil
                    continuation.resume(throwing: CancellationError())
                }
                self.webView.stopLoading()
            }
        }
    }

    private func collectPerformanceMetrics() async throws -> PerformanceMetrics? {
        // Load JavaScript from bundle resources - try correct bundle path
        let bundle: Bundle
        if let moduleBundle = Bundle(identifier: "PerformanceTest") {
            bundle = moduleBundle
        } else {
            // Look for the PerformanceTest_PerformanceTest.bundle inside main bundle
            let mainBundle = Bundle(for: PageLoadTester.self)
            guard let resourcePath = mainBundle.resourcePath,
                  let performanceBundle = Bundle(path: "\(resourcePath)/PerformanceTest_PerformanceTest.bundle") else {
                logger.error("Failed to find PerformanceTest bundle")
                throw PageLoadError.networkError(message: "PerformanceTest bundle not found")
            }
            bundle = performanceBundle
        }

        guard let url = bundle.url(forResource: "performanceMetrics", withExtension: "js") else {
            logger.error("Failed to find performanceMetrics.js in bundle")
            throw PageLoadError.networkError(message: "Performance metrics script not found in bundle")
        }

        guard let scriptContent = try? String(contentsOf: url) else {
            logger.error("Failed to read performanceMetrics.js from bundle")
            throw PageLoadError.networkError(message: "Failed to load performance metrics script")
        }

        do {
            // Load the function definition and then call it
            let fullScript = scriptContent + "; collectPerformanceMetrics();"
            let result = try await webView.evaluateJavaScript(fullScript)
            guard let metrics = result as? [String: Any] else { return nil }

            // Check for errors from JavaScript
            if let error = metrics["error"] as? String {
                logger.error("\(Constants.javascriptMetricsError)\(error)")
                return nil
            }

            // Convert milliseconds to seconds for time metrics
            let loadComplete = (metrics["loadComplete"] as? Double ?? 0) / 1000.0
            let fcp = (metrics["firstContentfulPaint"] as? Double).map { $0 / 1000.0 }
            let lcp = (metrics["largestContentfulPaint"] as? Double).map { $0 / 1000.0 }
            let ttfb = (metrics["timeToFirstByte"] as? Double).map { $0 / 1000.0 }

            return PerformanceMetrics(
                loadTime: loadComplete,
                firstContentfulPaint: fcp,
                largestContentfulPaint: lcp,
                timeToFirstByte: ttfb
            )
        } catch {
            logger.warning("\(Constants.failedToCollectMetrics)\(error)")
            return nil
        }
    }
}

extension PageLoadTester: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let urlString = self.currentURL?.absoluteString ?? Constants.unknownURLString
        logger.debug("\(Constants.navigationStarted)\(urlString)")
        progressHandler?(0.1)
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        progressHandler?(0.3)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let urlString = self.currentURL?.absoluteString ?? Constants.unknownURLString
        logger.debug("\(Constants.navigationFinished)\(urlString)")
        progressHandler?(0.9)

        guard let startTime = navigationStartTime,
              let url = currentURL else {
            if let continuation = continuation {
                self.continuation = nil
                continuation.resume(throwing: PageLoadError.invalidURL)
            }
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
            if let continuation = self.continuation {
                self.continuation = nil
                continuation.resume(returning: result)
            }
        }
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationError(error)
    }

    private func handleNavigationError(_ error: Error) {
        logger.error("\(Constants.navigationFailed)\(error.localizedDescription)")

        guard let startTime = navigationStartTime,
              let url = currentURL else {
            if let continuation = continuation {
                self.continuation = nil
                continuation.resume(throwing: PageLoadError.invalidURL)
            }
            return
        }

        let nsError = error as NSError
        let testError: PageLoadError

        switch nsError.code {
        case NSURLErrorTimedOut:
            testError = .timeout(duration: currentTimeout)
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
        // Check if continuation exists before resuming to prevent crashes
        if let continuation = continuation {
            self.continuation = nil
            continuation.resume(throwing: testError)
        }
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
            return String(format: "Page load timed out after %.0f seconds", duration)
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidURL:
            return "Invalid URL"
        case .cancelled:
            return "Page load was cancelled"
        }
    }
}
