//
//  VPNSessionHealthRolloverSchedule.swift
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

/// Calculates UTC-aligned rollover boundaries, evaluated on instrumentation callbacks rather than by a timer.
struct VPNSessionHealthRolloverSchedule {

    private enum Constants {
        static let defaultRolloverInterval: TimeInterval = 60 * 60
        static let debugRolloverInterval: TimeInterval = 4 * 60
    }

    let interval: TimeInterval

    /// Defaults to hourly rollover. Debug builds can opt into four-minute boundaries (:00, :04, :08, ...).
    /// Release builds always use hourly boundaries, regardless of `isDebugRolloverEnabled`.
    init(isDebugRolloverEnabled: Bool = false) {
#if DEBUG
        interval = isDebugRolloverEnabled ? Constants.debugRolloverInterval : Constants.defaultRolloverInterval
#else
        interval = Constants.defaultRolloverInterval
#endif
    }

    /// Returns the first boundary after `start` as `endedAt` and the boundary at or before `now` as `startedAt`.
    /// Returns `nil` if both dates fall in the same interval or `now` is not after `start`.
    /// If multiple boundaries were crossed, the dates skip intervening intervals rather than creating empty events.
    ///
    /// # Examples with the default hourly interval (all times UTC):
    ///     - start = 10:45, now = 11:00 → (endedAt: 11:00, startedAt: 11:00)
    ///     - start = 10:20, now = 13:05 → (endedAt: 11:00, startedAt: 13:00)
    ///
    /// # Examples with the four-minute debug interval (all times UTC):
    ///     - start = 10:45, now = 10:48 → (endedAt: 10:48, startedAt: 10:48)
    ///     - start = 10:20, now = 10:31 → (endedAt: 10:24, startedAt: 10:28)
    ///     - start = 10:04, now = 10:05 → nil (same interval)
    ///     - start = 11:00, now = 10:00 → nil (now not after start)
    func rolloverDates(from start: Date, to now: Date) -> (endedAt: Date, startedAt: Date)? {
        guard now > start else {
            return nil
        }

        let startInterval = (start.timeIntervalSince1970 / interval).rounded(.down)
        let currentInterval = (now.timeIntervalSince1970 / interval).rounded(.down)
        guard currentInterval > startInterval else {
            return nil
        }

        return (endedAt: Date(timeIntervalSince1970: (startInterval + 1) * interval),
                startedAt: Date(timeIntervalSince1970: currentInterval * interval))
    }
}
