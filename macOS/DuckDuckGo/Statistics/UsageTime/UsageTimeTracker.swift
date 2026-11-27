//
//  UsageTimeTracker.swift
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

struct UsageTimeReading {
    let date: Date
    let uptime: TimeInterval

    static func now() -> Self {
        Self(date: Date(), uptime: ProcessInfo.processInfo.systemUptime)
    }
}

struct UsageTimeIncrement: Equatable {
    let start: Date
    let open: TimeInterval
    let active: TimeInterval
}

struct UsageTimeTracker {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    enum Event {
        case start, input, resignActive, checkpoint, stop
    }

    private var previous: UsageTimeReading?
    private var activeUntil: TimeInterval?

    /// The caller supplies input only for a frontmost browser window.
    mutating func record(_ event: Event, at reading: UsageTimeReading) -> [UsageTimeIncrement] {
        guard let previous else {
            guard event == .start else { return [] }
            self.previous = reading
            return [UsageTimeIncrement(start: reading.date, open: 0, active: 0)]
        }

        let elapsed = max(0, reading.uptime - previous.uptime)
        let active = min(elapsed, max(0, (activeUntil ?? previous.uptime) - previous.uptime))
        var increments = Self.split(from: previous.date, to: reading.date, elapsed: elapsed, active: active)
        // Stopping exactly at midnight leaves the next day's first signal to the next session.
        if event == .stop, increments.count > 1, increments.last?.open == 0 {
            increments.removeLast()
        }
        self.previous = event == .stop ? nil : reading

        switch event {
        case .input:
            activeUntil = reading.uptime + 5 * 60
        case .resignActive, .stop:
            activeUntil = nil
        case .start, .checkpoint:
            break
        }
        return increments
    }

    private static func split(from start: Date, to end: Date, elapsed: TimeInterval, active: TimeInterval) -> [UsageTimeIncrement] {
        let whole = UsageTimeIncrement(start: start, open: elapsed, active: active)
        guard !calendar.isDate(start, inSameDayAs: end) else { return [whole] }
        // A wall-clock correction cannot create usage on skipped dates.
        guard abs(end.timeIntervalSince(start) - elapsed) < 1, end > start else {
            return [whole, UsageTimeIncrement(start: end, open: 0, active: 0)]
        }
        var increments: [UsageTimeIncrement] = []
        var cursor = start
        var remainingOpen = elapsed
        var remainingActive = active
        while let midnight = calendar.dateInterval(of: .day, for: cursor)?.end, midnight <= end {
            let open = min(remainingOpen, midnight.timeIntervalSince(cursor))
            let activePart = min(remainingActive, open)
            increments.append(UsageTimeIncrement(start: cursor, open: open, active: activePart))
            remainingOpen -= open
            remainingActive -= activePart
            cursor = midnight
        }
        increments.append(UsageTimeIncrement(start: cursor, open: remainingOpen, active: remainingActive))
        return increments
    }
}
