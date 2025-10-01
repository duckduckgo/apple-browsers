//
//  PerformanceMetrics.swift
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

public struct PerformanceMetrics: Codable, Equatable {
    public let loadTime: TimeInterval

    public let firstContentfulPaint: TimeInterval?

    public let largestContentfulPaint: TimeInterval?

    public let timeToFirstByte: TimeInterval?

    public init(
        loadTime: TimeInterval,
        firstContentfulPaint: TimeInterval? = nil,
        largestContentfulPaint: TimeInterval? = nil,
        timeToFirstByte: TimeInterval? = nil
    ) {
        self.loadTime = max(0, loadTime)
        self.firstContentfulPaint = firstContentfulPaint
        self.largestContentfulPaint = largestContentfulPaint
        self.timeToFirstByte = timeToFirstByte
    }

    // MARK: - Computed Properties

    /// Performance score from 0-100 based on load time
    public var performanceScore: Int {
        // Handle edge cases
        if loadTime < 0 { return 0 }
        if loadTime == 0 { return 100 }

        // Score based on load time thresholds
        switch loadTime {
        case 0..<1.0:
            return 90 + Int((1.0 - loadTime) * 10) // 90-100
        case 1.0..<2.0:
            return 70 + Int((2.0 - loadTime) * 20) // 70-90
        case 2.0..<3.0:
            return 50 + Int((3.0 - loadTime) * 20) // 50-70
        case 3.0..<5.0:
            return 30 + Int((5.0 - loadTime) * 10) // 30-50
        default:
            return max(0, 30 - Int((loadTime - 5.0) * 2)) // 0-30
        }
    }

    /// Letter grade based on performance score
    public var performanceGrade: String {
        switch performanceScore {
        case 90...100:
            return "A"
        case 70..<90:
            return "B"
        case 50..<70:
            return "C"
        case 30..<50:
            return "D"
        default:
            return "F"
        }
    }

    /// Formatted display time
    public var displayTime: String {
        if loadTime < 1.0 {
            // Show milliseconds for sub-second times
            return String(format: "%.0fms", loadTime * 1000)
        } else {
            // Show seconds with 2 decimal places
            return String(format: "%.2fs", loadTime)
        }
    }

    // MARK: - Methods

    /// Compare performance with another metric
    public func isFasterThan(_ other: PerformanceMetrics) -> Bool {
        return loadTime < other.loadTime
    }
}
