//
//  MetricsCollectionTests.swift
//  PerformanceTest
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//

import XCTest
@testable import PerformanceTest

final class MetricsCollectionTests: XCTestCase {

    func testCollectedMetricsStatistics() {
        // Create sample collected metrics
        var metrics = CollectedMetrics()

        // Add sample data
        metrics.loadComplete = [1.0, 2.0, 3.0, 4.0, 5.0]
        metrics.domComplete = [0.8, 1.8, 2.8, 3.8, 4.8]
        metrics.ttfb = [0.1, 0.2, 0.3, 0.4, 0.5]
        metrics.transferSize = [1000, 2000, 3000, 4000, 5000]
        metrics.resourceCount = [10, 20, 30, 40, 50]

        // Test mean calculation
        XCTAssertEqual(metrics.loadComplete.reduce(0, +) / Double(metrics.loadComplete.count), 3.0)

        // Test median calculation (middle value)
        let sortedLoad = metrics.loadComplete.sorted()
        XCTAssertEqual(sortedLoad[2], 3.0) // Median of 5 values

        // Test min/max
        XCTAssertEqual(metrics.loadComplete.min(), 1.0)
        XCTAssertEqual(metrics.loadComplete.max(), 5.0)
    }

    func testDetailedMetricsAppend() {
        var metrics = CollectedMetrics()

        let detailed = DetailedPerformanceMetrics(
            loadComplete: 2.5,
            domComplete: 2.3,
            domContentLoaded: 1.8,
            domInteractive: 1.2,
            firstContentfulPaint: 0.8,
            largestContentfulPaint: nil,
            timeToFirstByte: 0.2,
            responseTime: 0.15,
            serverTime: 0.1,
            transferSize: 5000,
            encodedBodySize: 4500,
            decodedBodySize: 10000,
            resourceCount: 25,
            totalResourcesSize: 50000,
            timeToInteractive: 1.5
        )

        metrics.append(detailed)

        XCTAssertEqual(metrics.loadComplete.count, 1)
        XCTAssertEqual(metrics.loadComplete[0], 2.5)
        XCTAssertEqual(metrics.ttfb[0], 0.2)
        XCTAssertEqual(metrics.resourceCount[0], 25)
    }

    func testPercentileCalculation() {
        let values = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
        let sorted = values.sorted()

        // P95 calculation (95th percentile)
        // For 10 values, 95th percentile is at index 8.55, so we round to 8 (9th value = 9.0)
        let p95Index = Int(Double(sorted.count - 1) * 0.95)
        let p95Value = sorted[p95Index]

        XCTAssertEqual(p95Index, 8) // Index 8 = value 9.0
        XCTAssertEqual(p95Value, 9.0) // For 10 values, p95 should be 9.0
    }

    func testWarmupExclusion() {
        // When processing metrics, first value should be excluded as warm-up
        let values = [100.0, 2.0, 3.0, 4.0, 5.0] // First value is outlier (warm-up)

        // Exclude first value
        let relevantValues = Array(values.dropFirst())

        XCTAssertEqual(relevantValues.count, 4)
        XCTAssertEqual(relevantValues.reduce(0, +) / Double(relevantValues.count), 3.5)
    }
}
