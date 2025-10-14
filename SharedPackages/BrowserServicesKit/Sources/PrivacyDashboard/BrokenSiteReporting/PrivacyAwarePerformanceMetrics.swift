//
//  PrivacyAwarePerformanceMetrics.swift
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

/// Privacy-aware performance metrics for analytics transmission.
/// 
/// Converts raw performance data into privacy-safe buckets and rounded values
/// to prevent fingerprinting while maintaining analytical value.
public struct PrivacyAwarePerformanceMetrics {

    // MARK: - Core Web Vitals
    public let firstContentfulPaintMs: Int?
    public let largestContentfulPaintMs: Int?
    public let timeToFirstByteMs: Int?
    public let loadCompleteMs: Int?

    // MARK: - Size Metrics
    public let transferSizeBucket: SizeBucket?
    public let decodedBodySizeBucket: SizeBucket?
    public let encodedBodySizeBucket: SizeBucket?
    public let totalResourcesSizeBucket: SizeBucket?

    // MARK: - Resource Metrics
    public let resourceCountBucket: ResourceBucket?
    public let redirectCountBucket: RedirectBucket?

    // MARK: - DOM Metrics
    public let domInteractiveMs: Int?
    public let domCompleteMs: Int?
    public let domContentLoadedMs: Int?

    public init(
        firstContentfulPaintMs: Int? = nil,
        largestContentfulPaintMs: Int? = nil,
        timeToFirstByteMs: Int? = nil,
        loadCompleteMs: Int? = nil,
        transferSizeBucket: SizeBucket? = nil,
        decodedBodySizeBucket: SizeBucket? = nil,
        encodedBodySizeBucket: SizeBucket? = nil,
        totalResourcesSizeBucket: SizeBucket? = nil,
        resourceCountBucket: ResourceBucket? = nil,
        redirectCountBucket: RedirectBucket? = nil,
        domInteractiveMs: Int? = nil,
        domCompleteMs: Int? = nil,
        domContentLoadedMs: Int? = nil
    ) {
        self.firstContentfulPaintMs = firstContentfulPaintMs
        self.largestContentfulPaintMs = largestContentfulPaintMs
        self.timeToFirstByteMs = timeToFirstByteMs
        self.loadCompleteMs = loadCompleteMs
        self.transferSizeBucket = transferSizeBucket
        self.decodedBodySizeBucket = decodedBodySizeBucket
        self.encodedBodySizeBucket = encodedBodySizeBucket
        self.totalResourcesSizeBucket = totalResourcesSizeBucket
        self.resourceCountBucket = resourceCountBucket
        self.redirectCountBucket = redirectCountBucket
        self.domInteractiveMs = domInteractiveMs
        self.domCompleteMs = domCompleteMs
        self.domContentLoadedMs = domContentLoadedMs
    }

