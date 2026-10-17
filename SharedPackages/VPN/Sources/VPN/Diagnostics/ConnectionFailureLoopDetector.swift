//
//  ConnectionFailureLoopDetector.swift
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
import Persistence

public final class ConnectionFailureLoopDetector {

    public enum Keys {
        static let consecutiveFailureCount = "vpn.loop-detector.consecutive-failure-count"
    }

    private static let threshold = 3

    private let store: ThrowingKeyValueStoring

    public private(set) var shouldSuppressCurrentAttemptTelemetry = false

    public var connectionLoopDetected: Bool {
        let count = (try? store.object(forKey: Keys.consecutiveFailureCount) as? Int) ?? 0
        return count > Self.threshold
    }

    public init(store: ThrowingKeyValueStoring) {
        self.store = store
    }

    /// Latches suppression for the whole attempt so nested telemetry, such as AuthV2 refresh,
    /// uses the failure count from before the outer VPN failure is recorded.
    public func connectionStarted(isOnDemand: Bool) {
        let count = (try? store.object(forKey: Keys.consecutiveFailureCount) as? Int) ?? 0
        shouldSuppressCurrentAttemptTelemetry = isOnDemand && count >= Self.threshold
    }

    public func connectionFinished() {
        shouldSuppressCurrentAttemptTelemetry = false
    }

    @discardableResult
    public func connectionFailed(isOnDemand: Bool) -> Bool {
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
        resetState()
    }

    public func reset() {
        resetState()
    }

    private func resetState() {
        connectionFinished()
        try? store.set(0, forKey: Keys.consecutiveFailureCount)
    }
}
