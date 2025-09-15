//
//  SitePerformanceTester.swift
//  PerformanceTest
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//

import Foundation
import WebKit
import os.log

/// Manages site performance testing with cache clearing and multiple iterations
@MainActor
public class SitePerformanceTester: NSObject {

    // MARK: - Properties

    private let webView: WKWebView
    private let logger = Logger(subsystem: "com.duckduckgo.macos.browser.performancetest", category: "SitePerformanceTester")

    /// Progress callback (iteration, total, status)
    public var progressHandler: ((Int, Int, String) -> Void)?

    /// Cancellation check
    public var isCancelled: () -> Bool = { false }

    // MARK: - Initialization

    public init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }

    // MARK: - Public Methods

    /// Run performance test with multiple iterations
    public func runPerformanceTest(
        url: URL,
        iterations: Int = 10,
        timeout: TimeInterval = 30.0
    ) async -> PerformanceTestResults {
        var loadTimes: [TimeInterval] = []
        var detailedMetrics = CollectedMetrics()
        var failedAttempts = 0

        // Store original delegate
        let originalDelegate = webView.navigationDelegate

        for iteration in 1...iterations {
            // Check cancellation
            if isCancelled() {
                webView.navigationDelegate = originalDelegate
                return PerformanceTestResults(
                    url: url,
                    loadTimes: loadTimes,
                    detailedMetrics: detailedMetrics,
                    failedAttempts: failedAttempts,
                    iterations: iteration - 1,
                    cancelled: true
                )
            }

            // Progress: Clearing cache
            progressHandler?(iteration, iterations, "Clearing cache...")

            // Clear cache for this specific website
            await clearCacheForURL(url)

            // Wait 500ms after cache clearing for it to take effect
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Progress: Loading page
            progressHandler?(iteration, iterations, "Loading page...")

            // Measure load time and collect metrics
            let metrics = await measurePageLoadAndCollectMetrics(url: url, timeout: timeout)

            if let metrics = metrics {
                loadTimes.append(metrics.loadComplete)
                detailedMetrics.append(metrics)
                logger.debug("Iteration \(iteration): Collected metrics successfully")
            } else {
                failedAttempts += 1
                logger.debug("Iteration \(iteration): Failed to collect metrics")
            }
        }

        // Restore original delegate
        webView.navigationDelegate = originalDelegate

        // Log summary of collected metrics
        logger.debug("Test complete. Collected \(detailedMetrics.loadComplete.count) samples")
        logger.debug("LoadComplete values: \(detailedMetrics.loadComplete)")
        logger.debug("DomComplete values: \(detailedMetrics.domComplete)")
        logger.debug("TTFB values: \(detailedMetrics.ttfb)")

        return PerformanceTestResults(
            url: url,
            loadTimes: loadTimes,
            detailedMetrics: detailedMetrics,
            failedAttempts: failedAttempts,
            iterations: iterations,
            cancelled: false
        )
    }

    // MARK: - Private Methods

    private func clearCacheForURL(_ url: URL) async {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: dataTypes)

        // Filter records for this specific domain
        let domain = url.host ?? url.absoluteString
        let recordsToDelete = records.filter { record in
            record.displayName.lowercased().contains(domain.lowercased()) ||
            record.displayName == domain
        }

        // Remove the data only for this specific domain
        if !recordsToDelete.isEmpty {
            await dataStore.removeData(ofTypes: dataTypes, for: recordsToDelete)

            // Also clear HTTP cache and cookies more aggressively
            let httpCookieStore = dataStore.httpCookieStore
            let cookies = await httpCookieStore.allCookies()

            for cookie in cookies {
                if cookie.domain.contains(domain) || domain.contains(cookie.domain) {
                    await httpCookieStore.delete(cookie)
                }
            }
        }
    }

    private func measurePageLoadAndCollectMetrics(url: URL, timeout: TimeInterval) async -> DetailedMetrics? {
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate

        delegate.startMeasurement()
        webView.load(URLRequest(url: url))

        let checkInterval: TimeInterval = 0.5
        var elapsed: TimeInterval = 0

        while !delegate.isComplete && elapsed < timeout {
            try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            elapsed += checkInterval

            // Try to get performance metrics after 2 seconds
            if elapsed > 2.0 {
                if let metrics = await collectPerformanceMetrics() {
                    return metrics
                }
            }
        }

        // If delegate completed, collect metrics
        if delegate.isComplete && delegate.error == nil {
            return await collectPerformanceMetrics()
        }

        return nil
    }

    private func collectPerformanceMetrics() async -> DetailedMetrics? {
        let script = """
            (function() {
                if (document.readyState !== 'complete') {
                    return null;
                }

                const navigation = performance.getEntriesByType('navigation')[0];
                const paint = performance.getEntriesByType('paint');
                const resources = performance.getEntriesByType('resource');

                // Find FCP
                const fcp = paint.find(p => p.name === 'first-contentful-paint');

                // Calculate total resource sizes
                const totalResourceSize = resources.reduce((sum, r) => sum + (r.transferSize || 0), 0);

                if (navigation) {
                    return {
                        // Core timing metrics (in milliseconds)
                        loadComplete: navigation.loadEventEnd - navigation.fetchStart,
                        domComplete: navigation.domComplete - navigation.fetchStart,
                        domContentLoaded: navigation.domContentLoadedEventEnd - navigation.fetchStart,
                        domInteractive: navigation.domInteractive - navigation.fetchStart,

                        // Paint metrics
                        fcp: fcp ? fcp.startTime : 0,

                        // Network metrics
                        ttfb: navigation.responseStart - navigation.fetchStart,
                        responseTime: navigation.responseEnd - navigation.responseStart,
                        serverTime: navigation.responseStart - navigation.requestStart,

                        // Size metrics (in bytes)
                        transferSize: navigation.transferSize || 0,
                        encodedBodySize: navigation.encodedBodySize || 0,
                        decodedBodySize: navigation.decodedBodySize || 0,

                        // Resource metrics
                        resourceCount: resources.length,
                        totalResourcesSize: totalResourceSize,

                        // TTI approximation
                        tti: navigation.domInteractive - navigation.fetchStart
                    };
                }

                return null;
            })();
        """

        do {
            let result: Any? = try await webView.evaluateJavaScript(script)
            if let metrics = result as? [String: Any] {
                logger.debug("Raw metrics collected: \(metrics)")

                let detailedMetrics = DetailedMetrics(
                    loadComplete: (metrics["loadComplete"] as? Double ?? 0) / 1000.0,
                    domComplete: (metrics["domComplete"] as? Double ?? 0) / 1000.0,
                    domContentLoaded: (metrics["domContentLoaded"] as? Double ?? 0) / 1000.0,
                    domInteractive: (metrics["domInteractive"] as? Double ?? 0) / 1000.0,
                    fcp: (metrics["fcp"] as? Double ?? 0) / 1000.0,
                    ttfb: (metrics["ttfb"] as? Double ?? 0) / 1000.0,
                    responseTime: (metrics["responseTime"] as? Double ?? 0) / 1000.0,
                    serverTime: (metrics["serverTime"] as? Double ?? 0) / 1000.0,
                    transferSize: metrics["transferSize"] as? Double ?? 0,
                    encodedBodySize: metrics["encodedBodySize"] as? Double ?? 0,
                    decodedBodySize: metrics["decodedBodySize"] as? Double ?? 0,
                    resourceCount: metrics["resourceCount"] as? Int ?? 0,
                    totalResourcesSize: metrics["totalResourcesSize"] as? Double ?? 0,
                    tti: (metrics["tti"] as? Double ?? 0) / 1000.0
                )

                logger.debug("Processed metrics - loadComplete: \(detailedMetrics.loadComplete), domComplete: \(detailedMetrics.domComplete), ttfb: \(detailedMetrics.ttfb)")
                return detailedMetrics
            } else {
                logger.debug("Failed to cast result to metrics dictionary. Result type: \(type(of: result))")
            }
        } catch {
            logger.debug("JavaScript evaluation failed: \(error.localizedDescription)")
        }

        return nil
    }

    struct DetailedMetrics {
        let loadComplete: TimeInterval
        let domComplete: TimeInterval
        let domContentLoaded: TimeInterval
        let domInteractive: TimeInterval
        let fcp: TimeInterval
        let ttfb: TimeInterval
        let responseTime: TimeInterval
        let serverTime: TimeInterval
        let transferSize: Double
        let encodedBodySize: Double
        let decodedBodySize: Double
        let resourceCount: Int
        let totalResourcesSize: Double
        let tti: TimeInterval
    }
}

