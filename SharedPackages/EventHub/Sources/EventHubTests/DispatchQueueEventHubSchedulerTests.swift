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
    @Test("fires the armed action once the real deadline elapses")
    func firesArmedActionOnceRealDeadlineElapses() async throws {
        let scheduler = DispatchQueueEventHubScheduler(queue: DispatchQueue(label: "eventhub.scheduler.test.fires"))
        let recorder = FireRecorder()

        scheduler.arm(atMillis: scheduler.nowMillis() + 100) { recorder.record("fired") }

        try await Task.sleep(nanoseconds: 50_000_000) // 0.05s: still before the 0.1s deadline
        #expect(recorder.recorded.isEmpty)

        try await Task.sleep(nanoseconds: 150_000_000) // total ~0.2s: past the deadline
        #expect(recorder.recorded == ["fired"])
    }

    @Test("re-arming cancels the previously armed timer; only the latest action fires")
    func rearmingCancelsPreviouslyArmedTimer() async throws {
        let scheduler = DispatchQueueEventHubScheduler(queue: DispatchQueue(label: "eventhub.scheduler.test.rearm"))
        let recorder = FireRecorder()

        // Arm at 0.1s, then immediately re-arm at 0.3s with a different action. `arm` cancels whatever
        // was previously scheduled, so "first" must never fire.
        scheduler.arm(atMillis: scheduler.nowMillis() + 100) { recorder.record("first") }
        scheduler.arm(atMillis: scheduler.nowMillis() + 300) { recorder.record("second") }

        try await Task.sleep(nanoseconds: 150_000_000) // 0.15s: past the cancelled first deadline
        #expect(recorder.recorded.isEmpty)

        try await Task.sleep(nanoseconds: 250_000_000) // total ~0.4s: past the second deadline
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
