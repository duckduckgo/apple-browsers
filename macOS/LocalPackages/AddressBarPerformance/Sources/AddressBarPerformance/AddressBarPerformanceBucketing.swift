//
//  AddressBarPerformanceBucketing.swift
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

/// Buckets a list of millisecond latency measurements into a fixed nine-band histogram,
/// expressing each band's share of the total as basis points (0..10000, where 10000 = 100%).
///
/// Bands (upper-inclusive milliseconds): 0..16, 16..50, 50..100, 100..150, 150..200,
/// 200..300, 300..500, 500..1000, 1000+. A sample of exactly 100ms lands in 50..100
/// (the SLO-pass side), so the "p75 ≤ 100ms" SLO reads directly off the cumulative
/// through `bp_50_100`.
///
/// Per-band value: `floor(count[i] * 10000 / N)`.
/// Per-pixel sums fall in [9992, 10000] (floor-rounding loss).
enum AddressBarPerformanceBucketing {

    /// Number of histogram bands.
    static let bandCount = 9

    /// Upper-inclusive boundaries for bands 0..7. Band 8 is unbounded.
    private static let bandUpperBoundsMs: [Int] = [16, 50, 100, 150, 200, 300, 500, 1000]

    /// Returns a 9-element basis-points histogram for `samples`. Empty input yields all zeros.
    static func basisPoints(for samples: [Int]) -> [Int] {
        guard !samples.isEmpty else {
            return Array(repeating: 0, count: bandCount)
        }
        var counts = Array(repeating: 0, count: bandCount)
        for sample in samples {
            counts[bandIndex(for: sample)] += 1
        }
        let total = samples.count
        return counts.map { ($0 * 10000) / total }
    }

    /// Returns the band index (0..8) for a single millisecond sample, using upper-inclusive boundaries.
    static func bandIndex(for sampleMs: Int) -> Int {
        for (index, upperBound) in bandUpperBoundsMs.enumerated() where sampleMs <= upperBound {
            return index
        }
        return bandCount - 1
    }
}
