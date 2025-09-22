//
//  MockWebView.swift
//  PerformanceTestTests
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//

import Foundation
import WebKit
@testable import PerformanceTest

/// Mock WebView for testing page load behavior
class MockWebView: WKWebView {

    // Control properties for testing
    var shouldSucceed = true
    var loadDuration: TimeInterval = 1.0
    var shouldTimeout = false
    var timeoutDuration: TimeInterval = 30.0

    // Tracking properties
    private(set) var loadedURLs: [URL] = []
    private(set) var navigationStartTime: Date?
    private(set) var navigationEndTime: Date?

    // Simulated navigation state
    private var _isLoading = false
    override var isLoading: Bool {
        return _isLoading
    }

    private var _url: URL?
    override var url: URL? {
        return _url
    }

    // Mock navigation delegate
    weak var mockNavigationDelegate: WKNavigationDelegate?

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func load(_ request: URLRequest) -> WKNavigation? {
        guard let url = request.url else { return nil }

        loadedURLs.append(url)
        _url = url
        _isLoading = true
        navigationStartTime = Date()

        // Simulate async loading
        DispatchQueue.main.asyncAfter(deadline: .now() + loadDuration) { [weak self] in
            guard let self = self else { return }

            if self.shouldTimeout {
                self.simulateTimeout()
            } else if self.shouldSucceed {
                self.simulateSuccessfulLoad()
            } else {
                self.simulateFailedLoad()
            }
        }

        // Return mock navigation object
        return MockNavigation()
    }

    private func simulateSuccessfulLoad() {
        _isLoading = false
        navigationEndTime = Date()

        // Call delegate methods
        mockNavigationDelegate?.webView?(self, didFinish: MockNavigation())
    }

    private func simulateFailedLoad() {
        _isLoading = false

        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotFindHost,
            userInfo: [NSLocalizedDescriptionKey: "Cannot find host"]
        )

        mockNavigationDelegate?.webView?(self, didFail: MockNavigation(), withError: error)
    }

    private func simulateTimeout() {
        _isLoading = false

        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorTimedOut,
            userInfo: [NSLocalizedDescriptionKey: "The request timed out"]
        )

        mockNavigationDelegate?.webView?(self, didFail: MockNavigation(), withError: error)
    }

    func reset() {
        loadedURLs.removeAll()
        _url = nil
        _isLoading = false
        navigationStartTime = nil
        navigationEndTime = nil
    }
}

/// Mock WKNavigation for testing
class MockNavigation: WKNavigation {
    // Empty implementation for testing
}

/// Mock JavaScript evaluation result
extension MockWebView {
    override func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        // Simulate performance metrics collection
        if javaScriptString.contains("performance") {
            let mockMetrics: [String: Any] = [
                "loadTime": loadDuration * 1000, // Convert to milliseconds
                "firstContentfulPaint": loadDuration * 0.3 * 1000,
                "largestContentfulPaint": loadDuration * 0.7 * 1000,
                "timeToFirstByte": loadDuration * 0.1 * 1000
            ]
            completionHandler?(mockMetrics, nil)
        } else {
            completionHandler?(nil, nil)
        }
    }
}
