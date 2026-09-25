//
//  HangMetricsProcessor.swift
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

/// Turns MetricKit hang reports into the list of pixels to send,
/// applying the recency, version and dedup rules. No MetricKit dependency for testability.
struct HangMetricsProcessor {

    /// Only data whose reporting period ended within the last 24 hours is sent
    static let recencyWindow: TimeInterval = 24 * 60 * 60

    func dataPointsToSendPixelsFor(from reports: [HangMetricsReport],
                                   currentAppVersion: String,
                                   now: Date,
                                   lastProcessedEnd: Date?) -> [HangDataPoint] {
        var result: [HangDataPoint] = []
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

            /// One data point per non-empty bucket, carrying that bucket's count, rather than
            /// one per hang: a hang regression would otherwise multiply pixel volume exactly
            /// when the app is least able to absorb it.
            for bucket in report.buckets where bucket.count > 0 {
                result.append(HangDataPoint(minMs: Int(bucket.startMs.rounded()),
                                            maxMs: Int(bucket.endMs.rounded()),
                                            count: bucket.count))
            }
        }
        return result
    }

    /// The newest reporting-period end across all received reports, used as the dedup marker.
    func newestTimestamp(in reports: [HangMetricsReport]) -> Date? {
        reports.map(\.timeStampEnd).max()
    }
}
