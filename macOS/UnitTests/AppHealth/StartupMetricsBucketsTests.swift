//
//  StartupMetricsBucketsTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class StartupMetricsBucketsTests: XCTestCase {

    // MARK: - Processor Count Bucketing

    func testBucketProcessorCountAtBoundaries() {
        XCTAssertEqual(StartupMetricsBuckets.bucketProcessorCount(1), "1")
        XCTAssertEqual(StartupMetricsBuckets.bucketProcessorCount(2), "2")
        XCTAssertEqual(StartupMetricsBuckets.bucketProcessorCount(4), "4")
        XCTAssertEqual(StartupMetricsBuckets.bucketProcessorCount(8), "8")
        XCTAssertEqual(StartupMetricsBuckets.bucketProcessorCount(12), "12")
    }

    func testBucketProcessorCountWithinRanges() {
        XCTAssertEqual(StartupMetricsBuckets.bucketProcessorCount(0), "1")
        XCTAssertEqual(StartupMetricsBuckets.bucketProcessorCount(3), "2")
        XCTAssertEqual(StartupMetricsBuckets.bucketProcessorCount(6), "4")
        XCTAssertEqual(StartupMetricsBuckets.bucketProcessorCount(10), "8")
        XCTAssertEqual(StartupMetricsBuckets.bucketProcessorCount(16), "12")
        XCTAssertEqual(StartupMetricsBuckets.bucketProcessorCount(64), "12")
    }

    // MARK: - Window Count Bucketing

    func testBucketWindowCountAtBoundaries() {
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(0), "0")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(1), "1")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(2), "2")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(4), "4")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(7), "7")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(11), "11")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(21), "21")
    }

    func testBucketWindowCountWithinRanges() {
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(3), "2")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(5), "4")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(6), "4")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(9), "7")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(10), "7")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(15), "11")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(20), "11")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(50), "21")
        XCTAssertEqual(StartupMetricsBuckets.bucketWindowCount(100), "21")
    }

    // MARK: - Tab Count Bucketing

    func testBucketTabCountAtBoundaries() {
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(0), "0")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(1), "1")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(2), "2")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(4), "4")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(7), "7")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(11), "11")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(21), "21")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(51), "51")
    }

    func testBucketTabCountWithinRanges() {
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(3), "2")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(5), "4")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(6), "4")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(9), "7")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(10), "7")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(15), "11")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(30), "21")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(50), "21")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(100), "51")
        XCTAssertEqual(StartupMetricsBuckets.bucketTabCount(500), "51")
    }

    // MARK: - Milliseconds Bucketing

    func testBucketMillisecondsAtBoundaries() {
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(0), "0")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(0.1), "100")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(0.2), "200")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(0.3), "300")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(0.4), "400")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(0.5), "500")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(1.0), "1000")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(2.0), "2000")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(3.0), "3000")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(5.0), "5000")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(10.0), "10000")
    }

    func testBucketMillisecondsWithinRanges() {
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(0.05), "0")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(0.15), "100")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(0.25), "200")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(0.35), "300")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(0.45), "400")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(0.75), "500")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(1.5), "1000")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(2.5), "2000")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(4.0), "3000")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(7.0), "5000")
        XCTAssertEqual(StartupMetricsBuckets.bucketMilliseconds(15.0), "10000")
    }
}
