//
//  PerformanceMetrics.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Unified performance metrics extracted from JavaScript payloads
public struct PerformanceMetrics {
    // Core Web Vitals
    public let firstContentfulPaint: Double?
    public let largestContentfulPaint: Double?
    public let timeToFirstByte: Double?
    public let loadComplete: Double?

    // Size Metrics
    public let transferSize: Double?
    public let decodedBodySize: Double?
    public let encodedBodySize: Double?
    public let totalResourcesSize: Double?

    // Resource Metrics
    public let resourceCount: Int?
    public let redirectCount: Int?

    // Network Metrics
    public let networkProtocol: String?
    public let serverTime: Double?
    public let responseTime: Double?

    // DOM Metrics
    public let domInteractive: Double?
    public let domComplete: Double?
    public let domContentLoaded: Double?

    // Navigation Metrics
    public let navigationType: String?

    /// Initialize from metrics dictionary
    public init(from metrics: [String: Any]) {
        self.firstContentfulPaint = metrics["firstContentfulPaint"] as? Double
        self.largestContentfulPaint = metrics["largestContentfulPaint"] as? Double
        self.timeToFirstByte = metrics["timeToFirstByte"] as? Double
        self.loadComplete = metrics["loadComplete"] as? Double
        self.transferSize = metrics["transferSize"] as? Double
        self.decodedBodySize = metrics["decodedBodySize"] as? Double
        self.encodedBodySize = metrics["encodedBodySize"] as? Double
        self.totalResourcesSize = metrics["totalResourcesSize"] as? Double
        self.resourceCount = metrics["resourceCount"] as? Int
        self.redirectCount = metrics["redirectCount"] as? Int
        self.networkProtocol = metrics["protocol"] as? String
        self.serverTime = metrics["serverTime"] as? Double
        self.responseTime = metrics["responseTime"] as? Double
        self.domInteractive = metrics["domInteractive"] as? Double
        self.domComplete = metrics["domComplete"] as? Double
        self.domContentLoaded = metrics["domContentLoaded"] as? Double
        self.navigationType = metrics["navigationType"] as? String
    }

    /// Convert to privacy-aware metrics for analytics
    public func privacyAwareMetrics() -> PrivacyAwarePerformanceMetrics {
        return PrivacyAwarePerformanceMetrics(
            firstContentfulPaint: firstContentfulPaint,
            largestContentfulPaint: largestContentfulPaint,
            timeToFirstByte: timeToFirstByte,
            loadComplete: loadComplete,
            transferSize: transferSize,
            decodedBodySize: decodedBodySize,
            encodedBodySize: encodedBodySize,
            totalResourcesSize: totalResourcesSize,
            resourceCount: resourceCount,
            redirectCount: redirectCount,
            domInteractive: domInteractive,
            domComplete: domComplete,
            domContentLoaded: domContentLoaded
        )
    }
}
