//
//  SitePerformanceTester.swift
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

// swiftlint:disable file_length

import Foundation
import WebKit
import os.log

@MainActor
public class SitePerformanceTester: NSObject {

    private let webView: WKWebView
    private let logger = Logger(
        subsystem: "com.duckduckgo.macos.browser.performancetest",
        category: "SitePerformanceTester"
    )

    /// Progress callback (iteration, total, status)
    public var progressHandler: ((Int, Int, String) -> Void)?

    /// Cancellation check
    public var isCancelled: () -> Bool = { false }

    public init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }

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
                    iterations: loadTimes.count,  // Actual completed tests (excluding warm-up)
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
            iterations: iterations - 1,  // Exclude warm-up iteration from count
            cancelled: false
        )
    }

    private func clearCacheForURL(_ url: URL) async {
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        // Clear ALL website data to ensure clean test conditions
        // This handles redirects, third-party resources, and cached data
        let records = await dataStore.dataRecords(ofTypes: dataTypes)
        if !records.isEmpty {
            await dataStore.removeData(ofTypes: dataTypes, for: records)
        }

        // Also clear all cookies to ensure complete cache clearing
        let httpCookieStore = dataStore.httpCookieStore
        let cookies = await httpCookieStore.allCookies()

        if !cookies.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                for cookie in cookies {
                    group.addTask {
                        await httpCookieStore.delete(cookie)
                    }
                }
            }
        }
    }

    private func measurePageLoadAndCollectMetrics(
        url: URL,
        timeout: TimeInterval
    ) async -> DetailedPerformanceMetrics? {
        // Store original delegate to restore later
        let originalDelegate = webView.navigationDelegate

        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate

        defer {
            // Always restore original delegate
            webView.navigationDelegate = originalDelegate
        }

        delegate.startMeasurement()
        webView.load(URLRequest(url: url))

        let checkInterval: TimeInterval = 0.5
        var elapsed: TimeInterval = 0

        // Wait for navigation to complete or timeout
        while !delegate.isComplete && elapsed < timeout {
            try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            elapsed += checkInterval
        }

        // Only collect metrics if navigation completed successfully
        if delegate.isComplete && delegate.error == nil {
            // Wait additional 2 seconds for page stabilization (lazy content, layout shifts)
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            return await collectPerformanceMetrics()
        }

        return nil
    }

    private func collectPerformanceMetrics() async -> DetailedPerformanceMetrics? {
        // First try Bundle.module (SPM standard)
        let bundle: Bundle
        if let moduleBundle = Bundle(identifier: "PerformanceTest") {
            bundle = moduleBundle
        } else {
            // Fallback to Bundle(for:) which points to main app bundle
            let mainBundle = Bundle(for: SitePerformanceTester.self)

            // Look for the PerformanceTest_PerformanceTest.bundle inside main bundle
            guard let resourcePath = mainBundle.resourcePath,
                  let performanceBundle = Bundle(path: "\(resourcePath)/PerformanceTest_PerformanceTest.bundle") else {
                logger.error("Failed to find PerformanceTest bundle")
                return nil
            }
            bundle = performanceBundle
        }

        // Try to find the resource
        guard let url = bundle.url(forResource: "performanceMetrics", withExtension: "js") else {
            logger.error("Failed to find performanceMetrics.js in bundle")
            return nil
        }

        guard let script = try? String(contentsOf: url) else {
            logger.error("Failed to read performanceMetrics.js from bundle")
            return nil
        }

        do {
            // Load the function definition and then call it
            let fullScript = script + "; collectPerformanceMetrics();"

            let result: Any? = try await webView.evaluateJavaScript(fullScript)
           if let metrics = result as? [String: Any] {
                logger.debug("Raw metrics collected: \(metrics)")

                let detailedMetrics = DetailedPerformanceMetrics(
                    loadComplete: (metrics["loadComplete"] as? Double ?? 0) / 1000.0,
                    domComplete: (metrics["domComplete"] as? Double ?? 0) / 1000.0,
                    domContentLoaded: (metrics["domContentLoaded"] as? Double ?? 0) / 1000.0,
                    domInteractive: (metrics["domInteractive"] as? Double ?? 0) / 1000.0,
                    firstContentfulPaint: (metrics["fcp"] as? Double ?? 0) / 1000.0,
                    timeToFirstByte: (metrics["ttfb"] as? Double ?? 0) / 1000.0,
                    responseTime: (metrics["responseTime"] as? Double ?? 0) / 1000.0,
                    serverTime: (metrics["serverTime"] as? Double ?? 0) / 1000.0,
                    transferSize: metrics["transferSize"] as? Double ?? 0,
                    encodedBodySize: metrics["encodedBodySize"] as? Double ?? 0,
                    decodedBodySize: metrics["decodedBodySize"] as? Double ?? 0,
                    resourceCount: metrics["resourceCount"] as? Int ?? 0,
                    totalResourcesSize: metrics["totalResourcesSize"] as? Double ?? 0,
                    timeToInteractive: (metrics["tti"] as? Double ?? 0) / 1000.0,
                    protocol: metrics["protocol"] as? String,
                    redirectCount: metrics["redirectCount"] as? Int ?? 0,
                    navigationType: metrics["navigationType"] as? String ?? "navigate"
                )

                logger.debug("Processed metrics - loadComplete: \(detailedMetrics.loadComplete), domComplete: \(detailedMetrics.domComplete), ttfb: \(detailedMetrics.timeToFirstByte)")
                return detailedMetrics
            } else {
                logger.debug("Failed to cast result to metrics dictionary. Result type: \(type(of: result))")
            }
        } catch {
            logger.debug("JavaScript evaluation failed: \(error.localizedDescription)")
        }

        return nil
    }

}

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

    mutating func append(_ metrics: DetailedPerformanceMetrics) {
        loadComplete.append(metrics.loadComplete)
        domComplete.append(metrics.domComplete)
        domContentLoaded.append(metrics.domContentLoaded)
        domInteractive.append(metrics.domInteractive)
        fcp.append(metrics.firstContentfulPaint)
        ttfb.append(metrics.timeToFirstByte)
        responseTime.append(metrics.responseTime)
        serverTime.append(metrics.serverTime)
        transferSize.append(metrics.transferSize)
        encodedBodySize.append(metrics.encodedBodySize)
        decodedBodySize.append(metrics.decodedBodySize)
        resourceCount.append(metrics.resourceCount)
        totalResourcesSize.append(metrics.totalResourcesSize)
        tti.append(metrics.timeToInteractive ?? 0)
    }
}

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

    public func percentile(_ percentile: Double) -> TimeInterval? {
        guard !loadTimes.isEmpty else { return nil }
        guard percentile >= 0 && percentile <= 100 else { return nil }

        // Exclude first iteration (warm-up) for DNS resolution, connection establishment
        let relevantTimes = loadTimes.count > 1 ? Array(loadTimes.dropFirst(1)) : loadTimes
        let sortedTimes = relevantTimes.sorted()
        let count = Double(sortedTimes.count)

        guard count > 0 else { return nil }

        if percentile == 0 { return sortedTimes.first }
        if percentile == 100 { return sortedTimes.last }

        let index = (percentile / 100.0) * (count - 1)
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
        guard let coeffVariation = coefficientOfVariation,
              let ratio = p95ToP50Ratio else { return "Unknown" }

        // Distinguish between test reliability and site reliability
        if coeffVariation < 10 && ratio < 1.5 {
            return "Excellent"
        } else if coeffVariation < 20 && ratio < 2.0 {
            return "Good"
        } else if coeffVariation < 40 && ratio < 3.0 {
            return "Fair"
        } else {
            // High variance could be site issue, not test issue
            return "Variable"
        }
    }

    public var reliabilityType: String {
        guard let coeffVariation = coefficientOfVariation,
              let ratio = p95ToP50Ratio else { return "Unknown" }

        // If P95/P50 ratio is high but CV is relatively low, it's likely the site
        if ratio > 3.0 && coeffVariation < 30 {
            return "Site has inconsistent performance"
        } else if ratio > 2.5 && coeffVariation < 20 {
            return "Site shows performance variance"
        } else if coeffVariation > 40 {
            return "Test results vary - consider retesting"
        } else {
            return "Confidence: \(confidenceScore)%"
        }
    }

    public var confidenceScore: Int {
        guard let coeffVariation = coefficientOfVariation else { return 0 }

        // Convert CV to confidence score (lower CV = higher confidence)
        // CV of 0-5% = 95-100% confidence
        // CV of 5-10% = 90-95% confidence
        // CV of 10-20% = 80-90% confidence
        // CV of 20-30% = 70-80% confidence
        // CV of 30-40% = 60-70% confidence
        // CV > 40% = < 60% confidence

        if coeffVariation <= 5 {
            return Int(100 - coeffVariation)
        } else if coeffVariation <= 10 {
            return Int(95 - (coeffVariation - 5))
        } else if coeffVariation <= 20 {
            return Int(90 - (coeffVariation - 10) * 0.5)
        } else if coeffVariation <= 30 {
            return Int(80 - (coeffVariation - 20) * 0.5)
        } else if coeffVariation <= 40 {
            return Int(70 - (coeffVariation - 30) * 0.5)
        } else {
            return max(50, Int(60 - (coeffVariation - 40) * 0.2))
        }
    }

    public var coefficientOfVariation: Double? {
        guard let avg = averageTime, let stdDev = standardDeviation, avg > 0 else { return nil }
        return (stdDev / avg) * 100
    }

    public var recommendedIterations: Int {
        guard let coeffVariation = coefficientOfVariation else { return 20 }

        if coeffVariation > 30 { return 50 } else if coeffVariation > 15 { return 30 } else { return 20 }
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