// MARK: - Navigation Delegate

private class NavigationDelegate: NSObject, WKNavigationDelegate {
    private var startTime: Date?
    var loadTime: TimeInterval?
    var isComplete = false
    var error: Error?

    func startMeasurement() {
        startTime = Date()
        loadTime = nil
        isComplete = false
        error = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let startTime = startTime {
            loadTime = Date().timeIntervalSince(startTime)
        }
        isComplete = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.error = error
        isComplete = true
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.error = error
        isComplete = true
    }
}

// MARK: - Collected Metrics Structure

public struct CollectedMetrics {
    var loadComplete: [TimeInterval] = []
    var domComplete: [TimeInterval] = []
    var domContentLoaded: [TimeInterval] = []
    var domInteractive: [TimeInterval] = []
    var fcp: [TimeInterval] = []
    var ttfb: [TimeInterval] = []
    var responseTime: [TimeInterval] = []
    var serverTime: [TimeInterval] = []
    var transferSize: [Double] = []
    var encodedBodySize: [Double] = []
    var decodedBodySize: [Double] = []
    var resourceCount: [Int] = []
    var totalResourcesSize: [Double] = []
    var tti: [TimeInterval] = []

    mutating func append(_ metrics: SitePerformanceTester.DetailedMetrics) {
        loadComplete.append(metrics.loadComplete)
        domComplete.append(metrics.domComplete)
        domContentLoaded.append(metrics.domContentLoaded)
        domInteractive.append(metrics.domInteractive)
        fcp.append(metrics.fcp)
        ttfb.append(metrics.ttfb)
        responseTime.append(metrics.responseTime)
        serverTime.append(metrics.serverTime)
        transferSize.append(metrics.transferSize)
        encodedBodySize.append(metrics.encodedBodySize)
        decodedBodySize.append(metrics.decodedBodySize)
        resourceCount.append(metrics.resourceCount)
        totalResourcesSize.append(metrics.totalResourcesSize)
        tti.append(metrics.tti)
    }
}

