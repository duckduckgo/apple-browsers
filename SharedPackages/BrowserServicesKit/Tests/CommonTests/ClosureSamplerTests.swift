//
//  ClosureSamplerTests.swift
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
@testable import Common

final class ClosureSamplerTests: XCTestCase {

    func testWhenPercentageIsZeroThenClosureNeverExecutes() {
        let sampler = ClosureSampler(percentage: 0)
        var executionCount = 0

        for _ in 0..<100 {
            sampler.sample {
                executionCount += 1
            }
        }

        XCTAssertEqual(executionCount, 0)
    }

    func testWhenPercentageIsHundredThenClosureAlwaysExecutes() {
        let sampler = ClosureSampler(percentage: 100)
        var executionCount = 0

        for _ in 0..<100 {
            sampler.sample {
                executionCount += 1
            }
        }

        XCTAssertEqual(executionCount, 100)
    }

    func testWhenPercentageIsFiftyThenClosureExecutesApproximatelyHalfTheTime() {
        let sampler = ClosureSampler(percentage: 50)
        var executionCount = 0
        let iterations = 1000

        for _ in 0..<iterations where sampler.sample({}) {
            executionCount += 1
        }

        // Allow for some variance (±10%)
        let expectedMin = Int(Double(iterations) * 0.4)
        let expectedMax = Int(Double(iterations) * 0.6)
        XCTAssertGreaterThanOrEqual(executionCount, expectedMin)
        XCTAssertLessThanOrEqual(executionCount, expectedMax)
    }

    func testWhenPercentageIsTenThenClosureExecutesApproximatelyTenPercentOfTheTime() {
        let sampler = ClosureSampler(percentage: 10)
        var executionCount = 0
        let iterations = 1000

        for _ in 0..<iterations where sampler.sample({}) {
            executionCount += 1
        }

        // Allow for some variance (±5%)
        let expectedMin = Int(Double(iterations) * 0.05)
        let expectedMax = Int(Double(iterations) * 0.15)
        XCTAssertGreaterThanOrEqual(executionCount, expectedMin)
        XCTAssertLessThanOrEqual(executionCount, expectedMax)
    }

    func testWhenPercentageIsBelowOneThenClampsToOne() {
        let sampler = ClosureSampler(percentage: -5)
        XCTAssertEqual(sampler.percentage, 1)
    }

    func testWhenPercentageIsAboveHundredThenClampsToHundred() {
        let sampler = ClosureSampler(percentage: 150)
        XCTAssertEqual(sampler.percentage, 100)
    }

    func testSampleWithReturnValueReturnsNilWhenNotSampled() {
        let sampler = ClosureSampler(percentage: 0)

        let result = sampler.sample { "test" }

        XCTAssertNil(result)
    }

    func testSampleWithReturnValueReturnsValueWhenSampled() {
        let sampler = ClosureSampler(percentage: 100)

        let result = sampler.sample { "test" }

        XCTAssertEqual(result, "test")
    }

    func testSampleWithVoidClosureReturnsFalseWhenNotSampled() {
        let sampler = ClosureSampler(percentage: 0)

        let result = sampler.sample { }

        XCTAssertFalse(result)
    }

    func testSampleWithVoidClosureReturnsTrueWhenSampled() {
        let sampler = ClosureSampler(percentage: 100)

        let result = sampler.sample { }

        XCTAssertTrue(result)
    }

    func testMultipleSamplersWithDifferentPercentagesWorkIndependently() {
        let sampler10 = ClosureSampler(percentage: 10)
        let sampler50 = ClosureSampler(percentage: 50)
        let sampler90 = ClosureSampler(percentage: 90)

        var count10 = 0
        var count50 = 0
        var count90 = 0
        let iterations = 1000

        for _ in 0..<iterations {
            if sampler10.sample({}) { count10 += 1 }
            if sampler50.sample({}) { count50 += 1 }
            if sampler90.sample({}) { count90 += 1 }
        }

        // Verify each sampler behaves independently
        XCTAssertLessThan(count10, count50)
        XCTAssertLessThan(count50, count90)
    }

    func testOnDiscardedClosureIsCalledWhenSamplingFails() {
        let sampler = ClosureSampler(percentage: 0)
        var discardedCount = 0

        for _ in 0..<10 {
            sampler.sample({
                XCTFail("Main closure should not execute when percentage is 0")
            }, onDiscarded: {
                discardedCount += 1
            })
        }

        XCTAssertEqual(discardedCount, 10)
    }

    func testOnDiscardedClosureIsNotCalledWhenSamplingSucceeds() {
        let sampler = ClosureSampler(percentage: 100)
        var discardedCount = 0
        var executedCount = 0

        for _ in 0..<10 {
            sampler.sample({
                executedCount += 1
            }, onDiscarded: {
                discardedCount += 1
            })
        }

        XCTAssertEqual(executedCount, 10)
        XCTAssertEqual(discardedCount, 0)
    }

    func testOnDiscardedClosureWithReturnValueIsCalledWhenSamplingFails() {
        let sampler = ClosureSampler(percentage: 0)
        var discardedCount = 0

        for _ in 0..<10 {
            let result = sampler.sample({
                return "test"
            }, onDiscarded: {
                discardedCount += 1
            })

            XCTAssertNil(result)
        }

        XCTAssertEqual(discardedCount, 10)
    }

    func testOnDiscardedClosureWithReturnValueIsNotCalledWhenSamplingSucceeds() {
        let sampler = ClosureSampler(percentage: 100)
        var discardedCount = 0
        var executedCount = 0

        for _ in 0..<10 {
            let result = sampler.sample({
                executedCount += 1
                return "test"
            }, onDiscarded: {
                discardedCount += 1
            })

            XCTAssertEqual(result, "test")
        }

        XCTAssertEqual(executedCount, 10)
        XCTAssertEqual(discardedCount, 0)
    }

    func testOnDiscardedClosureIsOptional() {
        let sampler = ClosureSampler(percentage: 0)

        // Should not crash when onDiscarded is nil
        let result = sampler.sample({
            return "test"
        })

        XCTAssertNil(result)
    }
}
