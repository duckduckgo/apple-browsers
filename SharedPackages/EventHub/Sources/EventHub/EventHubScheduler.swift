//
//  EventHubScheduler.swift
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
///
/// - Important: `queue` must be a **different** `DispatchQueue` instance from the one passed to
///   `EventHub.init(queue:)`. This queue is where the timer fires; `EventHub`'s scheduler-fire handler
///   then calls `.sync` onto its own queue to serialize the fire with all its other state mutations. If
///   the two queues are the same instance, the timer fires ON that queue and the `.sync` call is then
///   dispatched onto the queue it's already executing on — a silent deadlock (the block waiting on
///   `.sync` can never run until the currently-executing block — itself — returns).
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
