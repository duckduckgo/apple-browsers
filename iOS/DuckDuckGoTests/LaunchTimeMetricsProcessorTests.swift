//
//  LaunchTimeMetricsProcessorTests.swift
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

import XCTest
@testable import DuckDuckGo

final class LaunchTimeMetricsProcessorTests: XCTestCase {

    private let processor = LaunchTimeMetricsProcessor()
    private let version = "7.100.0"
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func report(version: String = "7.100.0",
                        multiVersion: Bool = false,
                        endOffset: TimeInterval = -60,
                        histograms: [LaunchType: [LaunchHistogramBucket]]) -> LaunchMetricsReport {
        LaunchMetricsReport(appVersion: version,
                            includesMultipleAppVersions: multiVersion,
                            timeStampEnd: now.addingTimeInterval(endOffset),
                            histograms: histograms)
    }

    func testExpandsBucketCountIntoOneDataPointEach() {
        let r = report(histograms: [.coldStart: [LaunchHistogramBucket(startMs: 100, endMs: 200, count: 3)]])
        let points = processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil)
        XCTAssertEqual(points, Array(repeating: LaunchTimeDataPoint(launchType: .coldStart, minMs: 100, maxMs: 200), count: 3))
    }

    func testEmitsAcrossAllLaunchTypes() {
        let r = report(histograms: [
            .coldStart: [LaunchHistogramBucket(startMs: 10, endMs: 20, count: 1)],
            .resume: [LaunchHistogramBucket(startMs: 30, endMs: 40, count: 1)],
            .optimizedFirstDraw: [LaunchHistogramBucket(startMs: 50, endMs: 60, count: 1)]
        ])
        let points = processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil)
        XCTAssertEqual(Set(points.map(\.launchType)), [.coldStart, .resume, .optimizedFirstDraw])
        XCTAssertEqual(points.count, 3)
    }

    func testSkipsMultiVersionReport() {
        let r = report(multiVersion: true, histograms: [.coldStart: [LaunchHistogramBucket(startMs: 1, endMs: 2, count: 5)]])
        XCTAssertTrue(processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil).isEmpty)
    }

    func testSkipsWrongVersionReport() {
        let r = report(version: "7.99.0", histograms: [.coldStart: [LaunchHistogramBucket(startMs: 1, endMs: 2, count: 5)]])
        XCTAssertTrue(processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil).isEmpty)
    }

    func testSkipsReportOlderThan24Hours() {
        let r = report(endOffset: -(24 * 60 * 60) - 1, histograms: [.coldStart: [LaunchHistogramBucket(startMs: 1, endMs: 2, count: 5)]])
        XCTAssertTrue(processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil).isEmpty)
    }

    func testKeepsReportExactlyAt24HourBoundary() {
        let r = report(endOffset: -(24 * 60 * 60), histograms: [.coldStart: [LaunchHistogramBucket(startMs: 1, endMs: 2, count: 1)]])
        XCTAssertEqual(processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil).count, 1)
    }

    func testSkipsAlreadyProcessedReport() {
        let r = report(endOffset: -60, histograms: [.coldStart: [LaunchHistogramBucket(startMs: 1, endMs: 2, count: 1)]])
        let points = processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: r.timeStampEnd)
        XCTAssertTrue(points.isEmpty)
    }

    func testIgnoresEmptyAndZeroCountBuckets() {
        let r = report(histograms: [
            .coldStart: [LaunchHistogramBucket(startMs: 1, endMs: 2, count: 0)],
            .resume: []
        ])
        XCTAssertTrue(processor.dataPointsToSendPixelsFor(from: [r], currentAppVersion: version, now: now, lastProcessedEnd: nil).isEmpty)
    }

    func testNewestTimestampReturnsMax() {
        let a = report(endOffset: -600, histograms: [:])
        let b = report(endOffset: -60, histograms: [:])
        XCTAssertEqual(processor.newestTimestamp(in: [a, b]), b.timeStampEnd)
        XCTAssertNil(processor.newestTimestamp(in: []))
    }
}
