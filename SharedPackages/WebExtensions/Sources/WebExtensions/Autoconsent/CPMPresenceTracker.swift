//
//  CPMPresenceTracker.swift
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

/// Whether the user can currently use the device, and when it last resumed, from notifications the app supplies.
///
/// A Mac whose screen is locked or asleep has no `background` app state, yet it is the situation in which a
/// background start is slowest (right after the system wakes, with the network process often replaced). The app
/// names the notifications for its platform; the tracker only keeps the bookkeeping so it can be tested.
///
/// Not tied to an actor: the app's delegate creates it, notifications arrive on the main queue, and diagnostics read
/// it from main-actor closures. A lock guards the state.
public final class CPMPresenceTracker: @unchecked Sendable {

    public enum Signal: Equatable, Sendable {
        case screenSlept
        case screenWoke
        case screenLocked
        case screenUnlocked
        /// The device or the app came back: the system woke (macOS) or the app became active (iOS).
        case resumed
    }

    private let now: () -> Date
    private let lock = NSLock()
    private var isScreenAsleep = false
    private var isScreenLocked = false
    private var resumeDate: Date?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    /// Whether the screen is locked or asleep, so the user cannot interact with the device.
    public var isUserAway: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isScreenAsleep || isScreenLocked
    }

    public var lastResumeDate: Date? {
        lock.lock()
        defer { lock.unlock() }
        return resumeDate
    }

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    deinit {
        observers.forEach { $0.center.removeObserver($0.token) }
    }

    public func record(_ signal: Signal) {
        lock.lock()
        defer { lock.unlock() }
        switch signal {
        case .screenSlept: isScreenAsleep = true
        case .screenWoke: isScreenAsleep = false
        case .screenLocked: isScreenLocked = true
        case .screenUnlocked: isScreenLocked = false
        case .resumed: resumeDate = now()
        }
    }

    /// Records `signal` whenever `name` is posted on `center`.
    public func observe(_ name: Notification.Name, on center: NotificationCenter, as signal: Signal) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            self?.record(signal)
        }
        lock.lock()
        observers.append((center: center, token: token))
        lock.unlock()
    }
}