    /// Initialize from raw performance metrics with automatic privacy conversion
    public init(
        firstContentfulPaint: Double? = nil,
        largestContentfulPaint: Double? = nil,
        timeToFirstByte: Double? = nil,
        loadComplete: Double? = nil,
        transferSize: Double? = nil,
        decodedBodySize: Double? = nil,
        encodedBodySize: Double? = nil,
        totalResourcesSize: Double? = nil,
        resourceCount: Int? = nil,
        redirectCount: Int? = nil,
        domInteractive: Double? = nil,
        domComplete: Double? = nil,
        domContentLoaded: Double? = nil
    ) {
        self.firstContentfulPaintMs = firstContentfulPaint?.roundedToMilliseconds()
        self.largestContentfulPaintMs = largestContentfulPaint?.roundedToMilliseconds()
        self.timeToFirstByteMs = timeToFirstByte?.roundedToMilliseconds()
        self.loadCompleteMs = loadComplete?.roundedToMilliseconds()
        self.transferSizeBucket = transferSize.map { SizeBucket.from($0) }
        self.decodedBodySizeBucket = decodedBodySize.map { SizeBucket.from($0) }
        self.encodedBodySizeBucket = encodedBodySize.map { SizeBucket.from($0) }
        self.totalResourcesSizeBucket = totalResourcesSize.map { SizeBucket.from($0) }
        self.resourceCountBucket = resourceCount.map { ResourceBucket.from($0) }
        self.redirectCountBucket = redirectCount.map { RedirectBucket.from($0) }
        self.domInteractiveMs = domInteractive?.roundedToMilliseconds()
        self.domCompleteMs = domComplete?.roundedToMilliseconds()
        self.domContentLoadedMs = domContentLoaded?.roundedToMilliseconds()
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [:]

        if let firstContentfulPaintMs = firstContentfulPaintMs {
            dict["firstContentfulPaintMs"] = firstContentfulPaintMs
        }
        if let largestContentfulPaintMs = largestContentfulPaintMs {
            dict["largestContentfulPaintMs"] = largestContentfulPaintMs
        }
        if let timeToFirstByteMs = timeToFirstByteMs {
            dict["timeToFirstByteMs"] = timeToFirstByteMs
        }
        if let loadCompleteMs = loadCompleteMs {
            dict["loadCompleteMs"] = loadCompleteMs
        }
        if let transferSizeBucket = transferSizeBucket {
            dict["transferSizeBucket"] = transferSizeBucket.rawValue
        }
        if let decodedBodySizeBucket = decodedBodySizeBucket {
            dict["decodedBodySizeBucket"] = decodedBodySizeBucket.rawValue
        }
        if let encodedBodySizeBucket = encodedBodySizeBucket {
            dict["encodedBodySizeBucket"] = encodedBodySizeBucket.rawValue
        }
        if let totalResourcesSizeBucket = totalResourcesSizeBucket {
            dict["totalResourcesSizeBucket"] = totalResourcesSizeBucket.rawValue
        }
        if let resourceCountBucket = resourceCountBucket {
            dict["resourceCountBucket"] = resourceCountBucket.rawValue
        }
        if let redirectCountBucket = redirectCountBucket {
            dict["redirectCountBucket"] = redirectCountBucket.rawValue
        }
        if let domInteractiveMs = domInteractiveMs {
            dict["domInteractiveMs"] = domInteractiveMs
        }
        if let domCompleteMs = domCompleteMs {
            dict["domCompleteMs"] = domCompleteMs
        }
        if let domContentLoadedMs = domContentLoadedMs {
            dict["domContentLoadedMs"] = domContentLoadedMs
        }

        return dict
    }
}

// MARK: - Bucket Types

/// Size buckets to prevent precise fingerprinting
public enum SizeBucket: String, CaseIterable {
    case small = "small"          // < 1 MB
    case medium = "medium"        // 1-5 MB
    case large = "large"          // 5-10 MB
    case veryLarge = "very_large" // > 10 MB

    public static func from(_ bytes: Double) -> SizeBucket {
        let bytesInMB = 1_000_000.0
        let sizeInMB = bytes / bytesInMB

        switch sizeInMB {
        case 0..<1:
            return .small
        case 1..<5:
            return .medium
        case 5..<10:
            return .large
        default:
            return .veryLarge
        }
    }
}

/// Resource count buckets to prevent precise fingerprinting
public enum ResourceBucket: String, CaseIterable {
    case few              // 0-10 resources
    case moderate         // 11-50 resources
    case many             // 51-100 resources
    case excessive        // > 100 resources

    public static func from(_ count: Int) -> ResourceBucket {
        switch count {
        case 0...10:
            return .few
        case 11...50:
            return .moderate
        case 51...100:
            return .many
        default:
            return .excessive
        }
    }
}

/// Redirect count buckets to prevent precise fingerprinting
public enum RedirectBucket: String, CaseIterable {
    case none             // 0 redirects
    case few              // 1-3 redirects
    case moderate         // 4-10 redirects
    case many             // > 10 redirects

    public static func from(_ count: Int) -> RedirectBucket {
        switch count {
        case 0:
            return .none
        case 1...3:
            return .few
        case 4...10:
            return .moderate
        default:
            return .many
        }
    }
}

private extension Double {
    func roundedToMilliseconds() -> Int {
        return Int(self.rounded())
    }
}
