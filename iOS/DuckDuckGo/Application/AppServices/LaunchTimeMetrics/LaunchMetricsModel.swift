//
//  LaunchMetricsModel.swift
//  DuckDuckGo
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

/// A MetricKit startup-time histogram category.
enum LaunchType: CaseIterable {
    case coldStart          // histogrammedTimeToFirstDraw
    case resume             // histogrammedApplicationResumeTime
    case optimizedFirstDraw // histogrammedOptimizedTimeToFirstDraw
}

/// One bucket of a MetricKit launch-time histogram, in milliseconds.
struct LaunchHistogramBucket: Equatable {
    let startMs: Double
    let endMs: Double
    let count: Int
}

/// A single MetricKit metric payload, reduced to only what we send.
struct LaunchMetricsReport {
    let appVersion: String
    let includesMultipleAppVersions: Bool
    let timeStampEnd: Date
    let histograms: [LaunchType: [LaunchHistogramBucket]]
}

/// One launch-time observation to fire as a pixel.
struct LaunchTimeDataPoint: Equatable {
    let launchType: LaunchType
    let minMs: Double
    let maxMs: Double
}
