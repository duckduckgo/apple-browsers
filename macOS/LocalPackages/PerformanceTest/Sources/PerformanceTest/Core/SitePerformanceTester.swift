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

    private var webView: WKWebView
    private let createNewTab: (() async -> WKWebView?)?
    private let closeTab: (() async -> Void)?
    private let logger = Logger(
        subsystem: "com.duckduckgo.macos.browser.performancetest",
        category: "SitePerformanceTester"
    )

    /// Progress callback (iteration, total, status)
    public var progressHandler: ((Int, Int, String) -> Void)?

    /// Cancellation check
    public var isCancelled: () -> Bool = { false }

    public init(
        webView: WKWebView,
        createNewTab: (() async -> WKWebView?)? = nil,
        closeTab: (() async -> Void)? = nil
    ) {
        self.webView = webView
        self.createNewTab = createNewTab
        self.closeTab = closeTab
        super.init()
    }

    public func runPerformanceTest(
        url: URL,
        iterations: Int = 10,
        maxIterations: Int = 30,
        timeout: TimeInterval = 30.0
    ) async -> PerformanceTestResults {
        var loadTimes: [TimeInterval] = []
        var detailedMetrics = CollectedMetrics()
        var failedAttempts = 0

        let minIterations = iterations
        var currentIteration = 0
        var shouldContinue = true

        while shouldContinue && currentIteration < maxIterations {
            currentIteration += 1

            if isCancelled() {
                return createCancelledResults(url: url, loadTimes: loadTimes, detailedMetrics: detailedMetrics, failedAttempts: failedAttempts)
            }

            let iterationResult = await performSingleIteration(
                url: url,
                iteration: currentIteration,
                minIterations: iterations,
                timeout: timeout
            )

            loadTimes.append(contentsOf: iterationResult.loadTimes)
            mergeMetrics(from: iterationResult.metrics, into: &detailedMetrics)
            failedAttempts += iterationResult.failedAttempts

            shouldContinue = checkShouldContinue(
                iteration: currentIteration,
                minIterations: minIterations,
                maxIterations: maxIterations,
                loadTimes: loadTimes
            )
        }

        logTestSummary(detailedMetrics: detailedMetrics, currentIteration: currentIteration)

        return PerformanceTestResults(
            url: url,
            loadTimes: loadTimes,
            detailedMetrics: detailedMetrics,
            failedAttempts: failedAttempts,
            iterations: loadTimes.count,
            cancelled: false
        )
    }

    private func createCancelledResults(
        url: URL,
        loadTimes: [TimeInterval],
        detailedMetrics: CollectedMetrics,
        failedAttempts: Int
    ) -> PerformanceTestResults {
        return PerformanceTestResults(
            url: url,
            loadTimes: loadTimes,
            detailedMetrics: detailedMetrics,
            failedAttempts: failedAttempts,
            iterations: loadTimes.count,
            cancelled: true
        )
    }

    private func performSingleIteration(
        url: URL,
        iteration: Int,
        minIterations: Int,
        timeout: TimeInterval
    ) async -> (loadTimes: [TimeInterval], metrics: CollectedMetrics, failedAttempts: Int) {
        var loadTimes: [TimeInterval] = []
        var detailedMetrics = CollectedMetrics()
        var failedAttempts = 0

        progressHandler?(iteration, minIterations, "Clearing cache...")
        await clearCacheForURL(url)
        await verifyCacheClearing()
        try? await Task.sleep(nanoseconds: 500_000_000)

        guard await prepareTestIteration(iteration: iteration) else {
            return ([], detailedMetrics, 1)
        }

        await runWarmup(iteration: iteration, minIterations: minIterations)
        try? await Task.sleep(nanoseconds: 500_000_000)

        progressHandler?(iteration, minIterations, "Loading page...")

        if let metrics = await measurePageLoadAndCollectMetrics(url: url, timeout: timeout) {
            loadTimes.append(metrics.loadComplete)
            detailedMetrics.append(metrics)
            logger.debug("Iteration \(iteration): Collected metrics successfully")
        } else {
            failedAttempts += 1
            logger.debug("Iteration \(iteration): Failed to collect metrics")
        }

        return (loadTimes, detailedMetrics, failedAttempts)
    }

    private func verifyCacheClearing() async {
        let dataStore = webView.configuration.websiteDataStore
        let remainingRecords = await dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())

        if !remainingRecords.isEmpty {
            logger.warning("Warning: \(remainingRecords.count) data records still present after clearing")
        } else {
            logger.debug("Cache clearing verified - 0 data records remaining")
        }
    }

    private func prepareTestIteration(iteration: Int) async -> Bool {
        if iteration > 1, let closeTab = closeTab {
            logger.debug("Iteration \(iteration): Closing previous test tab")
            await closeTab()
            logger.debug("Iteration \(iteration): Closed previous test tab")
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s delay to visualize tab closure
        }

        guard let createNewTab = createNewTab else {
            logger.error("createNewTab closure not provided")
            return false
        }

        guard let newWebView = await createNewTab() else {
            logger.warning("Iteration \(iteration): Failed to create new tab")
            return false
        }

        logger.debug("Iteration \(iteration): Created new test tab")
        webView = newWebView
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5s delay to visualize tab creation
        return true
    }

    private func runWarmup(iteration: Int, minIterations: Int) async {
        progressHandler?(iteration, minIterations, "Warming up JavaScript engine...")

        guard let warmupURL = URL(string: "https://duckduckgo.com") else {
            logger.error("Failed to create warmup URL")
            return
        }

        let warmupDelegate = NavigationDelegate()
        let originalDelegate = webView.navigationDelegate

        defer {
            webView.navigationDelegate = originalDelegate
        }

        warmupDelegate.startMeasurement()
        webView.navigationDelegate = warmupDelegate
        webView.load(URLRequest(url: warmupURL))

        await waitForWarmupCompletion(delegate: warmupDelegate)
    }

    private func waitForWarmupCompletion(delegate: NavigationDelegate) async {
        let warmupTimeout: TimeInterval = 10
        var warmupElapsed: TimeInterval = 0
        let checkInterval: TimeInterval = 0.5

        while !delegate.isComplete && warmupElapsed < warmupTimeout {
            try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            warmupElapsed += checkInterval
        }

        logWarmupResult(delegate: delegate)
    }

    private func logWarmupResult(delegate: NavigationDelegate) {
        if let error = delegate.error {
            logger.warning("Warmup navigation failed: \(error.localizedDescription)")
        } else if !delegate.isComplete {
            logger.warning("Warmup navigation timed out")
        } else {
            logger.debug("Warmup navigation completed in \(delegate.loadTime ?? 0)s")
        }
    }

    private func checkShouldContinue(
        iteration: Int,
        minIterations: Int,
        maxIterations: Int,
        loadTimes: [TimeInterval]
    ) -> Bool {
        guard iteration >= minIterations, loadTimes.count >= 4 else {
            return true
        }

        let isConsistent = isDataConsistent(loadTimes)
        logConsistencyMetrics(loadTimes: loadTimes, iteration: iteration, maxIterations: maxIterations)

        if isConsistent {
            logger.info("✓ Achieved 'Good' consistency after \(iteration) iterations. Stopping.")
            progressHandler?(iteration, maxIterations, "Good consistency achieved")
            return false
        }

        logger.info("Consistency not yet achieved. Testing iteration \(iteration + 1)...")
        return true
    }

    private func logConsistencyMetrics(loadTimes: [TimeInterval], iteration: Int, maxIterations: Int) {
        let sorted = loadTimes.sorted()
        let median = PerformanceTestResults.calculateMedian(sorted)

        guard let iqr = PerformanceTestResults.calculateIQR(sorted), median > 0 else { return }

        let coeffVar = (iqr / median * 100)
        let p50Index = Int(Double(sorted.count - 1) * 0.50)
        let p95Index = Int(Double(sorted.count - 1) * 0.95)
        let ratio = sorted[p95Index] / sorted[p50Index]
        let statusMsg = String(format: "CoeffVar: %.1f%%, Ratio: %.2fx", coeffVar, ratio)

        logger.info("Consistency metrics: \(statusMsg) (target: <20% AND <2.0x)")
        logger.info("  Median: \(Int(median))ms, IQR: \(Int(iqr))ms, P50: \(Int(sorted[p50Index]))ms, P95: \(Int(sorted[p95Index]))ms")
        progressHandler?(iteration, maxIterations, statusMsg)
    }

    private func mergeMetrics(from source: CollectedMetrics, into target: inout CollectedMetrics) {
        target.loadComplete.append(contentsOf: source.loadComplete)
        target.domComplete.append(contentsOf: source.domComplete)
        target.domContentLoaded.append(contentsOf: source.domContentLoaded)
        target.domInteractive.append(contentsOf: source.domInteractive)
        target.fcp.append(contentsOf: source.fcp)
        target.ttfb.append(contentsOf: source.ttfb)
        target.responseTime.append(contentsOf: source.responseTime)
        target.serverTime.append(contentsOf: source.serverTime)
        target.transferSize.append(contentsOf: source.transferSize)
        target.encodedBodySize.append(contentsOf: source.encodedBodySize)
        target.decodedBodySize.append(contentsOf: source.decodedBodySize)
        target.resourceCount.append(contentsOf: source.resourceCount)
        target.totalResourcesSize.append(contentsOf: source.totalResourcesSize)
        target.tti.append(contentsOf: source.tti)
    }

    private func logTestSummary(detailedMetrics: CollectedMetrics, currentIteration: Int) {
        logger.debug("Test complete. Collected \(detailedMetrics.loadComplete.count) samples across \(currentIteration) iterations")
        logger.debug("LoadComplete values: \(detailedMetrics.loadComplete)")
        logger.debug("DomComplete values: \(detailedMetrics.domComplete)")
        logger.debug("TTFB values: \(detailedMetrics.ttfb)")
    }

    private func clearCacheForURL(_ url: URL) async {
        // CRITICAL: Use the webView's actual data store, not .default()
        // The webView might be using a custom data store (e.g., burner mode)
        let dataStore = webView.configuration.websiteDataStore
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()

        logger.debug("Clearing all website data types: \(dataTypes)")

        // Clear ALL website data to ensure clean test conditions
        // This handles redirects, third-party resources, and cached data
        let records = await dataStore.dataRecords(ofTypes: dataTypes)
        logger.debug("Found \(records.count) data records to clear")

        if !records.isEmpty {
            await dataStore.removeData(ofTypes: dataTypes, for: records)
            logger.debug("Cleared \(records.count) data records")
        }

        // Also clear all cookies to ensure complete cache clearing
        let httpCookieStore = dataStore.httpCookieStore
        let cookies = await httpCookieStore.allCookies()
        logger.debug("Found \(cookies.count) cookies to clear")

        if !cookies.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                for cookie in cookies {
                    group.addTask {
                        await httpCookieStore.delete(cookie)
                    }
                }
            }
            logger.debug("Cleared \(cookies.count) cookies")
        }

        logger.debug("Cache clearing complete")
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
            // Initial stability delay
            try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms

            // Scroll to trigger LCP and lazy content (matching Safari behavior)
            _ = try? await webView.evaluateJavaScript("window.scrollTo(0, 300);")
            try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms

            // Additional scroll for layout shifts
            _ = try? await webView.evaluateJavaScript("window.scrollTo(0, 600);")
            try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms

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

    /// Check if data is consistent enough to stop early (low variance)
    private func isDataConsistent(_ values: [Double]) -> Bool {
        guard values.count >= 4 else { return false }

        let sorted = values.sorted()
        let median = PerformanceTestResults.calculateMedian(sorted)
        guard let iqr = PerformanceTestResults.calculateIQR(sorted), median > 0 else {
            return false
        }

        // Calculate coefficient of variation (IQR/median as percentage)
        let coefficientOfVariation = (iqr / median) * 100

        // Calculate P95/P50 ratio for additional reliability check
        let p50Index = Int(Double(sorted.count - 1) * 0.50)
        let p95Index = Int(Double(sorted.count - 1) * 0.95)
        let p50 = sorted[p50Index]
        let p95 = sorted[p95Index]
        let ratio = p50 > 0 ? p95 / p50 : 999

        // Only stop early if we achieve "Good" or better consistency
        // Good: coeffVariation < 20% AND ratio < 2.0x
        // Excellent: coeffVariation < 10% AND ratio < 1.5x
        return coefficientOfVariation < 20.0 && ratio < 2.0
    }

}

