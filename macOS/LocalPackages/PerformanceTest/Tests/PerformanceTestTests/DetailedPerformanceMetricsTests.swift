//
//  DetailedPerformanceMetricsTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import PerformanceTest

final class DetailedPerformanceMetricsTests: XCTestCase {

    // MARK: - Performance Score Tests

    func testPerformanceScore_withExcellentMetrics_returnsGradeA() {
        let metrics = DetailedPerformanceMetrics(
            loadComplete: 1.0,
            domComplete: 0.8,
            domContentLoaded: 0.5,
            domInteractive: 1.0,
            firstContentfulPaint: 1.0,
            largestContentfulPaint: 1.5,
            timeToFirstByte: 0.3,
            responseTime: 0.2,
            serverTime: 0.1,
            transferSize: 1000.0,
            encodedBodySize: 800.0,
            decodedBodySize: 1600.0,
            resourceCount: 10,
            totalResourcesSize: 500000.0,
            protocol: "h2"
        )

        XCTAssertEqual(metrics.performanceScore, 100)
        XCTAssertEqual(metrics.performanceGrade, "A")
    }

    func testPerformanceScore_withPoorMetrics_returnsLowScore() {
        let metrics = DetailedPerformanceMetrics(
            loadComplete: 10.0,
            domComplete: 8.0,
            domContentLoaded: 6.0,
            domInteractive: 8.0,
            firstContentfulPaint: 6.0,
            timeToFirstByte: 3.0,
            responseTime: 2.0,
            serverTime: 1.0,
            transferSize: 10000000.0,
            encodedBodySize: 9000000.0,
            decodedBodySize: 10000000.0,
            resourceCount: 100,
            totalResourcesSize: 10000000.0,
            cumulativeLayoutShift: 0.5,
            protocol: "http/1.1"
        )

        XCTAssertLessThan(metrics.performanceScore, 50)
        XCTAssertEqual(metrics.performanceGrade, "F")
    }

    // MARK: - Computed Properties Tests

    func testCompressionRatio_withValidSizes_calculatesCorrectly() {
        let metrics = DetailedPerformanceMetrics(
            loadComplete: 1.0,
            domComplete: 1.0,
            domContentLoaded: 1.0,
            domInteractive: 1.0,
            firstContentfulPaint: 1.0,
            timeToFirstByte: 1.0,
            responseTime: 1.0,
            serverTime: 1.0,
            transferSize: 1000.0,
            encodedBodySize: 500.0,
            decodedBodySize: 1000.0,
            resourceCount: 10,
            totalResourcesSize: 1000.0
        )

        XCTAssertEqual(metrics.compressionRatio!, 0.5, accuracy: 0.001)
    }

    func testCompressionRatio_withZeroSizes_returnsNil() {
        let metrics = DetailedPerformanceMetrics(
            loadComplete: 1.0,
            domComplete: 1.0,
            domContentLoaded: 1.0,
            domInteractive: 1.0,
            firstContentfulPaint: 1.0,
            timeToFirstByte: 1.0,
            responseTime: 1.0,
            serverTime: 1.0,
            transferSize: 1000.0,
            encodedBodySize: 0.0,
            decodedBodySize: 0.0,
            resourceCount: 10,
            totalResourcesSize: 1000.0
        )

        XCTAssertNil(metrics.compressionRatio)
    }

    func testAverageResourceSize_withValidData_calculatesCorrectly() {
        let metrics = DetailedPerformanceMetrics(
            loadComplete: 1.0,
            domComplete: 1.0,
            domContentLoaded: 1.0,
            domInteractive: 1.0,
            firstContentfulPaint: 1.0,
            timeToFirstByte: 1.0,
            responseTime: 1.0,
            serverTime: 1.0,
            transferSize: 1000.0,
            encodedBodySize: 1000.0,
            decodedBodySize: 1000.0,
            resourceCount: 5,
            totalResourcesSize: 2500.0
        )

        XCTAssertEqual(metrics.averageResourceSize!, 500.0)
    }

    func testUsesModernProtocol_withHTTP2_returnsTrue() {
        let metrics = DetailedPerformanceMetrics(
            loadComplete: 1.0,
            domComplete: 1.0,
            domContentLoaded: 1.0,
            domInteractive: 1.0,
            firstContentfulPaint: 1.0,
            timeToFirstByte: 1.0,
            responseTime: 1.0,
            serverTime: 1.0,
            transferSize: 1000.0,
            encodedBodySize: 1000.0,
            decodedBodySize: 1000.0,
            resourceCount: 10,
            totalResourcesSize: 1000.0,
            protocol: "h2"
        )

        XCTAssertTrue(metrics.usesModernProtocol)
    }

    func testUsesModernProtocol_withHTTP1_returnsFalse() {
        let metrics = DetailedPerformanceMetrics(
            loadComplete: 1.0,
            domComplete: 1.0,
            domContentLoaded: 1.0,
            domInteractive: 1.0,
            firstContentfulPaint: 1.0,
            timeToFirstByte: 1.0,
            responseTime: 1.0,
            serverTime: 1.0,
            transferSize: 1000.0,
            encodedBodySize: 1000.0,
            decodedBodySize: 1000.0,
            resourceCount: 10,
            totalResourcesSize: 1000.0,
            protocol: "http/1.1"
        )

        XCTAssertFalse(metrics.usesModernProtocol)
    }

    // MARK: - Value Validation Tests

    func testInitialization_withNegativeValues_clampsToZero() {
        let metrics = DetailedPerformanceMetrics(
            loadComplete: -1.0,
            domComplete: -1.0,
            domContentLoaded: -1.0,
            domInteractive: -1.0,
            firstContentfulPaint: -1.0,
            timeToFirstByte: -1.0,
            responseTime: -1.0,
            serverTime: -1.0,
            transferSize: -1000.0,
            encodedBodySize: -1000.0,
            decodedBodySize: -1000.0,
            resourceCount: -10,
            totalResourcesSize: -1000.0,
            redirectCount: -5
        )

        XCTAssertEqual(metrics.loadComplete, 0.0)
        XCTAssertEqual(metrics.domComplete, 0.0)
        XCTAssertEqual(metrics.domContentLoaded, 0.0)
        XCTAssertEqual(metrics.domInteractive, 0.0)
        XCTAssertEqual(metrics.firstContentfulPaint, 0.0)
        XCTAssertEqual(metrics.timeToFirstByte, 0.0)
        XCTAssertEqual(metrics.responseTime, 0.0)
        XCTAssertEqual(metrics.serverTime, 0.0)
        XCTAssertEqual(metrics.transferSize, 0.0)
        XCTAssertEqual(metrics.encodedBodySize, 0.0)
        XCTAssertEqual(metrics.decodedBodySize, 0.0)
        XCTAssertEqual(metrics.resourceCount, 0)
        XCTAssertEqual(metrics.totalResourcesSize, 0.0)
        XCTAssertEqual(metrics.redirectCount, 0)
    }
}
