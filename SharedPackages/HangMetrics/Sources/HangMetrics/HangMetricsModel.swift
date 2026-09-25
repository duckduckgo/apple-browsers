//
//  HangMetricsModel.swift
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

/// One bucket of the MetricKit application-hang-time histogram, in milliseconds.
struct HangHistogramBucket: Equatable {
    let startMs: Double
    let endMs: Double
    let count: Int
}

/// A single MetricKit metric payload, reduced to only what we send.
struct HangMetricsReport {
    let appVersion: String
    let includesMultipleAppVersions: Bool
    let timeStampEnd: Date
    let buckets: [HangHistogramBucket]
}

/// One hang-histogram bucket to fire as a pixel. Unlike the launch metrics, a bucket is
/// sent as a single pixel carrying its count rather than one pixel per occurrence: hang
/// volume is bounded by how badly the app is behaving rather than by user behaviour, so
/// a pixel per hang would grow without limit exactly when the app is at its worst.
struct HangDataPoint: Equatable {
    let minMs: Int
    let maxMs: Int
    let count: Int
}