/// Filter outliers using IQR method (Q1 - 1.5*IQR to Q3 + 1.5*IQR)
extension PerformanceTestResults {
    public static func filterOutliers(_ values: [Double]) -> [Double] {
        guard values.count >= 4 else { return values }  // Need at least 4 points for IQR

        let sorted = values.sorted()
        guard let iqr = calculateIQR(sorted) else { return values }

        let q1 = calculatePercentile(sorted, percentile: 0.25)
        let q3 = calculatePercentile(sorted, percentile: 0.75)

        let lowerBound = q1 - 1.5 * iqr
        let upperBound = q3 + 1.5 * iqr

        let filtered = sorted.filter { $0 >= lowerBound && $0 <= upperBound }

        // Only return filtered if we didn't remove too many points (keep at least 60%)
        return filtered.count >= Int(Double(values.count) * 0.6) ? filtered : values
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

    public var p25Time: TimeInterval? {
        return percentile(25)
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

        let sortedTimes = loadTimes.sorted()
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

    /// Interquartile Range - robust measure of spread
    /// IQR = Q3 - Q1 (75th percentile - 25th percentile)
    public var iqr: TimeInterval? {
        guard let q1 = p25Time, let q3 = p75Time else { return nil }
        return q3 - q1
    }

    /// Calculate IQR for any array of values (static helper)
    public static func calculateIQR(_ values: [Double]) -> Double? {
        guard values.count >= 3 else { return nil }  // Need at least 3 values for Q1, median, Q3

        let sorted = values.sorted()
        let count = Double(sorted.count)

        // Calculate Q1 (25th percentile)
        let q1Index = (count - 1) * 0.25
        let q1LowerIndex = Int(floor(q1Index))
        let q1UpperIndex = Int(ceil(q1Index))
        let q1 = q1LowerIndex == q1UpperIndex
            ? sorted[q1LowerIndex]
            : sorted[q1LowerIndex] + (q1Index - Double(q1LowerIndex)) * (sorted[q1UpperIndex] - sorted[q1LowerIndex])

        // Calculate Q3 (75th percentile)
        let q3Index = (count - 1) * 0.75
        let q3LowerIndex = Int(floor(q3Index))
        let q3UpperIndex = Int(ceil(q3Index))
        let q3 = q3LowerIndex == q3UpperIndex
            ? sorted[q3LowerIndex]
            : sorted[q3LowerIndex] + (q3Index - Double(q3LowerIndex)) * (sorted[q3UpperIndex] - sorted[q3LowerIndex])

        return q3 - q1
    }

    /// Calculate median for any array of values (static helper)
    public static func calculateMedian(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }

        let sorted = values.sorted()
        let count = sorted.count

        if count % 2 == 0 {
            return (sorted[count/2 - 1] + sorted[count/2]) / 2.0
        } else {
            return sorted[count/2]
        }
    }

    /// Calculate percentile for any array of values (static helper)
    public static func calculatePercentile(_ values: [Double], percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        guard percentile >= 0 && percentile <= 1.0 else { return 0 }

        let sorted = values.sorted()
        let count = Double(sorted.count)

        if percentile == 0 { return sorted.first ?? 0 }
        if percentile == 1.0 { return sorted.last ?? 0 }

        let index = percentile * (count - 1)
        let lowerIndex = Int(floor(index))
        let upperIndex = Int(ceil(index))

        if lowerIndex == upperIndex {
            return sorted[lowerIndex]
        }

        let weight = index - Double(lowerIndex)
        return sorted[lowerIndex] + weight * (sorted[upperIndex] - sorted[lowerIndex])
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
