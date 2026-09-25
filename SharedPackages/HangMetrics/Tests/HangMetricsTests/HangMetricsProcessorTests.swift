//
//  HangMetricsProcessorTests.swift
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
@testable import HangMetrics

final class HangMetricsProcessorTests: XCTestCase {

    private let processor = HangMetricsProcessor()
    private let version = "7.100.0"
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func report(version: String = "7.100.0",
                        multiVersion: Bool = false,
                        endOffset: TimeInterval = -60,
                        buckets: [HangHistogramBucket]) -> HangMetricsReport {
        HangMetricsReport(appVersion: version,
                          includesMultipleAppVersions: multiVersion,
                          timeStampEnd: now.addingTimeInterval(endOffset),
                          buckets: buckets)
    }

    func testEmitsOneDataPointPerBucketCarryingItsCount() {
        let r = report(buckets: [HangHistogramBucket(startMs: 100, endMs: 200, count: 3)])
        let points = processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil)
        XCTAssertEqual(points, [HangDataPoint(minMs: 100, maxMs: 200, count: 3)])
    }

    func testEmitsEveryNonEmptyBucketInTheHistogram() {
        let r = report(buckets: [
            HangHistogramBucket(startMs: 0, endMs: 100, count: 12),
            HangHistogramBucket(startMs: 100, endMs: 500, count: 4),
            HangHistogramBucket(startMs: 500, endMs: 2000, count: 1)
        ])
        let points = processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil)
        XCTAssertEqual(points, [
            HangDataPoint(minMs: 0, maxMs: 100, count: 12),
            HangDataPoint(minMs: 100, maxMs: 500, count: 4),
            HangDataPoint(minMs: 500, maxMs: 2000, count: 1)
        ])
    }

    func testRoundsFractionalBucketEdges() {
        let r = report(buckets: [HangHistogramBucket(startMs: 123.4, endMs: 456.6, count: 1)])
        let points = processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil)
        XCTAssertEqual(points, [HangDataPoint(minMs: 123, maxMs: 457, count: 1)])
    }

    func testSkipsMultiVersionReport() {
        let r = report(multiVersion: true, buckets: [HangHistogramBucket(startMs: 1, endMs: 2, count: 5)])
        XCTAssertTrue(processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil).isEmpty)
    }

    func testSkipsWrongVersionReport() {
        let r = report(version: "7.99.0", buckets: [HangHistogramBucket(startMs: 1, endMs: 2, count: 5)])
        XCTAssertTrue(processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil).isEmpty)
    }

    func testSkipsReportOlderThan24Hours() {
        let r = report(endOffset: -(24 * 60 * 60) - 1, buckets: [HangHistogramBucket(startMs: 1, endMs: 2, count: 5)])
        XCTAssertTrue(processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil).isEmpty)
    }

    func testKeepsReportExactlyAt24HourBoundary() {
        let r = report(endOffset: -(24 * 60 * 60), buckets: [HangHistogramBucket(startMs: 1, endMs: 2, count: 1)])
        XCTAssertEqual(processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil).count, 1)
    }

    func testSkipsAlreadyProcessedReport() {
        let r = report(endOffset: -60, buckets: [HangHistogramBucket(startMs: 1, endMs: 2, count: 1)])
        let points = processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: r.timeStampEnd)
        XCTAssertTrue(points.isEmpty)
    }

    func testIgnoresZeroCountBuckets() {
        let r = report(buckets: [
            HangHistogramBucket(startMs: 1, endMs: 2, count: 0),
            HangHistogramBucket(startMs: 2, endMs: 3, count: 7)
        ])
        let points = processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil)
        XCTAssertEqual(points, [HangDataPoint(minMs: 2, maxMs: 3, count: 7)])
    }

    func testEmitsNothingForReportWithNoBuckets() {
        let r = report(buckets: [])
        XCTAssertTrue(processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil).isEmpty)
    }

    func testNewestTimestampReturnsMax() {
        let a = report(endOffset: -600, buckets: [])
        let b = report(endOffset: -60, buckets: [])
        XCTAssertEqual(processor.newestTimestamp(in: [a, b]), b.timeStampEnd)
        XCTAssertNil(processor.newestTimestamp(in: []))
    }
}
