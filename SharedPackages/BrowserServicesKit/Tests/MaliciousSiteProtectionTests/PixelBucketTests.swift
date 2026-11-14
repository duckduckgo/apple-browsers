//
//  PixelBucketTests.swift
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
import Testing
@testable import MaliciousSiteProtection

@Suite("Malicious Site Protection - Aggregation Buckets")
struct PixelBucketTests {

    // MARK: - Labels

    @Suite("Labels")
    struct Labels {

        @Test("Duration labels", arguments: [
            (Event.DurationBucketAggregation.upTo100ms, "100ms"),
            (.upTo250ms, "250ms"),
            (.upTo500ms, "500ms"),
            (.upTo1s, "1s"),
            (.upTo2s, "2s"),
            (.upTo3s, "3s"),
            (.upTo4s, "4s"),
            (.upTo5s, "5s"),
            (.upTo6s, "6s"),
            (.upTo7s, "7s"),
            (.upTo8s, "8s"),
            (.upTo9s, "9s"),
            (.upTo10s, "10s"),
            (.upTo15s, "15s"),
            (.upTo20s, "20s"),
            (.upTo25s, "25s"),
            (.upTo30s, "30s"),
            (.more, "more")
        ])
        func durationLabel(bucket: Event.DurationBucketAggregation, label: String) {
            #expect(bucket.rawValue == label)
        }

        @Test("Dataset size labels", arguments: [
            (Event.DatasetSizeBucketAggregation.upTo500kb, "500kb"),
            (.upTo1mb, "1mb"),
            (.upTo2mb, "2mb"),
            (.upTo3mb, "3mb"),
            (.upTo4mb, "4mb"),
            (.upTo5mb, "5mb"),
            (.upTo6mb, "6mb"),
            (.upTo8mb, "8mb"),
            (.upTo10mb, "10mb"),
            (.upTo15mb, "15mb"),
            (.upTo20mb, "20mb"),
            (.upTo25mb, "25mb"),
            (.upTo30mb, "30mb"),
            (.upTo35mb, "35mb"),
            (.upTo40mb, "40mb"),
            (.upTo50mb, "50mb"),
            (.upTo60mb, "60mb"),
            (.upTo75mb, "75mb"),
            (.upTo100mb, "100mb"),
            (.more, "more")
        ])
        func datasetSizeLabel(bucket: Event.DatasetSizeBucketAggregation, label: String) {
            #expect(bucket.rawValue == label)
        }

    }

    // MARK: - Durations

    @Suite("Durations")
    struct Durations {

        /// For every bucket, a duration on its upper bound and one just above it, which goes in the next bucket.
        private static let durations: [(seconds: TimeInterval, bucket: Event.DurationBucketAggregation)] = [
            (0, .upTo100ms),
            (0.1, .upTo100ms),
            (0.1.nextUp, .upTo250ms),
            (0.25, .upTo250ms),
            (0.25.nextUp, .upTo500ms),
            (0.5, .upTo500ms),
            (0.5.nextUp, .upTo1s),
            (1, .upTo1s),
            (1.0.nextUp, .upTo2s),
            (2, .upTo2s),
            (2.0.nextUp, .upTo3s),
            (3, .upTo3s),
            (3.0.nextUp, .upTo4s),
            (4, .upTo4s),
            (4.0.nextUp, .upTo5s),
            (5, .upTo5s),
            (5.0.nextUp, .upTo6s),
            (6, .upTo6s),
            (6.0.nextUp, .upTo7s),
            (7, .upTo7s),
            (7.0.nextUp, .upTo8s),
            (8, .upTo8s),
            (8.0.nextUp, .upTo9s),
            (9, .upTo9s),
            (9.0.nextUp, .upTo10s),
            (10, .upTo10s),
            (10.0.nextUp, .upTo15s),
            (15, .upTo15s),
            (15.0.nextUp, .upTo20s),
            (20, .upTo20s),
            (20.0.nextUp, .upTo25s),
            (25, .upTo25s),
            (25.0.nextUp, .upTo30s),
            (30, .upTo30s),
            (30.0.nextUp, .more)
        ]

        @Test("A duration goes in the bucket of the smallest upper bound it doesn't exceed", arguments: durations)
        func durationBucket(seconds: TimeInterval, bucket: Event.DurationBucketAggregation) {
            #expect(Event.DurationBucketAggregation(seconds: seconds) == bucket)
        }

        @Test("Every duration bucket is tested")
        func everyDurationBucketIsTested() {
            #expect(Set(Self.durations.map(\.bucket)) == Set(Event.DurationBucketAggregation.allCases))
        }

    }

    // MARK: - Dataset Sizes

    @Suite("Dataset sizes")
    struct DatasetSizes {

        /// For every bucket, a size in bytes on its upper bound and one byte more, which goes in the next bucket.
        /// Sizes are in decimal megabytes: 1 MB = 1,000,000 bytes.
        private static let datasetSizes: [(bytes: Int, bucket: Event.DatasetSizeBucketAggregation)] = [
            (0, .upTo500kb),
            (500_000, .upTo500kb),
            (500_000 + 1, .upTo1mb),
            (1_000_000, .upTo1mb),
            (1_000_000 + 1, .upTo2mb),
            (2_000_000, .upTo2mb),
            (2_000_000 + 1, .upTo3mb),
            (3_000_000, .upTo3mb),
            (3_000_000 + 1, .upTo4mb),
            (4_000_000, .upTo4mb),
            (4_000_000 + 1, .upTo5mb),
            (5_000_000, .upTo5mb),
            (5_000_000 + 1, .upTo6mb),
            (6_000_000, .upTo6mb),
            (6_000_000 + 1, .upTo8mb),
            (8_000_000, .upTo8mb),
            (8_000_000 + 1, .upTo10mb),
            (10_000_000, .upTo10mb),
            (10_000_000 + 1, .upTo15mb),
            (15_000_000, .upTo15mb),
            (15_000_000 + 1, .upTo20mb),
            (20_000_000, .upTo20mb),
            (20_000_000 + 1, .upTo25mb),
            (25_000_000, .upTo25mb),
            (25_000_000 + 1, .upTo30mb),
            (30_000_000, .upTo30mb),
            (30_000_000 + 1, .upTo35mb),
            (35_000_000, .upTo35mb),
            (35_000_000 + 1, .upTo40mb),
            (40_000_000, .upTo40mb),
            (40_000_000 + 1, .upTo50mb),
            (50_000_000, .upTo50mb),
            (50_000_000 + 1, .upTo60mb),
            (60_000_000, .upTo60mb),
            (60_000_000 + 1, .upTo75mb),
            (75_000_000, .upTo75mb),
            (75_000_000 + 1, .upTo100mb),
            (100_000_000, .upTo100mb),
            (100_000_000 + 1, .more)
        ]

        @Test("A dataset size goes in the bucket of the smallest upper bound it doesn't exceed", arguments: datasetSizes)
        func datasetSizeBucket(bytes: Int, bucket: Event.DatasetSizeBucketAggregation) {
            #expect(Event.DatasetSizeBucketAggregation(bytes: bytes) == bucket)
        }

        @Test("Every dataset size bucket is tested")
        func everyDatasetSizeBucketIsTested() {
            #expect(Set(Self.datasetSizes.map(\.bucket)) == Set(Event.DatasetSizeBucketAggregation.allCases))
        }

    }

}
