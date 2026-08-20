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

/// The 6-hour and monthly windows are deliberately absent from the native payload.
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

public enum DuckAiUsageResetInterval: Equatable {
    case days(Int)
    case hours(Int)

    /// The localized `Resets in {…}` wrapper belongs to the UI layer.
    public var shortDescription: String {
        switch self {
        case .days(let days): return "\(days)d"
        case .hours(let hours): return "\(hours)h"
        }
    }

    /// Matches web, including its odd edges: 25h reads as "2d", and 23.9h as "24h".
    public static func from(now: Date, resetsAt: Date) -> Self {
        let interval = resetsAt.timeIntervalSince(now)
        // Only reachable if the clock moves between read and render.
        guard interval > 0 else { return .hours(0) }

        if interval >= Self.secondsPerDay {
            return .days(Int((interval / Self.secondsPerDay).rounded(.up)))
        }
        return .hours(max(1, Int((interval / Self.secondsPerHour).rounded(.up))))
    }

    private static let secondsPerHour: TimeInterval = 60 * 60
    private static let secondsPerDay: TimeInterval = 24 * 60 * 60
}

public struct DuckAiUsageWarning: Equatable {

    public enum Kind: String {
        /// Dismissible by paid and internal users.
        case approaching
        /// Sticky, shown to every tier, clears only when the window resets.
        case reached
    }

    public let window: DuckAiUsageWindow
    public let kind: Kind
    public let severity: DuckAiUsageSeverity
    /// Capped at 99 until the window is blocked, then 100.
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

extension DuckAiUsageWarning {

    /// For the debug log only, so a decision reads straight across against the web banner. iOS and
    /// macOS deliberately drop web's "Reduce usage with a more efficient model" subtitle.
    var messagePreview: (title: String, button: String?) {
        switch kind {
        case .reached:
            return ("\(window.rawValue.capitalized) limit reached", nil)

        case .approaching:
            let title = "\(percent)% of \(window.rawValue) limit · Resets in \(resetsIn.shortDescription)"
            let button = cheaperModelSuggestion.map { suggestion in
                suggestion.modelShortName.map { "Switch to \($0)" } ?? "Switch Model"
            }
            return (title, button)
        }
    }
}

extension DuckAiUsageWindow {

    static let visibilityFloor: Double = 50

    static let severityLadder: [(floor: Double, severity: DuckAiUsageSeverity)] = [
        (90, .critical),
        (75, .warning),
        (50, .info)
    ]

    /// Deliberately *not* the severity ladder: a daily banner dismissed at 50% stays hidden through
    /// 75%, where it is already `.warning`, and only comes back at 90%.
    var redisplayLadder: [Int] {
        switch self {
        case .daily: return [50, 90, 100]
        case .weekly: return [50, 75, 90, 100]
        }
    }

    func severity(forPercentUsed percentUsed: Double) -> DuckAiUsageSeverity? {
        Self.severityLadder.first { percentUsed >= $0.floor }?.severity
    }

    /// The bucket a dismissal is recorded against, so crossing the next one brings the message back.
    func redisplayThreshold(forPercentUsed percentUsed: Double) -> Int {
        redisplayLadder.last { percentUsed >= Double($0) } ?? 0
    }
}
