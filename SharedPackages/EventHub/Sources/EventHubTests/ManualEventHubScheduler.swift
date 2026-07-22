import Foundation
@testable import EventHub

/// Test double standing in for both `EventHubClock` and `EventHubScheduling`: a single manually-driven
/// virtual clock, exactly as the Windows fixture's single Rx `TestScheduler` drove both `Now` and period
/// timers. `advance(by:)` loops so an action that reschedules another already-due action also fires
/// within the same call (see `EventHubTests.firingResetsTheCounterForTheNextPeriod`, which
/// relies on the period-end firing and the next period's timer both being live after one `advance`).
final class ManualEventHubScheduler: EventHubClock, EventHubScheduling {
    private var currentMillis: Int64
    private var pending: [String: (fireAtMillis: Int64, action: () -> Void)] = [:]

    init(startMillis: Int64) {
        self.currentMillis = startMillis
    }

    func nowMillis() -> Int64 { currentMillis }

    func schedule(key: String, after interval: TimeInterval, _ action: @escaping () -> Void) {
        pending[key] = (currentMillis + Int64(interval * 1000), action)
    }

    func cancel(key: String) {
        pending.removeValue(forKey: key)
    }

    func advance(by interval: TimeInterval) {
        currentMillis += Int64(interval * 1000)
        while let due = pending.first(where: { $0.value.fireAtMillis <= currentMillis }) {
            pending.removeValue(forKey: due.key)
            due.value.action()
        }
    }
}
