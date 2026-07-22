import Foundation

/// The manager's notion of "now", expressed as UTC epoch milliseconds (mirrors the Windows
/// `ISchedulers.DefaultScheduler.Now`, which the manager reads for both period-window arithmetic and
/// `attributionPeriod`).
public protocol EventHubClock {
    func nowMillis() -> Int64
}

/// A single consolidated timer — never one per pixel (see the Tech Design's rejection of a per-pixel
/// `[String: Timer]` map). `arm(atMillis:_:)` replaces whatever was previously armed; passing `nil`
/// cancels without arming a new one. `EventHub` recomputes "the earlier of the earliest period end
/// across all telemetries, or the next write-behind flush deadline" and re-arms on every state change.
public protocol EventHubScheduler: EventHubClock {
    func arm(atMillis dateMillis: Int64?, _ action: @escaping () -> Void)
}

/// Production scheduler: one `DispatchSourceTimer` on a dedicated serial queue.
public final class DispatchQueueEventHubScheduler: EventHubScheduler {
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?

    public init(queue: DispatchQueue) {
        self.queue = queue
    }

    public func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    public func arm(atMillis dateMillis: Int64?, _ action: @escaping () -> Void) {
        timer?.cancel()
        timer = nil
        guard let dateMillis else { return }
        let delay = max(0, Double(dateMillis - nowMillis()) / 1000)
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now() + delay)
        newTimer.setEventHandler(handler: action)
        newTimer.resume()
        timer = newTimer
    }
}
