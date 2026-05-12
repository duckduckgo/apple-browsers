//
//  AddressBarPerformanceRecorderTests.swift
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

final class AddressBarPerformanceRecorderTests: XCTestCase {

    /// A controllable clock for deterministic timing in tests.
    private final class TestClock {
        var now: TimeInterval = 0
        func read() -> TimeInterval { now }
    }

    private var clock: TestClock!
    private var recorder: AddressBarPerformanceRecorder!

    override func setUp() {
        super.setUp()
        clock = TestClock()
        recorder = AddressBarPerformanceRecorder(clock: { [unowned self] in self.clock.read() })
    }

    override func tearDown() {
        recorder = nil
        clock = nil
        super.tearDown()
    }

    // MARK: - Basic semantics

    func test_takeAndClear_onFreshRecorderReturnsEmpty() {
        let snapshot = recorder.takeAndClear()
        XCTAssertEqual(snapshot.char, [])
        XCTAssertEqual(snapshot.suggest, [])
    }

    func test_onCharRendered_withNothingPending_recordsNothing() {
        clock.now = 0.5
        recorder.onCharRendered()
        XCTAssertEqual(recorder.takeAndClear().char, [])
    }

    func test_onSuggestionsRendered_withNothingPending_recordsNothing() {
        clock.now = 0.5
        recorder.onSuggestionsRendered()
        XCTAssertEqual(recorder.takeAndClear().suggest, [])
    }

    // MARK: - Char path

    func test_charPath_singleKeystrokeProducesOneSample() {
        clock.now = 0
        recorder.appendCharStartTime()
        clock.now = 0.030 // 30ms later
        recorder.onCharRendered()

        XCTAssertEqual(recorder.takeAndClear().char, [30])
    }

    func test_charPath_burstOfNKeystrokesInOneFrameProducesNSamples() {
        // Three keystrokes at 0, 5, 10 ms; one paint at 16 ms.
        clock.now = 0
        recorder.appendCharStartTime()
        clock.now = 0.005
        recorder.appendCharStartTime()
        clock.now = 0.010
        recorder.appendCharStartTime()
        clock.now = 0.016
        recorder.onCharRendered()

        XCTAssertEqual(recorder.takeAndClear().char, [16, 11, 6])
    }

    func test_charPath_drainsAndClearsBetweenBursts() {
        clock.now = 0
        recorder.appendCharStartTime()
        clock.now = 0.020
        recorder.onCharRendered()
        // Buffer cleared; next burst starts fresh.
        clock.now = 0.100
        recorder.appendCharStartTime()
        clock.now = 0.115
        recorder.onCharRendered()

        XCTAssertEqual(recorder.takeAndClear().char, [20, 15])
    }

    // MARK: - Suggest path

    func test_suggestPath_singleKeystrokeProducesOneSample() {
        clock.now = 0
        recorder.markKeystrokeForSuggest()
        clock.now = 0.080
        recorder.onSuggestionsRendered()

        XCTAssertEqual(recorder.takeAndClear().suggest, [80])
    }

    func test_suggestPath_burstCollapsesToOneSampleTiedToLastKeystroke() {
        clock.now = 0
        recorder.markKeystrokeForSuggest()
        clock.now = 0.005
        recorder.markKeystrokeForSuggest()
        clock.now = 0.010
        recorder.markKeystrokeForSuggest()
        clock.now = 0.080
        recorder.onSuggestionsRendered()

        // 80ms - 10ms = 70ms (latest keystroke wins).
        XCTAssertEqual(recorder.takeAndClear().suggest, [70])
    }

    func test_suggestPath_clearsSlotAfterRender() {
        clock.now = 0
        recorder.markKeystrokeForSuggest()
        clock.now = 0.050
        recorder.onSuggestionsRendered()
        // Second render with nothing pending → no second sample.
        clock.now = 0.100
        recorder.onSuggestionsRendered()

        XCTAssertEqual(recorder.takeAndClear().suggest, [50])
    }

