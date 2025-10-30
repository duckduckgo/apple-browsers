//
//  BucketModifierTests.swift
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

import XCTest
@testable import AttributedMetric

final class BucketModifierTests: XCTestCase {

    // MARK: - JSON Parsing Tests

    func testParseConfigurationsValidSettings() throws {
        let settings: [String: Any] = [
            "user_retention_week": [
                "buckets": [1, 2, 3],
                "version": 1
            ],
            "user_retention_month": [
                "buckets": [2, 3, 4, 5],
                "version": 1
            ]
        ]

        let modifier = DefaultBucketModifier()
        try modifier.parseConfigurations(from: settings)

        // Verify by testing bucketed values
        XCTAssertNotNil(try modifier.bucket(value: 1, pixelName: .userRetentionWeek))
        XCTAssertNotNil(try modifier.bucket(value: 2, pixelName: .userRetentionMonth))
    }

    func testParseConfigurationsEmptySettings() throws {
        let settings: [String: Any] = [:]
        let modifier = DefaultBucketModifier()
        try modifier.parseConfigurations(from: settings)

        // Should successfully parse but configurations will be empty
        // Testing bucketedValue would trigger assertionFailure in debug mode
        // The test succeeds if parseConfigurations doesn't throw
    }

    func testParseConfigurationsInvalidSettings() {
        let settings: [String: Any] = [
            "user_retention_week": "invalid_value"
        ]
        let modifier = DefaultBucketModifier()
        XCTAssertThrowsError(try modifier.parseConfigurations(from: settings)) { error in
            XCTAssertTrue(error is BucketModifierError)
            if case BucketModifierError.invalidConfiguration = error {
                // Expected error
            } else {
                XCTFail("Expected BucketModifierError.invalidConfiguration")
            }
        }
    }

    func testParseConfigurationsMissingBuckets() {
        let settings: [String: Any] = [
            "user_retention_week": [
                "version": 1
            ]
        ]
        let modifier = DefaultBucketModifier()
        XCTAssertThrowsError(try modifier.parseConfigurations(from: settings)) { error in
            XCTAssertTrue(error is BucketModifierError)
            if case BucketModifierError.invalidConfiguration = error {
                // Expected error
            } else {
                XCTFail("Expected BucketModifierError.invalidConfiguration")
            }
        }
    }

    func testParseConfigurationsMalformedStructure() {
        let settings: [String: Any] = [
            "user_retention_week": [
                "buckets": "not_an_array",
                "version": 1
            ]
        ]
        let modifier = DefaultBucketModifier()
        XCTAssertThrowsError(try modifier.parseConfigurations(from: settings)) { error in
            XCTAssertTrue(error is BucketModifierError)
            if case BucketModifierError.invalidConfiguration = error {
                // Expected error
            } else {
                XCTFail("Expected BucketModifierError.invalidConfiguration")
            }
        }
    }

    // MARK: - Bucketed Value Tests

    func testBucketedValueFirstBucket() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [5, 9], value 3 <= 5, should return "0"
        let bucket = try modifier.bucket(value: 3, pixelName: .userAverageSearchesPastWeekFirstMonth)
        XCTAssertEqual(bucket.value, 0)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueFirstBucketBoundary() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [5, 9], value 5 <= 5, should return "0"
        let bucket = try modifier.bucket(value: 5, pixelName: .userAverageSearchesPastWeekFirstMonth)
        XCTAssertEqual(bucket.value, 0)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueSecondBucket() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [5, 9], value 7 <= 9, should return "1"
        let bucket = try modifier.bucket(value: 7, pixelName: .userAverageSearchesPastWeekFirstMonth)
        XCTAssertEqual(bucket.value, 1)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueSecondBucketBoundary() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [5, 9], value 9 <= 9, should return "1"
        let bucket = try modifier.bucket(value: 9, pixelName: .userAverageSearchesPastWeekFirstMonth)
        XCTAssertEqual(bucket.value, 1)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueExceedsAllThresholds() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [5, 9], value 22 > 9, should return "2" (buckets.count)
        let bucket = try modifier.bucket(value: 22, pixelName: .userAverageSearchesPastWeekFirstMonth)
        XCTAssertEqual(bucket.value, 2)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueRetentionWeek() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [1, 2, 3], value 2 <= 2, should return "1"
        let bucket = try modifier.bucket(value: 2, pixelName: .userRetentionWeek)
        XCTAssertEqual(bucket.value, 1)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueRetentionMonth() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [2, 3, 4, 5], value 4 <= 4, should return "2"
        let bucket = try modifier.bucket(value: 4, pixelName: .userRetentionMonth)
        XCTAssertEqual(bucket.value, 2)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueActivePastWeek() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [2, 4], value 3 <= 4, should return "1"
        let bucket = try modifier.bucket(value: 3, pixelName: .userActivePastWeek)
        XCTAssertEqual(bucket.value, 1)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueAdClicks() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [2, 5], value 1 <= 2, should return "0"
        let bucket = try modifier.bucket(value: 1, pixelName: .userAverageAdClicksPastWeek)
        XCTAssertEqual(bucket.value, 0)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueDuckAI() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [5, 9], value 10 > 9, should return "2" (buckets.count)
        let bucket = try modifier.bucket(value: 10, pixelName: .userAverageDuckAiUsagePastWeek)
        XCTAssertEqual(bucket.value, 2)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueSubscribed() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [0, 1], value 0 <= 0, should return "0"
        let bucket = try modifier.bucket(value: 0, pixelName: .userSubscribed)
        XCTAssertEqual(bucket.value, 0)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueSyncedDevice() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [1], value 2 > 1, should return "1" (buckets.count)
        let bucket = try modifier.bucket(value: 2, pixelName: .userSyncedDevice)
        XCTAssertEqual(bucket.value, 1)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueZero() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [5, 9], value 0 <= 5, should return "0"
        let bucket = try modifier.bucket(value: 0, pixelName: .userAverageSearchesPastWeekFirstMonth)
        XCTAssertEqual(bucket.value, 0)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueMissingConfiguration() {
        let modifier = DefaultBucketModifier()

        // No configuration exists for this pixel, should throw an error
        XCTAssertThrowsError(try modifier.bucket(value: 5, pixelName: .userAverageSearchesPastWeekFirstMonth)) { error in
            XCTAssertTrue(error is BucketModifierError)
            if case BucketModifierError.missingConfiguration = error {
                // Expected error
            } else {
                XCTFail("Expected BucketModifierError.missingConfiguration")
            }
        }
    }

