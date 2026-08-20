//
//  DuckAiUsageWarning.swift
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

/// The windows the web app reports. The 6-hour and monthly windows are deliberately not part of the
/// native payload, so there is nothing to warn about for them.
public enum DuckAiUsageWindow: String, CaseIterable {
    case daily
    case weekly
}

public enum DuckAiUsageSeverity: Int, Comparable {
    case info
    case warning
    case critical
    case reached

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var loggingName: String {
        switch self {
        case .info: return "info"
        case .warning: return "warning"
        case .critical: return "critical"
        case .reached: return "reached"
        }
    }
}

/// How long until the window resets, at the granularity the copy uses.
public enum DuckAiUsageResetInterval: Equatable {
    case days(Int)
    case hours(Int)

    /// `"3d"` / `"5h"`. The localized `Resets in {…}` wrapper belongs to the UI layer.
    public var shortDescription: String {
        switch self {
        case .days(let days): return "\(days)d"
        case .hours(let hours): return "\(hours)h"
        }
    }

    /// Two edges here look like bugs and aren't — they're what the web copy does, so leave them:
    /// 25h renders as `"2d"` rather than `"1d"`, and 23.9h renders as `"24h"` rather than `"1d"`.
    public static func from(now: Date, resetsAt: Date) -> Self {
        let interval = resetsAt.timeIntervalSince(now)
        // Only reachable if the clock moves between read and render — `DuckAiUsageLimits.make` already
        // drops windows that have already reset.
        guard interval > 0 else { return .hours(0) }

        if interval >= Self.secondsPerDay {
            return .days(Int((interval / Self.secondsPerDay).rounded(.up)))
        }
        return .hours(max(1, Int((interval / Self.secondsPerHour).rounded(.up))))
    }

    private static let secondsPerHour: TimeInterval = 60 * 60
    private static let secondsPerDay: TimeInterval = 24 * 60 * 60
}

/// The single message that should be on screen, already resolved against tier, thresholds and dismissal.
public struct DuckAiUsageWarning: Equatable {

    public enum Kind: String {
        /// "{n}% of daily limit" — a heads-up, dismissible by paid and internal users.
        case approaching
        /// "Daily limit reached" — sticky, shown to every tier, clears only when the window resets.
        case reached
    }

    public let window: DuckAiUsageWindow
    public let kind: Kind
    public let severity: DuckAiUsageSeverity
    /// Rounded, capped at 99 until the window is blocked, then 100.
    public let percent: Int
    public let resetsIn: DuckAiUsageResetInterval
    public let isDismissible: Bool
    public let cheaperModelSuggestion: DuckAiCheaperModelSuggestion?

    public init(window: DuckAiUsageWindow,
                kind: Kind,
                severity: DuckAiUsageSeverity,
                percent: Int,
                resetsIn: DuckAiUsageResetInterval,
                isDismissible: Bool,
                cheaperModelSuggestion: DuckAiCheaperModelSuggestion? = nil) {
        self.window = window
        self.kind = kind
        self.severity = severity
        self.percent = percent
        self.resetsIn = resetsIn
        self.isDismissible = isDismissible
        self.cheaperModelSuggestion = cheaperModelSuggestion
    }
}

extension DuckAiUsageWindow {

    /// Below this the warning is hidden entirely, unless the window is already blocked.
    static let visibilityFloor: Double = 50

    /// Shared by both windows — drives how urgent the message looks.
    static let severityLadder: [(floor: Double, severity: DuckAiUsageSeverity)] = [
        (90, .critical),
        (75, .warning),
        (50, .info)
    ]

    /// Per-window, and deliberately *not* the severity ladder: a daily banner dismissed at 50% stays
    /// hidden through 75% — where it is already `.warning` — and only comes back at 90%.
    var redisplayLadder: [Int] {
        switch self {
        case .daily: return [50, 90, 100]
        case .weekly: return [50, 75, 90, 100]
        }
    }

    func severity(forPercentUsed percentUsed: Double) -> DuckAiUsageSeverity? {
        Self.severityLadder.first { percentUsed >= $0.floor }?.severity
    }

    /// The highest redisplay threshold this percentage has crossed — the bucket a dismissal is recorded
    /// against, so that crossing the next one brings the message back.
    func redisplayThreshold(forPercentUsed percentUsed: Double) -> Int {
        redisplayLadder.last { percentUsed >= Double($0) } ?? 0
    }
}
