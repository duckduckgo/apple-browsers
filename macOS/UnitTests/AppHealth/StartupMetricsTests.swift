//
//  StartupMetricsTests.swift
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

final class StartupMetricsTests: XCTestCase {

    // MARK: - Update

    func testUpdateRecordsInterval() throws {
        var metrics = StartupMetrics()
        metrics.update(step: .appDelegateInit, startTime: 1.0, endTime: 2.0)

        let intervalForInit = try XCTUnwrap(metrics.intervals[.appDelegateInit])
        XCTAssertEqual(intervalForInit.start, 1.0)
        XCTAssertEqual(intervalForInit.end, 2.0)
    }

    func testUpdateReturnsSelf() {
        var metrics = StartupMetrics()
        let returned = metrics.update(step: .appDelegateInit, startTime: 1.0, endTime: 2.0)

        XCTAssertNotNil(returned.intervals[.appDelegateInit])
    }

    func testUpdateOverwritesPreviousValue() {
        var metrics = StartupMetrics()
        metrics.update(step: .appDelegateInit, startTime: 1.0, endTime: 2.0)
        metrics.update(step: .appDelegateInit, startTime: 3.0, endTime: 5.0)

        XCTAssertEqual(metrics.intervals[.appDelegateInit]?.start, 3.0)
        XCTAssertEqual(metrics.intervals[.appDelegateInit]?.end, 5.0)
    }

    // MARK: - IsComplete

    func testIsCompleteReturnsFalseWhenEmpty() {
        let metrics = StartupMetrics()

        XCTAssertFalse(metrics.isComplete)
    }

    func testIsCompleteReturnsFalseWhenPartial() {
        var metrics = StartupMetrics()
        metrics.update(step: .appDelegateInit, startTime: 0, endTime: 1)
        metrics.update(step: .appWillFinishLaunching, startTime: 1, endTime: 2)

        XCTAssertFalse(metrics.isComplete)
    }

    func testIsCompleteReturnsTrueWhenAllStepsWereRecorded() {
        let metrics = buildCompleteMetrics()

        XCTAssertTrue(metrics.isComplete)
    }

    // MARK: - Duration

    func testDurationReturnsNilForUnrecordedStep() {
        let metrics = StartupMetrics()

        XCTAssertNil(metrics.duration(step: .appDelegateInit))
    }

    func testDurationReturnsCorrectValue() {
        var metrics = StartupMetrics()
        metrics.update(step: .appDelegateInit, startTime: 1.0, endTime: 3.5)

        XCTAssertEqual(metrics.duration(step: .appDelegateInit), 2.5)
    }

    // MARK: - Time Elapsed Between

    func testTimeElapsedBetweenReturnsNilWhenEarliestStepIsMissing() {
        var metrics = StartupMetrics()
        metrics.update(step: .appWillFinishLaunching, startTime: 2.0, endTime: 3.0)

        XCTAssertNil(metrics.timeElapsedBetween(endOf: .appDelegateInit, startOf: .appWillFinishLaunching))
    }

    func testTimeElapsedBetweenReturnsNilWhenLatestStepsMissing() {
        var metrics = StartupMetrics()
        metrics.update(step: .appDelegateInit, startTime: 1.0, endTime: 2.0)

        XCTAssertNil(metrics.timeElapsedBetween(endOf: .appDelegateInit, startOf: .appWillFinishLaunching))
    }

    func testTimeElapsedBetweenReturnsTheCorrectDelta() {
        var metrics = StartupMetrics()
        metrics.update(step: .appDelegateInit, startTime: 1.0, endTime: 2.0)
        metrics.update(step: .appWillFinishLaunching, startTime: 3.0, endTime: 4.0)

        XCTAssertEqual(metrics.timeElapsedBetween(endOf: .appDelegateInit, startOf: .appWillFinishLaunching), 1.0)
    }

    // MARK: - Interval

    func testIntervalDuration() {
        let interval = StartupMetrics.Interval(start: 1.0, end: 3.5)

        XCTAssertEqual(interval.duration, 2.5)
    }

    func testIntervalTimeElapsedSince() {
        let earlier = StartupMetrics.Interval(start: 1.0, end: 2.0)
        let later = StartupMetrics.Interval(start: 3.0, end: 4.0)

        XCTAssertEqual(later.timeElapsedSince(endOf: earlier), 1.0)
    }
}

// MARK: - Helpers

private extension StartupMetricsTests {

    func buildCompleteMetrics() -> StartupMetrics {
        var metrics = StartupMetrics()
        var time: TimeInterval = 0

        for step in StartupStep.allCases {
            let start = time
            time += 0.1
            metrics.update(step: step, startTime: start, endTime: time)
            time += 0.05
        }

        return metrics
    }
}