    func testBucketedValueSingleBucket() throws {
        let settings: [String: Any] = [
            "user_synced_device": [
                "buckets": [1],
                "version": 1
            ]
        ]
        let modifier = DefaultBucketModifier()
        try modifier.parseConfigurations(from: settings)

        // Single bucket [1], value 1 <= 1, should return "0"
        let bucket = try modifier.bucket(value: 1, pixelName: .userSyncedDevice)
        XCTAssertEqual(bucket.value, 0)
        XCTAssertEqual(bucket.version, 1)

        // Value exceeds threshold, should return "1" (buckets.count)
        let bucket2 = try modifier.bucket(value: 5, pixelName: .userSyncedDevice)
        XCTAssertEqual(bucket2.value, 1)
        XCTAssertEqual(bucket2.version, 1)
    }

    func testBucketedValueNegativeValue() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [5, 9], value -1 <= 5, should return "0"
        let bucket = try modifier.bucket(value: -1, pixelName: .userAverageSearchesPastWeekFirstMonth)
        XCTAssertEqual(bucket.value, 0)
        XCTAssertEqual(bucket.version, 1)
    }

    func testBucketedValueLargeValue() throws {
        let modifier = createModifierWithStandardConfig()

        // buckets: [5, 9], value 1000000 > 9, should return "2" (buckets.count)
        let bucket = try modifier.bucket(value: 1000000, pixelName: .userAverageSearchesPastWeekFirstMonth)
        XCTAssertEqual(bucket.value, 2)
        XCTAssertEqual(bucket.version, 1)
    }

    // MARK: - Bucket with Different Version Tests

    func testBucketWithDifferentVersions() throws {
        let settings: [String: Any] = [
            "user_retention_week": [
                "buckets": [1, 2, 3],
                "version": 1
            ],
            "user_retention_month": [
                "buckets": [2, 3, 4, 5],
                "version": 2
            ],
            "user_active_past_week": [
                "buckets": [2, 4],
                "version": 3
            ]
        ]
        let modifier = DefaultBucketModifier()
        try modifier.parseConfigurations(from: settings)

        let bucket1 = try modifier.bucket(value: 1, pixelName: .userRetentionWeek)
        XCTAssertEqual(bucket1.version, 1)
        XCTAssertEqual(bucket1.value, 0)

        let bucket2 = try modifier.bucket(value: 3, pixelName: .userRetentionMonth)
        XCTAssertEqual(bucket2.version, 2)
        XCTAssertEqual(bucket2.value, 1)

        let bucket3 = try modifier.bucket(value: 3, pixelName: .userActivePastWeek)
        XCTAssertEqual(bucket3.version, 3)
        XCTAssertEqual(bucket3.value, 1)
    }

    func testBucketWithLargeVersionNumber() throws {
        let settings: [String: Any] = [
            "user_retention_week": [
                "buckets": [1, 2, 3],
                "version": 999
            ]
        ]
        let modifier = DefaultBucketModifier()
        try modifier.parseConfigurations(from: settings)

        let bucket = try modifier.bucket(value: 2, pixelName: .userRetentionWeek)
        XCTAssertEqual(bucket.version, 999)
        XCTAssertEqual(bucket.value, 1)
    }

    // MARK: - Helper Methods

    private func createModifierWithStandardConfig() -> DefaultBucketModifier {
        let settings: [String: Any] = [
            "user_retention_week": [
                "buckets": [1, 2, 3],
                "version": 1
            ],
            "user_retention_month": [
                "buckets": [2, 3, 4, 5],
                "version": 1
            ],
            "user_active_past_week": [
                "buckets": [2, 4],
                "version": 1
            ],
            "user_average_searches_past_week_first_month": [
                "buckets": [5, 9],
                "version": 1
            ],
            "user_average_searches_past_week": [
                "buckets": [5, 9],
                "version": 1
            ],
            "user_average_ad_clicks_past_week": [
                "buckets": [2, 5],
                "version": 1
            ],
            "user_average_duck_ai_usage_past_week": [
                "buckets": [5, 9],
                "version": 1
            ],
            "user_subscribed": [
                "buckets": [0, 1],
                "version": 1
            ],
            "user_synced_device": [
                "buckets": [1],
                "version": 1
            ]
        ]
        let modifier = DefaultBucketModifier()
        try? modifier.parseConfigurations(from: settings)
        return modifier
    }
}
