//
//  DetailedPerformanceMetrics.swift
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

/// Extended performance metrics with detailed timing information
public struct DetailedPerformanceMetrics: Codable, Equatable {

    // MARK: - Core Timing Properties

    /// Total page load completion time in seconds
    public let loadComplete: TimeInterval

    /// DOM complete time in seconds
    public let domComplete: TimeInterval

    /// DOM content loaded time in seconds
    public let domContentLoaded: TimeInterval

    /// DOM interactive time in seconds
    public let domInteractive: TimeInterval

    // MARK: - Paint Metrics

    /// First Contentful Paint (FCP) in seconds
    public let firstContentfulPaint: TimeInterval

    /// Largest Contentful Paint (LCP) in seconds (optional)
    public let largestContentfulPaint: TimeInterval?

    // MARK: - Network Timing

    /// Time to First Byte (TTFB) in seconds
    public let timeToFirstByte: TimeInterval

    /// Response download time in seconds
    public let responseTime: TimeInterval

    /// Server processing time in seconds
    public let serverTime: TimeInterval

    /// DNS lookup time in seconds
    public let dnsLookupTime: TimeInterval?

    /// TCP connection time in seconds
    public let tcpConnectionTime: TimeInterval?

    /// Secure connection (TLS) time in seconds
    public let secureConnectionTime: TimeInterval?

    // MARK: - Size Metrics

    /// Total transfer size in bytes
    public let transferSize: Double

    /// Encoded body size in bytes
    public let encodedBodySize: Double

    /// Decoded body size in bytes
    public let decodedBodySize: Double

    // MARK: - Resource Metrics

    /// Number of resources loaded
    public let resourceCount: Int

    /// Total size of all resources in bytes
    public let totalResourcesSize: Double

    // MARK: - Interactivity Metrics

    /// Time to Interactive (TTI) in seconds
    public let timeToInteractive: TimeInterval?

    /// First Input Delay (FID) in milliseconds
    public let firstInputDelay: TimeInterval?

    /// Cumulative Layout Shift (CLS) score
    public let cumulativeLayoutShift: Double?

    // MARK: - Additional Metadata

    /// Network protocol used (e.g., "h2", "http/1.1")
    public let `protocol`: String?

    /// Number of redirects
    public let redirectCount: Int

    /// Navigation type (e.g., "navigate", "reload", "back_forward")
    public let navigationType: String

    // MARK: - Initialization

    public init(
        loadComplete: TimeInterval,
        domComplete: TimeInterval,
        domContentLoaded: TimeInterval,
        domInteractive: TimeInterval,
        firstContentfulPaint: TimeInterval,
        largestContentfulPaint: TimeInterval? = nil,
        timeToFirstByte: TimeInterval,
        responseTime: TimeInterval,
        serverTime: TimeInterval,
        dnsLookupTime: TimeInterval? = nil,
        tcpConnectionTime: TimeInterval? = nil,
        secureConnectionTime: TimeInterval? = nil,
        transferSize: Double,
        encodedBodySize: Double,
        decodedBodySize: Double,
        resourceCount: Int,
        totalResourcesSize: Double,
        timeToInteractive: TimeInterval? = nil,
        firstInputDelay: TimeInterval? = nil,
        cumulativeLayoutShift: Double? = nil,
        `protocol`: String? = nil,
        redirectCount: Int = 0,
        navigationType: String = "navigate"
    ) {
        self.loadComplete = max(0, loadComplete)
        self.domComplete = max(0, domComplete)
        self.domContentLoaded = max(0, domContentLoaded)
        self.domInteractive = max(0, domInteractive)
        self.firstContentfulPaint = max(0, firstContentfulPaint)
        self.largestContentfulPaint = largestContentfulPaint
        self.timeToFirstByte = max(0, timeToFirstByte)
        self.responseTime = max(0, responseTime)
        self.serverTime = max(0, serverTime)
        self.dnsLookupTime = dnsLookupTime
        self.tcpConnectionTime = tcpConnectionTime
        self.secureConnectionTime = secureConnectionTime
        self.transferSize = max(0, transferSize)
        self.encodedBodySize = max(0, encodedBodySize)
        self.decodedBodySize = max(0, decodedBodySize)
        self.resourceCount = max(0, resourceCount)
        self.totalResourcesSize = max(0, totalResourcesSize)
        self.timeToInteractive = timeToInteractive
        self.firstInputDelay = firstInputDelay
        self.cumulativeLayoutShift = cumulativeLayoutShift
        self.`protocol` = `protocol`
        self.redirectCount = max(0, redirectCount)
        self.navigationType = navigationType
    }

