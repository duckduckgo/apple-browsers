//
//  StartupProfilerTests.swift
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

final class StartupProfilerTests: XCTestCase {

    // MARK: - StartMeasuring

    func testStartMeasuringRecordsStep() {
        let profiler = StartupProfiler()

        let token = profiler.startMeasuring(.appInit)
        token.stop()

        let metrics = profiler.exportMetrics()
        XCTAssertNotNil(metrics.intervals[.appInit])
    }

    func testStartMeasuringRecordsDuration() throws {
        let profiler = StartupProfiler()

        let token = profiler.startMeasuring(.appInit)
        token.stop()

        let metrics = profiler.exportMetrics()
        let duration = try XCTUnwrap(metrics.duration(step: .appInit))
        XCTAssert(duration >= 0)
    }

    // MARK: - MeasureOnce

    func testMeasureOnceRecordsStepFromReferenceStart() {
        let profiler = StartupProfiler()

        let token = profiler.startMeasuring(.appInit)
        token.stop()

        profiler.measureOnce(.appWillFinishLaunching, startStep: .appInit)

        let metrics = profiler.exportMetrics()
        XCTAssertNotNil(metrics.intervals[.appWillFinishLaunching])

        let referenceStart = metrics.intervals[.appInit]?.start
        let measuredStart = metrics.intervals[.appWillFinishLaunching]?.start
        XCTAssertEqual(referenceStart, measuredStart)
    }

    func testMeasureOnceDoesNotOverwriteExistingStep() {
        let profiler = StartupProfiler()

        let token = profiler.startMeasuring(.appInit)
        token.stop()

        let originalEnd = profiler.exportMetrics().intervals[.appInit]?.end

        profiler.measureOnce(.appInit, startStep: .appInit)

        let afterEnd = profiler.exportMetrics().intervals[.appInit]?.end
        XCTAssertEqual(originalEnd, afterEnd)
    }

    func testMeasureOnceDoesNothingWhenReferenceStepMissing() {
        let profiler = StartupProfiler()

        profiler.measureOnce(.appWillFinishLaunching, startStep: .appInit)

        let metrics = profiler.exportMetrics()
        XCTAssertNil(metrics.intervals[.appWillFinishLaunching])
    }

    // MARK: - MeasureSequence

    func testMeasureSequenceRecordsInitialStep() {
        let profiler = StartupProfiler()

        let sequence = profiler.measureSequence(initialStep: .appInit)
        sequence.stop()

        let metrics = profiler.exportMetrics()
        XCTAssertNotNil(metrics.intervals[.appInit])
    }

    func testMeasureSequenceAdvanceRecordsBothSteps() {
        let profiler = StartupProfiler()

        let sequence = profiler.measureSequence(initialStep: .appInit)
        sequence.advance(to: .appWillFinishLaunching)
        sequence.stop()

        let metrics = profiler.exportMetrics()
        XCTAssertNotNil(metrics.intervals[.appInit])
        XCTAssertNotNil(metrics.intervals[.appWillFinishLaunching])
    }

    func testMeasureSequenceMultipleAdvances() {
        let profiler = StartupProfiler()

        let sequence = profiler.measureSequence(initialStep: .appInit)
        sequence.advance(to: .appWillFinishLaunching)
        sequence.advance(to: .appDidFinishLaunchingBeforeRestoration)
        sequence.stop()

        let metrics = profiler.exportMetrics()
        XCTAssertNotNil(metrics.intervals[.appInit])
        XCTAssertNotNil(metrics.intervals[.appWillFinishLaunching])
        XCTAssertNotNil(metrics.intervals[.appDidFinishLaunchingBeforeRestoration])
    }

    // MARK: - ExportMetrics

    func testExportMetricsReturnsEmptyByDefault() {
        let profiler = StartupProfiler()

        let metrics = profiler.exportMetrics()
        XCTAssertFalse(metrics.isComplete)
        XCTAssertTrue(metrics.intervals.isEmpty)
    }

    // MARK: - Delegate

    func testDelegateCalledWhenAllStepsRecorded() {
        let profiler = StartupProfiler()
        let delegate = MockStartupProfilerDelegate()
        profiler.delegate = delegate

        for step in StartupStep.allCases {
            let token = profiler.startMeasuring(step)
            token.stop()
        }

        XCTAssertTrue(delegate.didComplete)
        XCTAssertNotNil(delegate.receivedMetrics)
        XCTAssertTrue(delegate.receivedMetrics!.isComplete)
    }

    func testDelegateNotCalledWhenStepsIncomplete() {
        let profiler = StartupProfiler()
        let delegate = MockStartupProfilerDelegate()
        profiler.delegate = delegate

        let token = profiler.startMeasuring(.appInit)
        token.stop()

        XCTAssertFalse(delegate.didComplete)
    }

    // MARK: - StartupProfilerToken

    func testTokenStopOnlyCallsClosureOnce() {
        var callCount = 0

        let token = StartupProfilerToken {
            callCount += 1
        }

        token.stop()
        token.stop()

        XCTAssertEqual(callCount, 1)
    }

    // MARK: - Sequence

    func testSequenceStopRecordsStep() {
        var completedSteps = [StartupStep]()

        let sequence = StartupProfilerSequence(
            initialStep: .appInit,
            timeProvider: { 0 },
            onStepCompleted: { step, _, _ in completedSteps.append(step) }
        )

        sequence.stop()

        XCTAssertEqual(completedSteps, [.appInit])
    }

    func testSequenceAdvanceRecordsCurrentAndStartsNext() {
        var completedSteps = [StartupStep]()

        let sequence = StartupProfilerSequence(
            initialStep: .appInit,
            timeProvider: { 0 },
            onStepCompleted: { step, _, _ in completedSteps.append(step) }
        )

        sequence.advance(to: .appWillFinishLaunching)
        sequence.stop()

        XCTAssertEqual(completedSteps, [.appInit, .appWillFinishLaunching])
    }

    func testSequenceUsesTimeProvider() {
        var time: TimeInterval = 1.0
        var recordedIntervals = [(start: TimeInterval, end: TimeInterval)]()

        let sequence = StartupProfilerSequence(
            initialStep: .appInit,
            timeProvider: { time },
            onStepCompleted: { _, start, end in recordedIntervals.append((start, end)) }
        )

        time = 2.0
        sequence.advance(to: .appWillFinishLaunching)

        time = 3.0
        sequence.stop()

        XCTAssertEqual(recordedIntervals.count, 2)
        XCTAssertEqual(recordedIntervals[0].start, 1.0)
        XCTAssertEqual(recordedIntervals[0].end, 2.0)
        XCTAssertEqual(recordedIntervals[1].start, 2.0)
        XCTAssertEqual(recordedIntervals[1].end, 3.0)
    }
}

// MARK: - StartupProfilerDelegate

private final class MockStartupProfilerDelegate: StartupProfilerDelegate {
    var didComplete = false
    var receivedMetrics: StartupMetrics?

    func startupProfiler(_ profiler: StartupProfiler, didCompleteWithMetrics metrics: StartupMetrics) {
        didComplete = true
        receivedMetrics = metrics
    }
}
