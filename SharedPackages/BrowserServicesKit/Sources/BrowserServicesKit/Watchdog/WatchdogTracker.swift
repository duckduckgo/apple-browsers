//
//  WatchdogTracker.swift
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

internal final class WatchdogTracker {

    private let lock = NSLock()
    private var heartbeatTimestamp: DispatchTime = .now()
    private var hangStartTimestamp: DispatchTime?
    private var timeoutFireTimestamp: DispatchTime?

    func signalHeartbeat() {
        lock.withLock {
            heartbeatTimestamp = .now()
        }
    }

    func signalHangDetectedIfNeeded(secondsSinceLastHeartbeat: TimeInterval, checkInterval: TimeInterval) {
        lock.withLock {
            guard hangStartTimestamp == nil else {
                return
            }

            let delta = max(secondsSinceLastHeartbeat - checkInterval / 2, 0)
            hangStartTimestamp = DispatchTime.now(subtractingSeconds: delta)
        }
    }

    func signalHangRecovered() {
        lock.withLock {
            hangStartTimestamp = nil
        }
    }

    func signalTimeoutFired() {
        lock.withLock {
            timeoutFireTimestamp = .now()
        }
    }

    var lastHeartbeatTimestamp: DispatchTime {
        lock.withLock {
            heartbeatTimestamp
        }
    }

    var lastHangStartTimestamp: DispatchTime? {
        lock.withLock {
            hangStartTimestamp
        }
    }

    var secondsSinceLastHeartbeat: TimeInterval {
        lastHeartbeatTimestamp.secondsElapsedSinceNow
    }

    var secondsSinceHangStarted: TimeInterval {
        lastHangStartTimestamp?.secondsElapsedSinceNow ?? .zero
    }

    var secondsSinceLastTimeoutFire: TimeInterval? {
        timeoutFireTimestamp?.secondsElapsedSinceNow
    }
}

private extension DispatchTime {

    var secondsElapsedSinceNow: TimeInterval {
        let delta = DispatchTime.now().uptimeNanoseconds - uptimeNanoseconds
        return TimeInterval(Double(delta) / .nanosecondsPerSecond)
    }

    static func now(subtractingSeconds delta: TimeInterval) -> DispatchTime {
        let adjustmentNanoseconds = delta * .nanosecondsPerSecond
        return DispatchTime(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds - UInt64(adjustmentNanoseconds))
    }
}

private extension Double {

    static let nanosecondsPerSecond = Double(NSEC_PER_SEC)
}