    // MARK: - Char/suggest independence

    func test_charAndSuggest_areIndependent() {
        // One keystroke, one char paint, one suggest paint → both record.
        clock.now = 0
        recorder.markKeystrokeForSuggest()
        recorder.appendCharStartTime()
        clock.now = 0.020
        recorder.onCharRendered()
        clock.now = 0.080
        recorder.onSuggestionsRendered()

        let snapshot = recorder.takeAndClear()
        XCTAssertEqual(snapshot.char, [20])
        XCTAssertEqual(snapshot.suggest, [80])
    }

    // MARK: - Reset / takeAndClear

    func test_reset_clearsAllState() {
        clock.now = 0
        recorder.markKeystrokeForSuggest()
        recorder.appendCharStartTime()
        clock.now = 0.020
        recorder.onCharRendered()
        recorder.markKeystrokeForSuggest()
        recorder.appendCharStartTime()

        recorder.reset()

        // Even with later paints, nothing is recorded.
        clock.now = 1.0
        recorder.onCharRendered()
        recorder.onSuggestionsRendered()

        let snapshot = recorder.takeAndClear()
        XCTAssertEqual(snapshot.char, [])
        XCTAssertEqual(snapshot.suggest, [])
    }

    func test_takeAndClear_clearsAllState() {
        clock.now = 0
        recorder.appendCharStartTime()
        clock.now = 0.020
        recorder.onCharRendered()

        let first = recorder.takeAndClear()
        XCTAssertEqual(first.char, [20])

        // After takeAndClear, recorder is fresh.
        let second = recorder.takeAndClear()
        XCTAssertEqual(second.char, [])
        XCTAssertEqual(second.suggest, [])
    }

    func test_takeAndClear_discardsPendingEntriesNotPairedWithPaint() {
        clock.now = 0
        recorder.appendCharStartTime() // pending, never paired
        let snapshot = recorder.takeAndClear()
        XCTAssertEqual(snapshot.char, [])
        XCTAssertEqual(snapshot.suggest, [])
    }

    // MARK: - Sample cap

    func test_sampleCap_dropsCharSamplesOverFiveSeconds() {
        clock.now = 0
        recorder.appendCharStartTime()
        clock.now = 5.001 // 5001 ms
        recorder.onCharRendered()

        XCTAssertEqual(recorder.takeAndClear().char, [])
    }

    func test_sampleCap_dropsSuggestSamplesOverFiveSeconds() {
        clock.now = 0
        recorder.markKeystrokeForSuggest()
        clock.now = 6.0
        recorder.onSuggestionsRendered()

        XCTAssertEqual(recorder.takeAndClear().suggest, [])
    }

    func test_sampleCap_keepsExactlyFiveSecondSample() {
        clock.now = 0
        recorder.appendCharStartTime()
        clock.now = 5.0
        recorder.onCharRendered()

        XCTAssertEqual(recorder.takeAndClear().char, [5_000])
    }

    func test_sampleCap_appliesPerSampleInBurst() {
        // Two pending keystrokes, only one within cap by the time paint lands.
        clock.now = 0
        recorder.appendCharStartTime()    // start at 0
        clock.now = 4.999
        recorder.appendCharStartTime()    // start at 4999
        clock.now = 6.0                   // paint at 6000
        recorder.onCharRendered()

        // First: 6000-0 = 6000 → dropped.
        // Second: 6000-4999 = 1001 → kept.
        XCTAssertEqual(recorder.takeAndClear().char, [1_001])
    }

    func test_sampleCap_dropsNegativeDeltas() {
        // Defensive: a paintTime before the keystroke (clock skew) shouldn't record.
        clock.now = 1.0
        recorder.appendCharStartTime()
        clock.now = 0.5
        recorder.onCharRendered()

        XCTAssertEqual(recorder.takeAndClear().char, [])
    }
}