// MARK: - Results Model

public struct PerformanceTestResults {
    public let url: URL
    public let loadTimes: [TimeInterval]
    public let detailedMetrics: CollectedMetrics
    public let failedAttempts: Int
    public let iterations: Int
    public let cancelled: Bool

    public var averageTime: TimeInterval? {
        guard !loadTimes.isEmpty else { return nil }
        return loadTimes.reduce(0, +) / Double(loadTimes.count)
    }

    public var minTime: TimeInterval? {
        return loadTimes.min()
    }

    public var maxTime: TimeInterval? {
        return loadTimes.max()
    }

    public var standardDeviation: TimeInterval? {
        guard !loadTimes.isEmpty else { return nil }
        let avg = averageTime ?? 0
        let variance = loadTimes.reduce(0) { sum, time in
            sum + pow(time - avg, 2)
        } / Double(loadTimes.count)
        return sqrt(variance)
    }

    // MARK: - Percentile Analysis

    public var medianTime: TimeInterval? {
        return percentile(50)
    }

    public var p75Time: TimeInterval? {
        return percentile(75)
    }

    public var p95Time: TimeInterval? {
        return percentile(95)
    }

    public func percentile(_ p: Double) -> TimeInterval? {
        guard !loadTimes.isEmpty else { return nil }
        guard p >= 0 && p <= 100 else { return nil }

        // Exclude first iteration (warm-up) for DNS resolution, connection establishment
        let relevantTimes = loadTimes.count > 1 ? Array(loadTimes.dropFirst(1)) : loadTimes
        let sortedTimes = relevantTimes.sorted()
        let count = Double(sortedTimes.count)

        guard count > 0 else { return nil }

        if p == 0 { return sortedTimes.first }
        if p == 100 { return sortedTimes.last }

        let index = (p / 100.0) * (count - 1)
        let lowerIndex = Int(floor(index))
        let upperIndex = Int(ceil(index))

        if lowerIndex == upperIndex {
            return sortedTimes[lowerIndex]
        }

        let weight = index - Double(lowerIndex)
        let lowerValue = sortedTimes[lowerIndex]
        let upperValue = sortedTimes[upperIndex]

        return lowerValue + weight * (upperValue - lowerValue)
    }

