import Foundation
import Persistence

public final class ConnectionFailureLoopDetector {

    public enum Keys {
        static let consecutiveFailureCount = "vpn.loop-detector.consecutive-failure-count"
    }

    private static let threshold = 3

    private let store: ThrowingKeyValueStoring
    private let isFeatureEnabled: Bool

    public var connectionLoopDetected: Bool {
        guard isFeatureEnabled else { return false }
        let count = (try? store.object(forKey: Keys.consecutiveFailureCount) as? Int) ?? 0
        return count > Self.threshold
    }

    public init(store: ThrowingKeyValueStoring, isFeatureEnabled: Bool) {
        self.store = store
        self.isFeatureEnabled = isFeatureEnabled
    }

    @discardableResult
    public func connectionFailed(isOnDemand: Bool) -> Bool {
        guard isFeatureEnabled else { return false }

        if !isOnDemand {
            resetState()
            return false
        }

        let currentCount = (try? store.object(forKey: Keys.consecutiveFailureCount) as? Int) ?? 0
        let count = currentCount + 1
        try? store.set(count, forKey: Keys.consecutiveFailureCount)

        return count == Self.threshold
    }

    public func connectionSucceeded() {
        guard isFeatureEnabled else { return }
        resetState()
    }

    public func reset() {
        guard isFeatureEnabled else { return }
        resetState()
    }

    private func resetState() {
        try? store.set(0, forKey: Keys.consecutiveFailureCount)
    }
}
