//
//  StartupMetricsBuckets.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

// MARK: - StartupMetricsBuckets

enum StartupMetricsBuckets {

    /// Buckets an active processor count into predefined ranges.
    /// - Returns: Lower bound of the matching range: `"1"`, `"2"`, `"4"`, `"8"`, or `"12"`.
    ///
    static func bucketProcessorCount(_ count: Int) -> String {
        switch count {
        case ..<2:
            return "1"
        case ..<4:
            return "2"
        case ..<8:
            return "4"
        case ..<12:
            return "8"
        default:
            return "12"
        }
    }

    /// Buckets a window count into predefined ranges.
    /// - Returns: Lower bound of the matching range: `"0"`, `"1"`, `"2"`, `"4"`, `"7"`, `"11"`, or `"21"`.
    ///
    static func bucketWindowCount(_ count: Int) -> String {
        switch count {
        case ..<1:
            return "0"
        case 1:
            return "1"
        case 2..<4:
            return "2"
        case 4..<7:
            return "4"
        case 7..<11:
            return "7"
        case 11..<21:
            return "11"
        default:
            return "21"
        }
    }

    /// Buckets a tab count into predefined ranges.
    /// - Returns: Lower bound of the matching range: `"0"`, `"1"`, `"2"`, `"4"`, `"7"`, `"11"`, `"21"`, or `"51"`.
    ///
    static func bucketTabCount(_ count: Int) -> String {
        switch count {
        case ..<1:
            return "0"
        case 1:
            return "1"
        case 2..<4:
            return "2"
        case 4..<7:
            return "4"
        case 7..<11:
            return "7"
        case 11..<21:
            return "11"
        case 21..<51:
            return "21"
        default:
            return "51"
        }
    }

    /// Buckets a `TimeInterval` (in seconds) into a millisecond range and returns the result as a `String`.
    ///
    static func bucketMilliseconds(_ seconds: TimeInterval) -> String {
        bucketMillisecondsAsInt(seconds).description
    }

    /// Returns the `TimeInterval` expressed as milliseconds, rounded down to 5ms
    ///
    private static func bucketMillisecondsAsInt(_ seconds: TimeInterval) -> Int {
        let ms = Int(seconds * 1000)
        let remainder = (ms % 5)

        return ms - remainder
    }
}
