//
//  AddressBarPerformanceCoordinatorTests.swift
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

import PixelKit
import XCTest
@testable import AddressBarPerformance

@MainActor
final class AddressBarPerformanceCoordinatorTests: XCTestCase {

    private final class TestClock {
        var now: TimeInterval = 0
        func read() -> TimeInterval { now }
    }

    /// Captures pixels fired by the coordinator. Thread-safe so background-dispatched emits can append.
    private final class PixelCapture: PixelFiring {
        private let lock = NSLock()
        private var pixels: [AddressBarPerformancePixel] = []

        func fire(_ event: PixelKitEvent,
                  frequency: PixelKit.Frequency,
                  includeAppVersionParameter: Bool,
                  withAdditionalParameters: [String: String]?,
                  withNamePrefix: String?,
                  onComplete: @escaping PixelKit.CompletionBlock) {
            guard let pixel = event as? AddressBarPerformancePixel else {
                XCTFail("Unexpected event type: \(type(of: event))")
                onComplete(false, nil)
                return
            }
            lock.lock()
            pixels.append(pixel)
            lock.unlock()
            onComplete(true, nil)
        }

        func snapshot() -> [AddressBarPerformancePixel] {
            lock.lock(); defer { lock.unlock() }
            return pixels
        }
    }

    private var clock: TestClock!
    private var capture: PixelCapture!
    private var coordinator: AddressBarPerformanceCoordinator!

    /// Small delay so async dispatch fires within the test timeout but predictably after a brief wait.
    private let testDeferredEmitDelay: TimeInterval = 0.02
    private let testHookStopDelay: TimeInterval = 0.05

    override func setUp() {
        super.setUp()
        AddressBarPerformanceCoordinator.currentActive = nil
        clock = TestClock()
        capture = PixelCapture()
        coordinator = makeCoordinator()
    }

    override func tearDown() {
        coordinator = nil
        capture = nil
        clock = nil
        AddressBarPerformanceCoordinator.currentActive = nil
        super.tearDown()
    }

    private func makeCoordinator() -> AddressBarPerformanceCoordinator {
        let testClock = clock!
        let recorder = AddressBarPerformanceRecorder(clock: { testClock.read() })
        return AddressBarPerformanceCoordinator(
            recorder: recorder,
            deferredEmitDelay: testDeferredEmitDelay,
            hookStopDelay: testHookStopDelay,
            pixelFiring: capture
        )
    }

    // MARK: - Helpers

