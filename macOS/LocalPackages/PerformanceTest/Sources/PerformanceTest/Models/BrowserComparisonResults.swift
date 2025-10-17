//
//  BrowserComparisonResults.swift
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

/// Represents which browser performed better for a given metric
public enum BrowserWinner {
    case duckduckgo
    case safari
    case tie
}

/// Results from comparing performance tests between DuckDuckGo and Safari
public struct BrowserComparisonResults {
    public let url: URL
    public let duckDuckGoResults: PerformanceTestResults
    public let safariResults: PerformanceTestResults
    public let iterations: Int

    public init(
        url: URL,
        duckDuckGoResults: PerformanceTestResults,
        safariResults: PerformanceTestResults,
        iterations: Int
    ) {
        self.url = url
        self.duckDuckGoResults = duckDuckGoResults
        self.safariResults = safariResults
        self.iterations = iterations
    }

    // MARK: - Metric Comparison Helpers

    /// Calculate percentage difference between two values
    /// Returns positive if Safari is faster, negative if DuckDuckGo is faster
    public func percentageDifference(_ duckduckgoValue: Double, _ safariValue: Double) -> Double {
        let maxValue = max(duckduckgoValue, safariValue)
        guard maxValue > 0 else { return 0 }
        return ((duckduckgoValue - safariValue) / maxValue) * 100
    }

    /// Determine which browser won for a time-based metric (lower is better)
    /// Uses statistical significance testing to determine if differences are meaningful
    /// - Parameters:
    ///   - duckduckgoValue: Median time value for DuckDuckGo
    ///   - safariValue: Median time value for Safari
    ///   - ddgStdDev: IQR (Interquartile Range) for DuckDuckGo, automatically converted to std dev
    ///   - safariStdDev: IQR (Interquartile Range) for Safari, automatically converted to std dev
    /// - Returns: Winner based on 95% confidence interval testing
    /// - Note: IQR values are converted to standard deviation using σ ≈ IQR/1.349 (assumes normal distribution)
    public func timeBasedWinner(_ duckduckgoValue: Double, _ safariValue: Double, ddgStdDev: Double = 0, safariStdDev: Double = 0) -> BrowserWinner {
        // Check if the difference is statistically significant
        let diff = abs(duckduckgoValue - safariValue)

        // If we have IQR data, convert to standard deviation and use it for significance testing
        if ddgStdDev > 0 || safariStdDev > 0 {
            // Convert IQR to approximate standard deviation: σ ≈ IQR/1.349
            // This assumes a normal distribution where IQR ≈ 1.349σ
            let ddgStdDevConverted = ddgStdDev / 1.349
            let safariStdDevConverted = safariStdDev / 1.349

            // Use proper quadrature for combining standard deviations: sqrt(σ1² + σ2²)
            let combinedStdDev = sqrt(ddgStdDevConverted * ddgStdDevConverted + safariStdDevConverted * safariStdDevConverted)

            // Use 1.96 multiplier for 95% confidence interval (two-tailed test)
            let confidenceMargin = 1.96 * combinedStdDev

            // Difference must be greater than confidence margin to be significant
            if diff < confidenceMargin {
                return .tie
            }
        } else {
            // Fallback to percentage threshold if no std dev data
            let threshold = 0.01 // 1% threshold for "tie"
            let percentDiff = diff / max(duckduckgoValue, safariValue)

            if percentDiff < threshold {
                return .tie
            }
        }

        return safariValue < duckduckgoValue ? .safari : .duckduckgo
    }

