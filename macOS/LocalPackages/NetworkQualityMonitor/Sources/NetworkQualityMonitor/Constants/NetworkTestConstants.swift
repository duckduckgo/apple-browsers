//
//  NetworkTestConstants.swift
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

/// Shared constants used across multiple NetworkQualityMonitor services
public enum NetworkTestConstants {

    // MARK: - Shared Timing Constants

    enum Timing {
        static let nanosPerMillisecond: UInt64 = 1_000_000
        static let nanosPerSecond: UInt64 = 1_000_000_000
        static let millisPerSecond: Double = 1000
        static let megabitsPerByte: Double = 8.0 / 1_000_000

        // Sleep durations in nanoseconds
        static let measurementDelay: UInt64 = 50_000_000  // 50ms
        static let baselineSampleDelay: UInt64 = 100_000_000  // 100ms
        static let downloadStartDelay: UInt64 = 500_000_000  // 500ms
    }

    // MARK: - Statistical Utilities

    /// Calculates median value from an array of measurements
    /// For even-sized arrays, returns the average of the two middle values
    /// For odd-sized arrays, returns the middle value
    static func median(of measurements: [Double]) -> Double? {
        guard !measurements.isEmpty else { return nil }

        let sorted = measurements.sorted()
        let count = sorted.count

        if count % 2 == 0 {
            // Even number of elements - average the two middle values
            let midIndex1 = count / 2 - 1
            let midIndex2 = count / 2
            return (sorted[midIndex1] + sorted[midIndex2]) / 2.0
        } else {
            // Odd number of elements - return the middle value
            let midIndex = count / 2
            return sorted[midIndex]
        }
    }
}