    // MARK: - Enhanced Reliability Analysis

    public var p95ToP50Ratio: Double? {
        guard let p95 = p95Time, let p50 = medianTime, p50 > 0 else { return nil }
        return p95 / p50
    }

    public var reliabilityScore: String {
        guard let cv = coefficientOfVariation, let ratio = p95ToP50Ratio else { return "Unknown" }

        // Distinguish between test reliability and site reliability
        if cv < 10 && ratio < 1.5 {
            return "Excellent"
        } else if cv < 20 && ratio < 2.0 {
            return "Good"
        } else if cv < 40 && ratio < 3.0 {
            return "Fair"
        } else {
            // High variance could be site issue, not test issue
            return "Variable"
        }
    }

    public var reliabilityType: String {
        guard let cv = coefficientOfVariation, let ratio = p95ToP50Ratio else { return "Unknown" }

        // If P95/P50 ratio is high but CV is relatively low, it's likely the site
        if ratio > 3.0 && cv < 30 {
            return "Site has inconsistent performance"
        } else if ratio > 2.5 && cv < 20 {
            return "Site shows performance variance"
        } else if cv > 40 {
            return "Test results vary - consider retesting"
        } else {
            return "Confidence: \(confidenceScore)%"
        }
    }

    public var confidenceScore: Int {
        guard let cv = coefficientOfVariation else { return 0 }

        // Convert CV to confidence score (lower CV = higher confidence)
        // CV of 0-5% = 95-100% confidence
        // CV of 5-10% = 90-95% confidence
        // CV of 10-20% = 80-90% confidence
        // CV of 20-30% = 70-80% confidence
        // CV of 30-40% = 60-70% confidence
        // CV > 40% = < 60% confidence

        if cv <= 5 {
            return Int(100 - cv)
        } else if cv <= 10 {
            return Int(95 - (cv - 5))
        } else if cv <= 20 {
            return Int(90 - (cv - 10) * 0.5)
        } else if cv <= 30 {
            return Int(80 - (cv - 20) * 0.5)
        } else if cv <= 40 {
            return Int(70 - (cv - 30) * 0.5)
        } else {
            return max(50, Int(60 - (cv - 40) * 0.2))
        }
    }

    public var coefficientOfVariation: Double? {
        guard let avg = averageTime, let stdDev = standardDeviation, avg > 0 else { return nil }
        return (stdDev / avg) * 100
    }

    public var recommendedIterations: Int {
        guard let cv = coefficientOfVariation else { return 20 }

        if cv > 30 { return 50 } else if cv > 15 { return 30 } else { return 20 }
    }

    public var performanceScore: Int {
        guard let median = medianTime else { return 0 }
        // Based on Core Web Vitals LCP thresholds
        // Good: < 2.5s, Needs Improvement: 2.5-4s, Poor: > 4s
        switch median {
        case ..<1.0: return 100
        case ..<1.5: return 95
        case ..<2.0: return 90
        case ..<2.5: return 85  // Still "Good" per Core Web Vitals
        case ..<3.0: return 75
        case ..<3.5: return 70
        case ..<4.0: return 65  // "Needs Improvement" threshold
        case ..<5.0: return 55
        case ..<6.0: return 45
        case ..<8.0: return 35
        case ..<10.0: return 25
        default: return max(0, 25 - Int((median - 10) * 2))
        }
    }

    public var performanceGrade: String {
        switch performanceScore {
        case 90...100: return "A"
        case 80..<90: return "B"
        case 70..<80: return "C"
        case 60..<70: return "D"
        default: return "F"
        }
    }
}
