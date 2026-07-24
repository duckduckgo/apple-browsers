//
//  LaunchTimeMetricsProcessor.swift
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

/// Turns MetricKit launch reports into the list of pixels to send,
/// applying the recency, version and dedup rules. No MetricKit dependency for testability.
struct LaunchTimeMetricsProcessor {

    /// Only data whose reporting period ended within the last 24 hours is sent
    static let recencyWindow: TimeInterval = 24 * 60 * 60

    func dataPointsToSendPixelsFor(from reports: [LaunchMetricsReport],
                                   currentAppVersion: String,
                                   now: Date,
                                   lastProcessedEnd: Date?) -> [LaunchTimeDataPoint] {
        var result: [LaunchTimeDataPoint] = []
        let earliestAllowed = now.addingTimeInterval(-Self.recencyWindow)

        for report in reports {

            /// Skip if the report is:
            ///     older than the last one we processed
            ///     isn't solely for the app version we are currently on
            ///     it's older than the recency window
            if let lastProcessedEnd = lastProcessedEnd,
                report.timeStampEnd <= lastProcessedEnd { continue }
            if report.includesMultipleAppVersions { continue }
            if report.appVersion != currentAppVersion { continue }
            if report.timeStampEnd < earliestAllowed { continue }

            for launchType in LaunchType.allCases {
                guard let buckets = report.histograms[launchType] else { continue }
                for bucket in buckets where bucket.count > 0 {
                    let point = LaunchTimeDataPoint(launchType: launchType,
                                                    minMs: bucket.startMs,
                                                    maxMs: bucket.endMs)
                    result.append(contentsOf: Array(repeating: point, count: bucket.count))
                }
            }
        }
        return result
    }

    /// The newest reporting-period end across all received reports, used as the dedup marker.
    func newestTimestamp(in reports: [LaunchMetricsReport]) -> Date? {
        reports.map(\.timeStampEnd).max()
    }
}
