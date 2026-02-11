//
//  MemoryReportingBucketsTests.swift
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

final class MemoryReportingBucketsTests: XCTestCase {

    // MARK: - Memory Bucketing

    func testBucketMemoryMB_BelowFirstBucket() {
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(0), 0)
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(100), 0)
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(511.9), 0)
    }

    func testBucketMemoryMB_AtBoundaries() {
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(512), 512)
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(1024), 1024)
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(2048), 2048)
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(4096), 4096)
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(8192), 8192)
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(16384), 16384)
    }

    func testBucketMemoryMB_WithinRanges() {
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(700), 512)
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(1500), 1024)
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(3000), 2048)
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(6000), 4096)
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(12000), 8192)
        XCTAssertEqual(MemoryReportingBuckets.bucketMemoryMB(32000), 16384)
    }

    // MARK: - Window Count Bucketing

    func testBucketWindowCount_AtBoundaries() {
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(0), 0)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(1), 1)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(2), 2)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(4), 4)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(7), 7)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(11), 11)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(21), 21)
    }

    func testBucketWindowCount_WithinRanges() {
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(3), 2)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(5), 4)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(6), 4)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(9), 7)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(10), 7)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(15), 11)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(20), 11)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(50), 21)
        XCTAssertEqual(MemoryReportingBuckets.bucketWindowCount(100), 21)
    }

    // MARK: - Tab Count Bucketing

    func testBucketTabCount_AtBoundaries() {
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(0), 0)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(1), 1)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(2), 2)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(4), 4)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(7), 7)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(11), 11)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(21), 21)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(51), 51)
    }

    func testBucketTabCount_WithinRanges() {
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(3), 2)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(5), 4)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(6), 4)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(9), 7)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(10), 7)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(15), 11)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(30), 21)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(50), 21)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(100), 51)
        XCTAssertEqual(MemoryReportingBuckets.bucketTabCount(500), 51)
    }

    // MARK: - Architecture

    func testCurrentArchitecture_ReturnsValidValue() {
        let arch = MemoryReportingBuckets.currentArchitecture
        XCTAssertTrue(arch == "ARM" || arch == "Intel", "Architecture should be ARM or Intel, got \(arch)")
    }
}