    private func waitForPixelEmission() {
        // Sleep just past the deferred delay to allow the async work item to fire.
        let waitDeadline = Date().addingTimeInterval(testDeferredEmitDelay + 0.5)
        while capture.snapshot().isEmpty && Date() < waitDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        // Give async dispatch one more runloop spin to settle.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    // MARK: - Char path

    func test_keystrokeAndPaintAndTerminate_firesPixelWithCharHalfPopulated() {
        clock.now = 0
        coordinator.markKeystroke()
        coordinator.armCharRenderIfPending()
        clock.now = 0.030 // 30ms — lands in 16..50 band (index 1)
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()

        waitForPixelEmission()

        let pixels = capture.snapshot()
        XCTAssertEqual(pixels.count, 1)
        let pixel = pixels[0]
        XCTAssertEqual(pixel.charBasisPoints[1], 10_000)
        XCTAssertEqual(pixel.charBasisPoints.reduce(0, +), 10_000)
        XCTAssertEqual(pixel.suggestBasisPoints.reduce(0, +), 0, "Suggest half must be empty (all zeros)")
        XCTAssertEqual(pixel.stages, .character)
    }

    func test_terminateWithNoMeasurements_doesNotFirePixel() {
        coordinator.terminateInteraction()
        waitForPixelEmission()
        XCTAssertTrue(capture.snapshot().isEmpty)
    }

    /// Regression guard for the duplicate-terminator path. Cmd-Tab fires window-deactivate and
    /// app-deactivate back to back: the first terminator snapshots a non-empty buffer and
    /// schedules emission, the second sees an empty recorder. The first pixel must still fire.
    func test_duplicateTerminator_doesNotCancelFirstPixel() {
        clock.now = 0
        coordinator.markKeystroke()
        coordinator.armCharRenderIfPending()
        clock.now = 0.030
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()
        coordinator.terminateInteraction()

        waitForPixelEmission()

        XCTAssertEqual(capture.snapshot().count, 1)
    }

    func test_paintWithoutKeystroke_recordsNothing() {
        clock.now = 0.030
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()
        waitForPixelEmission()
        XCTAssertTrue(capture.snapshot().isEmpty)
    }

    // MARK: - Suggest path

    func test_keystrokeAndSuggestionsUpdateAndPaint_firesPixelWithBothHalvesPopulated() {
        clock.now = 0
        coordinator.markKeystroke()
        coordinator.armCharRenderIfPending()
        clock.now = 0.080
        coordinator.markSuggestionsUpdated()
        coordinator.handlePaint(at: 0.080)
        coordinator.terminateInteraction()

        waitForPixelEmission()

        let pixels = capture.snapshot()
        XCTAssertEqual(pixels.count, 1)
        let pixel = pixels[0]
        XCTAssertGreaterThan(pixel.charBasisPoints.reduce(0, +), 0, "Char half must be populated")
        XCTAssertGreaterThan(pixel.suggestBasisPoints.reduce(0, +), 0, "Suggest half must be populated")
        XCTAssertEqual(pixel.stages, .both)
    }

    func test_suggestionsUpdateWithoutKeystroke_recordsNothing() {
        coordinator.markSuggestionsUpdated()
        clock.now = 0.030
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()
        waitForPixelEmission()
        XCTAssertTrue(capture.snapshot().isEmpty)
    }

    /// Regression guard: a `SearchSuggestions` `$result` emission can land between the keystroke
    /// arrival and `controlTextDidChange`. The suggest anchor must be set at keystroke time
    /// (not at commit time) so the resulting suggest sample doesn't get lost.
    func test_suggestUpdateBeforeCommit_stillRecordsSuggestSample() {
        clock.now = 0
        coordinator.markKeystroke()
        clock.now = 0.080
        coordinator.markSuggestionsUpdated()
        // No armCharRenderIfPending — simulating the suggest update arriving before commit.
        coordinator.handlePaint(at: 0.080)
        coordinator.terminateInteraction()

        waitForPixelEmission()

        let pixels = capture.snapshot()
        XCTAssertEqual(pixels.count, 1)
        let pixel = pixels[0]
        // 80ms latency — band 2 (50..100).
        XCTAssertEqual(pixel.suggestBasisPoints[2], 10_000)
        XCTAssertEqual(pixel.charBasisPoints.reduce(0, +), 0, "Char half must be empty (no commit fired)")
        XCTAssertEqual(pixel.stages, .suggestion)
    }

    // MARK: - Commit-gating

    func test_keystrokeWithoutTextDidChange_doesNotProduceCharSample() {
        clock.now = 0
        coordinator.markKeystroke()
        // Simulate a suppressed keystroke: no armCharRenderIfPending follows.
        clock.now = 0.030
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()
        waitForPixelEmission()
        XCTAssertTrue(capture.snapshot().isEmpty)
    }

    func test_textDidChangeWithoutPriorKeystroke_isNoOp() {
        // Programmatic text change with no preceding markKeystroke.
        coordinator.armCharRenderIfPending()
        clock.now = 0.030
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()
        waitForPixelEmission()
        XCTAssertTrue(capture.snapshot().isEmpty)
    }

    func test_suppressedKeystrokeFollowedByLegitimate_recordsOnlyTheLegitimate() {
        clock.now = 0
        coordinator.markKeystroke() // k1, will be suppressed
        // No armCharRenderIfPending for k1 — buffer didn't change.
        clock.now = 0.020
        coordinator.markKeystroke() // k2, legitimate
        coordinator.armCharRenderIfPending()
        clock.now = 0.030 // 10ms after k2
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()

        waitForPixelEmission()

        let pixels = capture.snapshot()
        XCTAssertEqual(pixels.count, 1)
        // Single sample at 10ms — band 0 (0..16). All weight on band 0, nothing elsewhere.
        XCTAssertEqual(pixels[0].charBasisPoints[0], 10_000)
    }

    // MARK: - Reset and cancellation

    func test_resetForNewInteraction_clearsPendingState() {
        clock.now = 0
        coordinator.markKeystroke()
        coordinator.armCharRenderIfPending()
        coordinator.resetForNewInteraction()
        clock.now = 0.030
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()

        waitForPixelEmission()
        XCTAssertTrue(capture.snapshot().isEmpty)
    }

    func test_resetForNewInteraction_clearsPendingCharIntent() {
        clock.now = 0
        coordinator.markKeystroke()
        coordinator.resetForNewInteraction()
        // Confirming after reset must not retroactively arm — the stashed t₀ is gone.
        coordinator.armCharRenderIfPending()
        clock.now = 0.030
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()

        waitForPixelEmission()
        XCTAssertTrue(capture.snapshot().isEmpty)
    }

    func test_terminateInteraction_clearsPendingCharIntent() {
        clock.now = 0
        coordinator.markKeystroke()
        coordinator.terminateInteraction()
        // Confirming after terminate must not retroactively arm a sample that didn't exist.
        coordinator.armCharRenderIfPending()
        clock.now = 0.030
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()

        waitForPixelEmission()
        XCTAssertTrue(capture.snapshot().isEmpty)
    }

    /// Regression guard for the Cmd-Tab cycle: the user types, switches apps, returns within
    /// the deferred-emit window, and types again. The first interaction's pixel must still
    /// fire — we never drop a captured measurement in flight.
    func test_resetForNewInteraction_doesNotCancelPendingEmit() {
        clock.now = 0
        coordinator.markKeystroke()
        coordinator.armCharRenderIfPending()
        clock.now = 0.030
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()

        // Reset before the deferred emit fires.
        coordinator.resetForNewInteraction()

        waitForPixelEmission()
        XCTAssertEqual(capture.snapshot().count, 1)
    }

    // MARK: - Burst behaviour

    func test_burstOfKeystrokesInOneFrame_recordsNSamplesForCharStage() {
        clock.now = 0
        coordinator.markKeystroke()
        coordinator.armCharRenderIfPending()
        clock.now = 0.005
        coordinator.markKeystroke()
        coordinator.armCharRenderIfPending()
        clock.now = 0.010
        coordinator.markKeystroke()
        coordinator.armCharRenderIfPending()
        clock.now = 0.016
        coordinator.handlePaint(at: 0.016)
        coordinator.terminateInteraction()

        waitForPixelEmission()

        let pixels = capture.snapshot()
        XCTAssertEqual(pixels.count, 1)
        // Three measurements: 16 → band 0, 11 → band 0, 6 → band 0. All in band 0.
        XCTAssertEqual(pixels[0].charBasisPoints[0], 10_000)
    }

    // MARK: - Hook lifecycle

    func test_terminate_schedulesDeferredHookStop_andStopsAfterDelay() async {
        coordinator.resetForNewInteraction()
        XCTAssertTrue(AddressBarPerformanceCoordinator.currentActive === coordinator)

        coordinator.terminateInteraction()
        let task = coordinator.pendingHookStopTask
        XCTAssertNotNil(task, "Terminator must schedule a deferred hook stop")
        XCTAssertFalse(task?.isCancelled ?? true)

        await task?.value
        XCTAssertNil(coordinator.pendingHookStopTask, "Deferred stop must clear the task")
        XCTAssertNil(AddressBarPerformanceCoordinator.currentActive, "Deferred stop must clear currentActive")
    }

    func test_resetForNewInteraction_cancelsDeferredHookStop() {
        coordinator.resetForNewInteraction()
        coordinator.terminateInteraction()
        let scheduled = coordinator.pendingHookStopTask
        XCTAssertNotNil(scheduled)

        coordinator.resetForNewInteraction()
        XCTAssertNil(coordinator.pendingHookStopTask, "Reset must clear the pending stop")
        XCTAssertTrue(scheduled?.isCancelled ?? false)
        XCTAssertTrue(AddressBarPerformanceCoordinator.currentActive === coordinator)
    }

    func test_markKeystroke_cancelsDeferredHookStop() {
        coordinator.resetForNewInteraction()
        coordinator.terminateInteraction()
        let scheduled = coordinator.pendingHookStopTask
        XCTAssertNotNil(scheduled)

        coordinator.markKeystroke()
        XCTAssertNil(coordinator.pendingHookStopTask, "markKeystroke must clear the pending stop (Cmd-Tab-back safety)")
        XCTAssertTrue(scheduled?.isCancelled ?? false)
    }

    func test_backToBackTerminators_onlyLatestStopIsLive() {
        coordinator.resetForNewInteraction()
        coordinator.terminateInteraction()
        let firstTask = coordinator.pendingHookStopTask

        coordinator.terminateInteraction()
        let secondTask = coordinator.pendingHookStopTask

        XCTAssertNotNil(firstTask)
        XCTAssertNotNil(secondTask)
        XCTAssertNotEqual(firstTask, secondTask, "Second terminator must replace the task, not stack")
        XCTAssertTrue(firstTask?.isCancelled ?? false, "The earlier stop must be cancelled")
        XCTAssertFalse(secondTask?.isCancelled ?? true)
    }

    func test_secondCoordinator_displacesFirstImmediately() {
        let coordinatorA = coordinator! // already constructed in setUp
        let coordinatorB = makeCoordinator()

        coordinatorA.resetForNewInteraction()
        XCTAssertTrue(AddressBarPerformanceCoordinator.currentActive === coordinatorA)
        coordinatorA.terminateInteraction()
        let aTask = coordinatorA.pendingHookStopTask
        XCTAssertNotNil(aTask)

        coordinatorB.resetForNewInteraction()
        XCTAssertTrue(AddressBarPerformanceCoordinator.currentActive === coordinatorB, "B activation displaces A")
        XCTAssertNil(coordinatorA.pendingHookStopTask, "Displacement clears A's pending stop")
        XCTAssertTrue(aTask?.isCancelled ?? false)
    }

    func test_detach_cancelsPendingStop_andClearsCurrentActive() {
        coordinator.resetForNewInteraction()
        coordinator.terminateInteraction()
        let scheduled = coordinator.pendingHookStopTask
        XCTAssertNotNil(scheduled)

        coordinator.detach()
        XCTAssertNil(coordinator.pendingHookStopTask)
        XCTAssertTrue(scheduled?.isCancelled ?? false)
        XCTAssertNil(AddressBarPerformanceCoordinator.currentActive)
    }
}
