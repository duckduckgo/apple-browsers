//
//  WatchdogDetectionState.swift
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

internal enum WatchdogRecoveryOrigin: String {
    case hanging
    case timeout
}

internal enum WatchdogDetectionState: Equatable {
    case responsive
    case hanging
    case timeout
    case recovery(after: WatchdogRecoveryOrigin, heartbeatCount: Int)
    case recovered(after: WatchdogRecoveryOrigin)
}

extension WatchdogDetectionState {

    /// Encapsulates the Watchdog State Machine logic
    ///
    static func nextState(currentState: WatchdogDetectionState, settings: WatchdogSettings, secondsSinceLastHeartbeat: TimeInterval, secondsSinceHangStarted: TimeInterval) -> WatchdogDetectionState {
        switch currentState {
        case .responsive where secondsSinceLastHeartbeat > settings.minimumHangDuration:
            return .hanging

        case .responsive:
            return .responsive

        /// # Hanging: Enter Recovery if we're seeing heartbeats again
        case .hanging:
            if secondsSinceLastHeartbeat <= settings.minimumHangDuration {
                return .recovery(after: .hanging, heartbeatCount: 0)
            }

            if secondsSinceHangStarted <= settings.maximumHangDuration {
                return .hanging
            }

            return .timeout

        /// # Timeout: Enter Recovery if we're seeing heartbeats again
        case .timeout:
            if secondsSinceLastHeartbeat <= settings.minimumHangDuration {
                return .recovery(after: .timeout, heartbeatCount: 0)
            }

            return .timeout

        /// # Recovery: We'll loop back into this state, should the heartbeat become stale again
        case .recovery(let reason, let heartbeatCount):
            /// # Re-enqueue:
            ///     Stay in `.recovery` if we've been thru `.timeout` already, in order to avoid over-reporting the pixel
            if secondsSinceLastHeartbeat > settings.minimumHangDuration {
                let previouslyHanging = reason == .hanging
                return previouslyHanging ? .hanging : .recovery(after: reason, heartbeatCount: 0)
            }

            /// # Track the number of Heartbeats, until we match the recovery settings
            ///
            if heartbeatCount < settings.requiredRecoveryHeartbeats {
                return .recovery(after: reason, heartbeatCount: heartbeatCount + 1)
            }

            /// # Recovered State will track the `uiHangRecovered` only if we came from `.hanging`. Timeouts are doomed
            return .recovered(after: reason)

        case .recovered:
            return .responsive
        }
    }
}
