import Foundation
@testable import EventHub

/// Test double for `EventHubScheduler`: a manually-advanced virtual clock driving a single armed
/// callback. `advance(by:)` loops so an action that re-arms another already-due callback also fires
/// within the same call (see `EventHubTests.firingResetsTheCounterForTheNextPeriod`, which relies on
/// the period-end firing and the next period's timer both being live after one `advance`).
final class ManualEventHubScheduler: EventHubScheduler {
    private var currentMillis: Int64
    private var armedAtMillis: Int64?
    private var armedAction: (() -> Void)?

    init(startMillis: Int64) {
        self.currentMillis = startMillis
    }

    func nowMillis() -> Int64 { currentMillis }

    func arm(atMillis dateMillis: Int64?, _ action: @escaping () -> Void) {
        armedAtMillis = dateMillis
        armedAction = dateMillis == nil ? nil : action
    }

    func advance(by interval: TimeInterval) {
        currentMillis += Int64(interval * 1000)
        while let dueAt = armedAtMillis, dueAt <= currentMillis, let action = armedAction {
            armedAtMillis = nil
            armedAction = nil
            action()
        }
    }
}
