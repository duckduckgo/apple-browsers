import Foundation

/// The manager's notion of "now", expressed as UTC epoch milliseconds (mirrors the Windows
/// `ISchedulers.DefaultScheduler.Now`, which the manager reads for both period-window arithmetic and
/// `attributionPeriod`).
public protocol EventHubClock {
    func nowMillis() -> Int64
}

/// One-shot, cancellable, keyed scheduling for period-end timers and the write-behind persistence
/// flush. `key` identifies what was scheduled (typically a pixel name, or a fixed key for the flush
/// timer) so a later call under the same key replaces — rather than stacks — the pending action,
/// mirroring the Windows manager's `Dictionary<string, IDisposable> timers`.
public protocol EventHubScheduling {
    func schedule(key: String, after interval: TimeInterval, _ action: @escaping () -> Void)
    func cancel(key: String)
}