    /// Determine which browser won for a size-based metric (smaller is better)
    /// Uses statistical significance testing to determine if differences are meaningful
    /// - Parameters:
    ///   - duckduckgoValue: Median size value for DuckDuckGo
    ///   - safariValue: Median size value for Safari
    ///   - ddgStdDev: IQR (Interquartile Range) for DuckDuckGo, automatically converted to std dev
    ///   - safariStdDev: IQR (Interquartile Range) for Safari, automatically converted to std dev
    /// - Returns: Winner based on 95% confidence interval testing
    /// - Note: IQR values are converted to standard deviation using σ ≈ IQR/1.349 (assumes normal distribution)
    public func sizeBasedWinner(_ duckduckgoValue: Double, _ safariValue: Double, ddgStdDev: Double = 0, safariStdDev: Double = 0) -> BrowserWinner {
        // Check if the difference is statistically significant
        let diff = abs(duckduckgoValue - safariValue)

        // If we have IQR data, convert to standard deviation and use it for significance testing
        if ddgStdDev > 0 || safariStdDev > 0 {
            // Convert IQR to approximate standard deviation: σ ≈ IQR/1.349
            // This assumes a normal distribution where IQR ≈ 1.349σ
            let ddgStdDevConverted = ddgStdDev / 1.349
            let safariStdDevConverted = safariStdDev / 1.349

            // Use proper quadrature for combining standard deviations: sqrt(σ1² + σ2²)
            let combinedStdDev = sqrt(ddgStdDevConverted * ddgStdDevConverted + safariStdDevConverted * safariStdDevConverted)

            // Use 1.96 multiplier for 95% confidence interval (two-tailed test)
            let confidenceMargin = 1.96 * combinedStdDev

            // Difference must be greater than confidence margin to be significant
            if diff < confidenceMargin {
                return .tie
            }
        } else {
            // Fallback to percentage threshold if no std dev data
            let threshold = 0.01 // 1% threshold for "tie"
            let percentDiff = diff / max(duckduckgoValue, safariValue)

            if percentDiff < threshold {
                return .tie
            }
        }

        return safariValue < duckduckgoValue ? .safari : .duckduckgo
    }

    // MARK: - Helper Methods

    private func getMedian(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }

        // Filter outliers using IQR method for more accurate median
        let filtered = PerformanceTestResults.filterOutliers(values)
        let sorted = filtered.sorted()
        let count = sorted.count

