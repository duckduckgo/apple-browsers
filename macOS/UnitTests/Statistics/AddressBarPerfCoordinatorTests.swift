//
//  AddressBarPerfCoordinatorTests.swift
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

final class AddressBarPerfCoordinatorTests: XCTestCase {

    private final class TestClock {
        var now: TimeInterval = 0
        func read() -> TimeInterval { now }
    }

    /// Captures pixels fired by the coordinator. Thread-safe so background-dispatched emits can append.
    private final class PixelCapture {
        private let lock = NSLock()
        private var pixels: [AddressBarPerfPixel] = []

        var firer: (AddressBarPerfPixel) -> Void {
            { [weak self] pixel in
                self?.lock.lock()
                self?.pixels.append(pixel)
                self?.lock.unlock()
            }
        }

        func snapshot() -> [AddressBarPerfPixel] {
            lock.lock(); defer { lock.unlock() }
            return pixels
        }
    }

    private var clock: TestClock!
    private var capture: PixelCapture!
    private var coordinator: AddressBarPerfCoordinator!

    /// Small delay so async dispatch fires within the test timeout but predictably after a brief wait.
    private let testDeferredEmitDelay: TimeInterval = 0.02

    override func setUp() {
        super.setUp()
        clock = TestClock()
        capture = PixelCapture()
        let recorder = AddressBarPerfRecorder(clock: { [unowned self] in self.clock.read() })
        coordinator = AddressBarPerfCoordinator(
            recorder: recorder,
            deferredEmitDelay: testDeferredEmitDelay,
            pixelFirer: capture.firer
        )
    }

    override func tearDown() {
        coordinator = nil
        capture = nil
        clock = nil
        super.tearDown()
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

    private func basisPoints(_ pixel: AddressBarPerfPixel) -> [Int] {
        switch pixel {
        case .charRender(let bp), .suggestSettle(let bp):
            return bp
        }
    }

    // MARK: - Char path

    func test_keystrokeAndPaintAndTerminate_firesCharPixelWithCorrectBucket() {
        clock.now = 0
        coordinator.markKeystroke()
        clock.now = 0.030 // 30ms — lands in 16..50 band (index 1)
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()

        waitForPixelEmission()

        let pixels = capture.snapshot()
        XCTAssertEqual(pixels.count, 1)
        guard let first = pixels.first, case .charRender = first else {
            return XCTFail("Expected a charRender pixel")
        }
        let bp = basisPoints(first)
        XCTAssertEqual(bp[1], 10_000)
        XCTAssertEqual(bp.reduce(0, +), 10_000)
    }

    func test_terminateWithNoMeasurements_doesNotFirePixel() {
        coordinator.terminateInteraction()
        waitForPixelEmission()
        XCTAssertEqual(capture.snapshot(), [])
    }

    func test_paintWithoutKeystroke_recordsNothing() {
        clock.now = 0.030
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()
        waitForPixelEmission()
        XCTAssertEqual(capture.snapshot(), [])
    }

    // MARK: - Suggest path

    func test_keystrokeAndSuggestionsUpdateAndPaint_firesSuggestPixel() {
        clock.now = 0
        coordinator.markKeystroke()
        clock.now = 0.080
        coordinator.markSuggestionsUpdated()
        coordinator.handlePaint(at: 0.080)
        coordinator.terminateInteraction()

        waitForPixelEmission()

        let pixels = capture.snapshot()
        // Order is implementation-defined (char fires first, then suggest); we only require both.
        XCTAssertTrue(pixels.contains { if case .suggestSettle = $0 { return true } else { return false } },
                      "Expected a suggestSettle pixel")
    }

    func test_suggestionsUpdateWithoutKeystroke_recordsNothing() {
        coordinator.markSuggestionsUpdated()
        clock.now = 0.030
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()
        waitForPixelEmission()
        XCTAssertEqual(capture.snapshot(), [])
    }

    // MARK: - Reset and cancellation

    func test_resetForNewInteraction_clearsPendingState() {
        clock.now = 0
        coordinator.markKeystroke()
        coordinator.resetForNewInteraction()
        clock.now = 0.030
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()

        waitForPixelEmission()
        XCTAssertEqual(capture.snapshot(), [])
    }

    func test_resetForNewInteraction_cancelsPendingEmit() {
        clock.now = 0
        coordinator.markKeystroke()
        clock.now = 0.030
        coordinator.handlePaint(at: 0.030)
        coordinator.terminateInteraction()

        // Reset before the deferred emit fires.
        coordinator.resetForNewInteraction()

        waitForPixelEmission()
        XCTAssertEqual(capture.snapshot(), [])
    }

    // MARK: - Burst behaviour

    func test_burstOfKeystrokesInOneFrame_recordsNSamplesForCharStage() {
        clock.now = 0
        coordinator.markKeystroke()
        clock.now = 0.005
        coordinator.markKeystroke()
        clock.now = 0.010
        coordinator.markKeystroke()
        clock.now = 0.016
        coordinator.handlePaint(at: 0.016)
        coordinator.terminateInteraction()

        waitForPixelEmission()

        let pixels = capture.snapshot()
        XCTAssertEqual(pixels.count, 1)
        guard let first = pixels.first, case .charRender = first else {
            return XCTFail("Expected a charRender pixel")
        }
        let bp = basisPoints(first)
        // Three measurements: 16 → band 0, 11 → band 0, 6 → band 0. All in band 0.
        XCTAssertEqual(bp[0], 10_000)
    }
}
