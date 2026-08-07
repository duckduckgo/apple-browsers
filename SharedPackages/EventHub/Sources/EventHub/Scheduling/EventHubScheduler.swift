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

/// A single consolidated timer — never one per pixel (see the Tech Design's rejection of a per-pixel
/// `[String: Timer]` map). `arm(atMillis:_:)` replaces whatever was previously armed; passing `nil`
/// cancels without arming a new one. `EventHub` recomputes "the earlier of the earliest period end
/// across all telemetries, or the next write-behind flush deadline" and re-arms on every state change.
public protocol EventHubScheduler {
    /// The manager's notion of "now", as UTC epoch milliseconds (mirrors the Windows
    /// `ISchedulers.DefaultScheduler.Now`, read for both period-window arithmetic and
    /// `attributionPeriod`). Callable from any thread: `EventHub` samples it both on its own queue and,
    /// for the event entry points, on the caller's thread before dispatching.
    func nowMillis() -> Int64

    func arm(atMillis dateMillis: Int64?, _ action: @escaping () -> Void)
}

/// Production scheduler: one `DispatchSourceTimer` on a dedicated serial queue. `arm` is only ever
/// called from `EventHub`'s own queue, which is what makes the unsynchronized `timer` property safe.
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
