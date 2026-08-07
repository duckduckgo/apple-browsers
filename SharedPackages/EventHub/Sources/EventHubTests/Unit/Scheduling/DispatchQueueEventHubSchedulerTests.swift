//
//  DispatchQueueEventHubSchedulerTests.swift
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
import Testing
@testable import EventHub

/// Thread-safe recorder for scheduler fire callbacks. Unlike every other scheduler test in this
/// package (all built on `ManualEventHubScheduler`'s virtual clock, which invokes the armed callback
/// inline on the calling thread), these tests exercise the real `DispatchSourceTimer` inside
/// `DispatchQueueEventHubScheduler`: the callback genuinely fires asynchronously, on the queue passed
/// to `init(queue:)`, after a real (short) delay.
private final class FireRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    func record(_ name: String) {
        lock.lock()
        names.append(name)
        lock.unlock()
    }

    var recorded: [String] {
        lock.lock()
        defer { lock.unlock() }
        return names
    }
}

@Suite("DispatchQueueEventHubScheduler")
struct DispatchQueueEventHubSchedulerTests {
    // These wait on the callback rather than on the wall clock. Sleeping for "long enough" and then
    // asserting is a race in both directions: an overshooting sleep makes a not-yet-fired check fail,
    // and a late timer makes an already-fired check fail. Neither would be a real defect — the delay is
    // Dispatch's to honour, not ours.
    @Test("fires the armed action once the deadline elapses")
    func firesArmedActionOnceDeadlineElapses() async {
        let scheduler = DispatchQueueEventHubScheduler(queue: DispatchQueue(label: "eventhub.scheduler.test.fires"))

        // Returning at all is the assertion: an armed timer that never fires hangs here instead.
        await withCheckedContinuation { continuation in
            scheduler.arm(atMillis: scheduler.nowMillis() + 50) { continuation.resume() }
        }
    }

    @Test("re-arming cancels the previously armed timer; only the latest action fires")
    func rearmingCancelsPreviouslyArmedTimer() async {
        let scheduler = DispatchQueueEventHubScheduler(queue: DispatchQueue(label: "eventhub.scheduler.test.rearm"))
        let recorder = FireRecorder()

        // "first" is due well before "second", so waiting for "second" to fire is enough: had the
        // re-arm failed to cancel it, "first" would already be recorded by the time we get here.
        scheduler.arm(atMillis: scheduler.nowMillis() + 50) { recorder.record("first") }
        await withCheckedContinuation { continuation in
            scheduler.arm(atMillis: scheduler.nowMillis() + 150) {
                recorder.record("second")
                continuation.resume()
            }
        }

        #expect(recorder.recorded == ["second"])
    }

    @Test("arming nil cancels without firing")
    func armingNilCancelsWithoutFiring() async throws {
        let scheduler = DispatchQueueEventHubScheduler(queue: DispatchQueue(label: "eventhub.scheduler.test.nil"))
        let recorder = FireRecorder()

        scheduler.arm(atMillis: scheduler.nowMillis() + 100) { recorder.record("fired") }
        scheduler.arm(atMillis: nil) {}

        try await Task.sleep(nanoseconds: 250_000_000) // well past the original (cancelled) deadline
        #expect(recorder.recorded.isEmpty)
    }
}
