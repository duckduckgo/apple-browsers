//
//  DetailedPerformanceMetrics.swift
//  PerformanceTest
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//

import Foundation

/// Detailed performance metrics matching spec requirements
public struct DetailedPerformanceMetrics: Codable {

    // Resource metrics
    public let decodedBodySize: [TimeInterval]
    public let encodedBodySize: [TimeInterval]
    public let transferSize: [TimeInterval]
    public let totalResourcesSize: [TimeInterval]
    public let resourceCount: [Int]

    // DOM metrics
    public let domComplete: [TimeInterval]
    public let domContentLoaded: [TimeInterval]
    public let domInteractive: [TimeInterval]

    // Timing metrics
    public let fcp: [TimeInterval]  // First Contentful Paint
    public let loadComplete: [TimeInterval]
    public let responseTime: [TimeInterval]
    public let serverTime: [TimeInterval]
    public let ttfb: [TimeInterval]  // Time to First Byte
    public let tti: [TimeInterval]   // Time to Interactive

    // Statistical aggregations for each metric
    public enum StatisticalView: String, CaseIterable {
        case mean = "Mean"
        case median = "Median"
        case min = "Min"
        case max = "Max"
        case p95 = "P95"
        case stdDev = "StdDev"
        case cv = "CV"
    }

    // MARK: - Statistical Methods

    public func getValue(for metric: MetricType, view: StatisticalView) -> Double? {
        let values: [Double]

        switch metric {
        case .decodedBodySize: values = decodedBodySize
        case .encodedBodySize: values = encodedBodySize
        case .transferSize: values = transferSize
        case .totalResourcesSize: values = totalResourcesSize
        case .resourceCount: values = resourceCount.map { Double($0) }
        case .domComplete: values = domComplete
        case .domContentLoaded: values = domContentLoaded
        case .domInteractive: values = domInteractive
        case .fcp: values = fcp
        case .loadComplete: values = loadComplete
        case .responseTime: values = responseTime
        case .serverTime: values = serverTime
        case .ttfb: values = ttfb
        case .tti: values = tti
        }

        guard !values.isEmpty else { return nil }

        switch view {
        case .mean:
            return values.reduce(0, +) / Double(values.count)
        case .median:
            return percentile(values, 50)
        case .min:
            return values.min()
        case .max:
            return values.max()
        case .p95:
            return percentile(values, 95)
        case .stdDev:
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { sum, value in
                sum + pow(value - mean, 2)
            } / Double(values.count)
            return sqrt(variance)
        case .cv:
            let mean = values.reduce(0, +) / Double(values.count)
            guard mean > 0 else { return nil }
            let stdDev = getValue(for: metric, view: .stdDev) ?? 0
            return (stdDev / mean) * 100
        }
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = (p / 100.0) * Double(sorted.count - 1)
        let lowerIndex = Int(floor(index))
        let upperIndex = Int(ceil(index))

        if lowerIndex == upperIndex {
            return sorted[lowerIndex]
        }

        let weight = index - Double(lowerIndex)
        return sorted[lowerIndex] + weight * (sorted[upperIndex] - sorted[lowerIndex])
    }

    public enum MetricType: String, CaseIterable {
        case decodedBodySize = "Decoded Body Size"
        case encodedBodySize = "Encoded Body Size"
        case transferSize = "Transfer Size"
        case totalResourcesSize = "Total Resources"
        case resourceCount = "Resource Count"
        case domComplete = "DOM Complete"
        case domContentLoaded = "DOM Content Loaded"
        case domInteractive = "DOM Interactive"
        case fcp = "FCP"
        case loadComplete = "Load Complete"
        case responseTime = "Response Time"
        case serverTime = "Server Time"
        case ttfb = "TTFB"
        case tti = "TTI"
    }
}
