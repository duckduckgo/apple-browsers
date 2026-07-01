//
//  AddressBarPerformanceRecorder.swift
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

import Foundation
import QuartzCore

/// Records per-keystroke and per-suggestion-render latency measurements for one address bar
/// across a single interaction (focus → terminator).
///
/// The recorder is a passive collector — callers mark keystrokes as they arrive, mark paint
/// events as they happen, and snapshot the buffers when the interaction ends. All access is
/// expected on the main thread; threads are not synchronised internally.
///
/// Char and suggest stages aggregate keystrokes differently:
/// - Char keeps every pending keystroke; a paint that lands N keystrokes produces N samples,
///   each with its own latency.
/// - Suggest keeps only the latest keystroke; the suggestions pipeline coalesces a typing
///   burst into a single render, attributable to the last keystroke before that render.
final class AddressBarPerformanceRecorder {

    typealias Clock = () -> TimeInterval

    /// Default cap on individual measurements (5s). Samples beyond this are dropped to suppress
    /// sleep / hibernate artifacts.
    static let defaultSampleCapMs: Int = 5_000

    private let clock: Clock
    private let sampleCapMs: Int

    private var pendingCharStartTimes: [TimeInterval] = []
    private var latestKeystrokeForSuggest: TimeInterval?
    private var charSamplesMs: [Int] = []
    private var suggestSamplesMs: [Int] = []

    init(clock: @escaping Clock = CACurrentMediaTime, sampleCapMs: Int = AddressBarPerformanceRecorder.defaultSampleCapMs) {
        self.clock = clock
        self.sampleCapMs = sampleCapMs
    }

    /// Sets the suggest stage's anchor to `time`. Called at keystroke arrival so a
    /// `SearchSuggestions` update that lands before the buffer-commit notification still finds an
    /// anchor. Returns the timestamp that was stamped, so the coordinator can reuse it when
    /// pushing the same keystroke into the char pending list at commit time.
    @discardableResult
    func markKeystrokeForSuggest(at time: TimeInterval? = nil) -> TimeInterval {
        let t = time ?? clock()
        latestKeystrokeForSuggest = t
        return t
    }

    /// Appends `time` to the char pending list. Called at `controlTextDidChange` once the buffer
    /// has actually committed, with the original keystroke's arrival time.
    func appendCharStartTime(at time: TimeInterval? = nil) {
        let t = time ?? clock()
        pendingCharStartTimes.append(t)
    }

    /// Drains the char pending list, recording one char sample per pending keystroke against
    /// `paintTime`. No-op when nothing is pending.
    func onCharRendered(at paintTime: TimeInterval? = nil) {
        guard !pendingCharStartTimes.isEmpty else { return }
        let t = paintTime ?? clock()
        for startTime in pendingCharStartTimes {
            recordSample(start: startTime, end: t, into: &charSamplesMs)
        }
        pendingCharStartTimes.removeAll()
    }

    /// Records one suggest sample against `paintTime` using the latest queued keystroke,
    /// then clears the slot. No-op when nothing is queued.
    func onSuggestionsRendered(at paintTime: TimeInterval? = nil) {
        guard let startTime = latestKeystrokeForSuggest else { return }
        let t = paintTime ?? clock()
        recordSample(start: startTime, end: t, into: &suggestSamplesMs)
        latestKeystrokeForSuggest = nil
    }

    /// Discards all pending state and recorded samples.
    func reset() {
        pendingCharStartTimes.removeAll()
        latestKeystrokeForSuggest = nil
        charSamplesMs.removeAll()
        suggestSamplesMs.removeAll()
    }

    /// Returns the samples recorded so far and clears all state. Pending entries that
    /// haven't been paired with a paint are discarded.
    func takeAndClear() -> (char: [Int], suggest: [Int]) {
        let snapshot = (char: charSamplesMs, suggest: suggestSamplesMs)
        reset()
        return snapshot
    }

    private func recordSample(start: TimeInterval, end: TimeInterval, into buffer: inout [Int]) {
        let deltaMs = Int(((end - start) * 1000).rounded())
        guard deltaMs >= 0, deltaMs <= sampleCapMs else { return }
        buffer.append(deltaMs)
    }
}
