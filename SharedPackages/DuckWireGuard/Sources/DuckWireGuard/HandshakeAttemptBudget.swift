//
//  HandshakeAttemptBudget.swift
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

/// Bounds expensive Noise work even though MAC1 can be produced without knowing a secret.
/// The peer shares this allowance across both handshake roles and retains it across key resets.
/// See [WireGuard §5.3](https://www.wireguard.com/papers/wireguard.pdf#page=8) for the load-protection rationale.
struct HandshakeAttemptBudget {
    // Local pre-DH work policy; these numbers are not protocol requirements.
    private static let capacity: Double = 8
    private static let attemptsPerSecond: Double = 50

    private var tokens = HandshakeAttemptBudget.capacity
    private var updated: TimeInterval?

    mutating func consume(at currentTime: TimeInterval) throws {
        if let updated {
            let elapsed = min(max(currentTime - updated, 0), Self.capacity / Self.attemptsPerSecond)
            tokens = min(Self.capacity, tokens + elapsed * Self.attemptsPerSecond)
            self.updated = max(updated, currentTime)
        } else {
            updated = currentTime
        }
        guard tokens >= 1 else { throw WireGuardPeer.Error.handshakeRateLimited }
        tokens -= 1
    }
}