    // MARK: - Computed Properties

    /// Compression ratio (encoded vs decoded size)
    public var compressionRatio: Double? {
        guard encodedBodySize > 0 && decodedBodySize > 0 else { return nil }
        return 1.0 - (encodedBodySize / decodedBodySize)
    }

    /// Average resource size in bytes
    public var averageResourceSize: Double? {
        guard resourceCount > 0 else { return nil }
        return totalResourcesSize / Double(resourceCount)
    }

    /// Whether the page used HTTP/2 or newer
    public var usesModernProtocol: Bool {
        guard let proto = `protocol` else { return false }
        return proto.contains("h2") || proto.contains("h3") || proto.contains("quic")
    }

    /// Core Web Vitals assessment
    public var coreWebVitals: CoreWebVitalsAssessment {
        CoreWebVitalsAssessment(
            lcp: largestContentfulPaint ?? firstContentfulPaint,
            fid: firstInputDelay,
            cls: cumulativeLayoutShift
        )
    }

    // MARK: - Performance Score

    /// Overall performance score (0-100)
    public var performanceScore: Int {
        var score = 100.0

        // Weight different metrics
        // LCP/FCP: 25%
        let paintMetric = largestContentfulPaint ?? firstContentfulPaint
        if paintMetric > 4.0 {
            score -= 25
        } else if paintMetric > 2.5 {
            score -= 12.5
        }

        // TTFB: 15%
        if timeToFirstByte > 1.8 {
            score -= 15
        } else if timeToFirstByte > 0.8 {
            score -= 7.5
        }

        // Load Complete: 20%
        if loadComplete > 5.0 {
            score -= 20
        } else if loadComplete > 3.0 {
            score -= 10
        }

        // DOM Interactive: 15%
        if domInteractive > 3.5 {
            score -= 15
        } else if domInteractive > 2.0 {
            score -= 7.5
        }

        // Resource optimization: 10%
        if totalResourcesSize > 5_000_000 { // > 5MB
            score -= 10
        } else if totalResourcesSize > 2_000_000 { // > 2MB
            score -= 5
        }

        // Protocol bonus: 5%
        if !usesModernProtocol {
            score -= 5
        }

        // Compression bonus: 5%
        if let ratio = compressionRatio, ratio < 0.5 {
            score -= 5
        }

        // CLS penalty: 5%
        if let cls = cumulativeLayoutShift, cls > 0.25 {
            score -= 5
        }

        return max(0, min(100, Int(score)))
    }

    /// Performance grade based on score
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

// MARK: - Core Web Vitals Assessment

public struct CoreWebVitalsAssessment: Codable, Equatable {
    public let lcp: TimeInterval // Largest Contentful Paint
    public let fid: TimeInterval? // First Input Delay
    public let cls: Double? // Cumulative Layout Shift

    public var lcpAssessment: String {
        if lcp <= 2.5 { return "Good" }
        else if lcp <= 4.0 { return "Needs Improvement" }
        else { return "Poor" }
    }

    public var fidAssessment: String? {
        guard let fid = fid else { return nil }
        if fid <= 0.1 { return "Good" }
        else if fid <= 0.3 { return "Needs Improvement" }
        else { return "Poor" }
    }

    public var clsAssessment: String? {
        guard let cls = cls else { return nil }
        if cls <= 0.1 { return "Good" }
        else if cls <= 0.25 { return "Needs Improvement" }
        else { return "Poor" }
    }

    public var overallAssessment: String {
        let assessments = [lcpAssessment, fidAssessment, clsAssessment].compactMap { $0 }
        let poorCount = assessments.filter { $0 == "Poor" }.count
        let needsImprovementCount = assessments.filter { $0 == "Needs Improvement" }.count

        if poorCount > 0 { return "Poor" }
        else if needsImprovementCount > 1 { return "Needs Improvement" }
        else { return "Good" }
    }
}