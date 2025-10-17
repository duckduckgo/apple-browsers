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

private enum PerformanceConstants {
    enum Protocols {
        static let http2 = "h2"
        static let http3 = "h3"
        static let quic = "quic"
        static let unknown = "unknown"
    }

    enum NavigationTypes {
        static let navigate = "navigate"
        static let reload = "reload"
        static let backForward = "back_forward"
    }

    enum Grades {
        static let gradeA = "A"
        static let gradeB = "B"
        static let gradeC = "C"
        static let gradeD = "D"
        static let gradeF = "F"
    }

    enum Assessments {
        static let good = "Good"
        static let needsImprovement = "Needs Improvement"
        static let poor = "Poor"
    }
}

public struct DetailedPerformanceMetrics: Codable, Equatable {
    private typealias Constants = PerformanceConstants

    public let loadComplete: TimeInterval

    public let domComplete: TimeInterval

    public let domContentLoaded: TimeInterval

    public let domInteractive: TimeInterval

    public let firstContentfulPaint: TimeInterval

    public let largestContentfulPaint: TimeInterval?

    public let timeToFirstByte: TimeInterval

    public let responseTime: TimeInterval

    public let serverTime: TimeInterval

    public let dnsLookupTime: TimeInterval?

    public let tcpConnectionTime: TimeInterval?

    public let secureConnectionTime: TimeInterval?

    public let transferSize: Double

    public let encodedBodySize: Double

    public let decodedBodySize: Double

    public let resourceCount: Int

    public let totalResourcesSize: Double

    public let timeToInteractive: TimeInterval?

    public let firstInputDelay: TimeInterval?

    public let cumulativeLayoutShift: Double?

    public let `protocol`: String?

    public let redirectCount: Int

    public let navigationType: String

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

    public var compressionRatio: Double? {
        guard encodedBodySize > 0 && decodedBodySize > 0 else { return nil }
        return 1.0 - (encodedBodySize / decodedBodySize)
    }

    public var usesModernProtocol: Bool {
        guard let proto = `protocol` else { return false }
        return proto.contains(Constants.Protocols.http2) ||
               proto.contains(Constants.Protocols.http3) ||
               proto.contains(Constants.Protocols.quic)
    }

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
        case 90...100: return Constants.Grades.gradeA
        case 80..<90: return Constants.Grades.gradeB
        case 70..<80: return Constants.Grades.gradeC
        case 60..<70: return Constants.Grades.gradeD
        default: return Constants.Grades.gradeF
        }
    }
}