        if count % 2 == 0 {
            return (sorted[count/2 - 1] + sorted[count/2]) / 2.0
        } else {
            return sorted[count/2]
        }
    }

    // MARK: - JSON Export

    /// Export results to JSON format
    public func exportToJSON() -> Data? {
        let exportData: [String: Any] = [
            "url": url.absoluteString,
            "testDate": ISO8601DateFormatter().string(from: Date()),
            "iterations": iterations,
            "duckduckgo": browserData(from: duckDuckGoResults, browser: "DuckDuckGo"),
            "safari": browserData(from: safariResults, browser: "Safari"),
            "comparison": comparisonData()
        ]

        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }

    private func browserData(from results: PerformanceTestResults, browser: String) -> [String: Any] {
        // Calculate statistics for all metrics
        let metrics = results.detailedMetrics

        return [
            "browser": browser,
            "iterations": results.iterations,
            "failedAttempts": results.failedAttempts,
            "reliability": results.reliabilityScore,
            "metrics": [
                "loadComplete": metricStats(metrics.loadComplete),
                "domComplete": metricStats(metrics.domComplete),
                "domContentLoaded": metricStats(metrics.domContentLoaded),
                "domInteractive": metricStats(metrics.domInteractive),
                "firstContentfulPaint": metricStats(metrics.fcp),
                "timeToFirstByte": metricStats(metrics.ttfb),
                "responseTime": metricStats(metrics.responseTime),
                "serverTime": metricStats(metrics.serverTime),
                "transferSize": metricStats(metrics.transferSize),
                "decodedBodySize": metricStats(metrics.decodedBodySize),
                "encodedBodySize": metricStats(metrics.encodedBodySize),
                "resourceCount": metricStats(metrics.resourceCount.map { Double($0) })
            ],
            "rawData": [
                "loadComplete": metrics.loadComplete,
                "domComplete": metrics.domComplete,
                "domContentLoaded": metrics.domContentLoaded,
                "domInteractive": metrics.domInteractive,
                "firstContentfulPaint": metrics.fcp,
                "timeToFirstByte": metrics.ttfb,
                "responseTime": metrics.responseTime,
                "serverTime": metrics.serverTime,
                "transferSize": metrics.transferSize,
                "decodedBodySize": metrics.decodedBodySize,
                "encodedBodySize": metrics.encodedBodySize,
                "resourceCount": metrics.resourceCount
            ]
        ]
    }

    private func metricStats(_ values: [Double]) -> [String: Any] {
        guard !values.isEmpty else { return [:] }

        // Filter outliers using IQR method for more accurate statistics
        let filtered = PerformanceTestResults.filterOutliers(values)
        let sorted = filtered.sorted()

        let minValue: Double = sorted.first ?? 0
        let maxValue: Double = sorted.last ?? 0

        return [
            "median": getMedian(values),
            "mean": sorted.reduce(0, +) / Double(sorted.count),
            "min": minValue,
            "max": maxValue,
            "p95": calculatePercentile(sorted, percentile: 0.95),
            "iqr": PerformanceTestResults.calculateIQR(sorted) ?? 0
        ]
    }

    private func calculatePercentile(_ sorted: [Double], percentile: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = percentile * Double(sorted.count - 1)
        let lowerIndex = Int(floor(index))
        let upperIndex = Int(ceil(index))

        if lowerIndex == upperIndex {
            return sorted[lowerIndex]
        }

        let weight = index - Double(lowerIndex)
        return sorted[lowerIndex] + weight * (sorted[upperIndex] - sorted[lowerIndex])
    }

    private func comparisonData() -> [String: Any] {
        return [
            "loadComplete": metricComparison(
                duckDuckGoResults.detailedMetrics.loadComplete,
                safariResults.detailedMetrics.loadComplete,
                isTime: true
            ),
            "domComplete": metricComparison(
                duckDuckGoResults.detailedMetrics.domComplete,
                safariResults.detailedMetrics.domComplete,
                isTime: true
            ),
            "domContentLoaded": metricComparison(
                duckDuckGoResults.detailedMetrics.domContentLoaded,
                safariResults.detailedMetrics.domContentLoaded,
                isTime: true
            ),
            "domInteractive": metricComparison(
                duckDuckGoResults.detailedMetrics.domInteractive,
                safariResults.detailedMetrics.domInteractive,
                isTime: true
            ),
            "firstContentfulPaint": metricComparison(
                duckDuckGoResults.detailedMetrics.fcp,
                safariResults.detailedMetrics.fcp,
                isTime: true
            ),
            "timeToFirstByte": metricComparison(
                duckDuckGoResults.detailedMetrics.ttfb,
                safariResults.detailedMetrics.ttfb,
                isTime: true
            ),
            "responseTime": metricComparison(
                duckDuckGoResults.detailedMetrics.responseTime,
                safariResults.detailedMetrics.responseTime,
                isTime: true
            ),
            "serverTime": metricComparison(
                duckDuckGoResults.detailedMetrics.serverTime,
                safariResults.detailedMetrics.serverTime,
                isTime: true
            ),
            "transferSize": metricComparison(
                duckDuckGoResults.detailedMetrics.transferSize,
                safariResults.detailedMetrics.transferSize,
                isTime: false
            ),
            "decodedBodySize": metricComparison(
                duckDuckGoResults.detailedMetrics.decodedBodySize,
                safariResults.detailedMetrics.decodedBodySize,
                isTime: false
            ),
            "encodedBodySize": metricComparison(
                duckDuckGoResults.detailedMetrics.encodedBodySize,
                safariResults.detailedMetrics.encodedBodySize,
                isTime: false
            ),
            "resourceCount": metricComparison(
                duckDuckGoResults.detailedMetrics.resourceCount.map { Double($0) },
                safariResults.detailedMetrics.resourceCount.map { Double($0) },
                isTime: false
            )
        ]
    }

    private func metricComparison(_ ddgValues: [Double], _ safariValues: [Double], isTime: Bool) -> [String: Any] {
        let ddgMedian = getMedian(ddgValues)
        let safariMedian = getMedian(safariValues)

        // Filter outliers before calculating IQR
        let ddgFiltered = PerformanceTestResults.filterOutliers(ddgValues)
        let safariFiltered = PerformanceTestResults.filterOutliers(safariValues)

        let ddgIQR = PerformanceTestResults.calculateIQR(ddgFiltered) ?? 0
        let safariIQR = PerformanceTestResults.calculateIQR(safariFiltered) ?? 0

        let winner = isTime ?
            timeBasedWinner(ddgMedian, safariMedian, ddgStdDev: ddgIQR, safariStdDev: safariIQR) :
            sizeBasedWinner(ddgMedian, safariMedian, ddgStdDev: ddgIQR, safariStdDev: safariIQR)

        return [
            "duckduckgoMedian": ddgMedian,
            "safariMedian": safariMedian,
            "percentageDifference": percentageDifference(ddgMedian, safariMedian),
            "winner": winnerString(winner)
        ]
    }

    private func winnerString(_ winner: BrowserWinner) -> String {
        switch winner {
        case .duckduckgo: return "DuckDuckGo"
        case .safari: return "Safari"
        case .tie: return "Tie"
        }
    }
}
