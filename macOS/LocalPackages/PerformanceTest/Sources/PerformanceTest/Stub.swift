// Temporary stub file to allow package compilation
// This will be replaced with actual implementation

import Foundation
import WebKit

// Stub structs to allow tests to compile (will all fail)
public struct PerformanceMetrics: Codable, Equatable {
    public let loadTime: TimeInterval
    public init(loadTime: TimeInterval) { self.loadTime = loadTime }
    public init(loadTime: TimeInterval, firstContentfulPaint: TimeInterval? = nil,
                largestContentfulPaint: TimeInterval? = nil, timeToFirstByte: TimeInterval? = nil) {
        self.loadTime = loadTime
    }
}

public struct TestResult: Codable, Equatable {
    public let url: URL
    public init(url: URL, metrics: PerformanceMetrics?, success: Bool, error: Error?, timestamp: Date) {
        self.url = url
    }
}

public class PageLoadTester {
    public init(webView: WKWebView) {}
}
