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

    // MARK: - Standard Tab Count Bucketing

    func testBucketStandardTabCount_AtBoundaries() {
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(0), 0)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(1), 1)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(2), 2)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(4), 4)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(7), 7)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(11), 11)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(21), 21)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(51), 51)
    }

    func testBucketStandardTabCount_WithinRanges() {
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(3), 2)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(5), 4)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(6), 4)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(9), 7)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(10), 7)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(15), 11)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(30), 21)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(50), 21)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(100), 51)
        XCTAssertEqual(MemoryReportingBuckets.bucketStandardTabCount(500), 51)
    }

    // MARK: - Pinned Tab Count Bucketing

    func testBucketPinnedTabCount_AtBoundaries() {
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(0), 0)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(1), 1)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(2), 2)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(4), 4)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(7), 7)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(11), 11)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(15), 15)
    }

    func testBucketPinnedTabCount_WithinRanges() {
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(3), 2)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(5), 4)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(6), 4)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(9), 7)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(10), 7)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(12), 11)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(14), 11)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(20), 15)
        XCTAssertEqual(MemoryReportingBuckets.bucketPinnedTabCount(100), 15)
    }

    // MARK: - Used Allocation Bucketing

    func testBucketUsedAllocationMB_BelowFirstBucket() {
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(0), 0)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(32), 0)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(63.9), 0)
    }

    func testBucketUsedAllocationMB_AtBoundaries() {
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(64), 64)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(128), 128)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(256), 256)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(512), 512)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(1024), 1024)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(2048), 2048)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(4096), 4096)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(8192), 8192)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(16384), 16384)
    }

    func testBucketUsedAllocationMB_WithinRanges() {
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(100), 64)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(200), 128)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(400), 256)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(800), 512)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(1500), 1024)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(3000), 2048)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(6000), 4096)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(12000), 8192)
        XCTAssertEqual(MemoryReportingBuckets.bucketUsedAllocationMB(32000), 16384)
    }

    // MARK: - Architecture

    func testCurrentArchitecture_ReturnsValidValue() {
        let arch = MemoryReportingBuckets.currentArchitecture
        XCTAssertTrue(arch == "ARM" || arch == "Intel", "Architecture should be ARM or Intel, got \(arch)")
    }
}
