//
//  AddressBarPerformanceBucketingTests.swift
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
@testable import AddressBarPerformance

final class AddressBarPerformanceBucketingTests: XCTestCase {

    // MARK: - bandIndex

    func test_bandIndex_lowerBoundaries() {
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 0), 0)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 1), 0)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 15), 0)
    }

    func test_bandIndex_upperBoundariesAreInclusive() {
        // A sample exactly at a boundary lands in the lower (smaller-index) band.
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 16), 0)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 50), 1)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 100), 2)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 150), 3)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 200), 4)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 300), 5)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 500), 6)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 1000), 7)
    }

    func test_bandIndex_oneAboveBoundaryAdvancesBand() {
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 17), 1)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 51), 2)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 101), 3)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 151), 4)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 201), 5)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 301), 6)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 501), 7)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 1001), 8)
    }

    func test_bandIndex_extremes() {
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 5_000), 8)
        XCTAssertEqual(AddressBarPerformanceBucketing.bandIndex(for: 1_000_000), 8)
    }

    // MARK: - basisPoints

    func test_basisPoints_emptyInputIsAllZeros() {
        XCTAssertEqual(AddressBarPerformanceBucketing.basisPoints(for: []), Array(repeating: 0, count: 9))
    }

    func test_basisPoints_singleSampleIsTenThousandInItsBand() {
        let result = AddressBarPerformanceBucketing.basisPoints(for: [10])
        XCTAssertEqual(result[0], 10_000)
        XCTAssertEqual(result.dropFirst().reduce(0, +), 0)
        XCTAssertEqual(result.reduce(0, +), 10_000)
    }

    func test_basisPoints_twoSamplesEvenlySplit() {
        let result = AddressBarPerformanceBucketing.basisPoints(for: [10, 30])
        XCTAssertEqual(result[0], 5_000)
        XCTAssertEqual(result[1], 5_000)
        XCTAssertEqual(result.reduce(0, +), 10_000)
    }

    func test_basisPoints_threeSamplesAcrossDistinctBandsSumsToNineThousandNineHundredNinetyNine() {
        // floor(1 * 10000 / 3) = 3333 each, sum = 9999 (one basis point lost to floor rounding).
        let result = AddressBarPerformanceBucketing.basisPoints(for: [10, 30, 75])
        XCTAssertEqual(result[0], 3_333)
        XCTAssertEqual(result[1], 3_333)
        XCTAssertEqual(result[2], 3_333)
        XCTAssertEqual(result.reduce(0, +), 9_999)
    }

    func test_basisPoints_allSamplesInSameBandIsTenThousandRegardlessOfN() {
        for n in [1, 2, 7, 100, 1_000] {
            let result = AddressBarPerformanceBucketing.basisPoints(for: Array(repeating: 10, count: n))
            XCTAssertEqual(result[0], 10_000, "n=\(n)")
            XCTAssertEqual(result.reduce(0, +), 10_000, "n=\(n)")
        }
    }

    func test_basisPoints_allBandsPopulatedSumIsAtLeastNineThousandNinetyTwo() {
        // One sample in each band → sum loses up to (BandCount - 1) = 8 basis points to flooring.
        let oneInEachBand: [Int] = [10, 30, 75, 120, 175, 250, 400, 750, 2_000]
        let result = AddressBarPerformanceBucketing.basisPoints(for: oneInEachBand)
        XCTAssertGreaterThanOrEqual(result.reduce(0, +), 9_992)
        XCTAssertLessThanOrEqual(result.reduce(0, +), 10_000)
        // Each band has exactly one sample.
        for value in result {
            XCTAssertGreaterThan(value, 0)
        }
    }

    func test_basisPoints_boundaryValuesLandInLowerBand() {
        // 100ms (the SLO threshold) must land in bp_50_100, not bp_100_150.
        let result = AddressBarPerformanceBucketing.basisPoints(for: [100])
        XCTAssertEqual(result[2], 10_000)
        XCTAssertEqual(result[3], 0)
    }

    func test_basisPoints_perPixelSumIsBoundedAboveByTenThousand() {
        // Random sanity check across many distributions: sum is always in [9992, 10000].
        for _ in 0..<200 {
            let n = Int.random(in: 1...50)
            let samples = (0..<n).map { _ in Int.random(in: 0...2_000) }
            let sum = AddressBarPerformanceBucketing.basisPoints(for: samples).reduce(0, +)
            XCTAssertGreaterThanOrEqual(sum, 10_000 - (AddressBarPerformanceBucketing.bandCount - 1))
            XCTAssertLessThanOrEqual(sum, 10_000)
        }
    }
}
