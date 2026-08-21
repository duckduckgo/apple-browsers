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

/// Which of the specified messages this is. Selects the headline; the action is resolved separately.
public enum DuckAiUsageMessage: String {
    case approaching
    case dailyLimitReached
    case weeklyLimitReached
    /// The weekly allowance for advanced models, as opposed to overall weekly usage.
    case advancedModelsLimitReached

    var isReached: Bool { self != .approaching }
}

public enum DuckAiUsageAction: Equatable {
    case switchToModel(DuckAiModelSuggestion)
    case switchToFreeModel(DuckAiModelSuggestion)
    /// `isTrialEligible` picks the copy; both route to the same upsell.
    case tryForFree(isTrialEligible: Bool)
    case startUsingWeeklyLimit

    var buttonTitle: String {
        switch self {
        case .switchToModel(let suggestion):
            return suggestion.modelShortName.map { "Switch to \($0)" } ?? "Switch Model"
        case .switchToFreeModel:
            return "Switch to a Free Model"
        case .tryForFree(let isTrialEligible):
            return isTrialEligible ? "Try for free" : "Subscribe"
        case .startUsingWeeklyLimit:
            return "Start using weekly limit"
        }
    }
}

public struct DuckAiUsageWarning: Equatable {

    public let window: DuckAiUsageWindow
    public let message: DuckAiUsageMessage
    public let severity: DuckAiUsageSeverity
    /// Capped at 99 until the window is blocked, then 100.
    public let percent: Int
    public let resetsIn: DuckAiUsageResetInterval
    public let isDismissible: Bool
    public let action: DuckAiUsageAction?
    /// The `>` beside the primary action, opening the native model picker.
    public let offersModelPicker: Bool

    public init(window: DuckAiUsageWindow,
                message: DuckAiUsageMessage,
                severity: DuckAiUsageSeverity,
                percent: Int,
                resetsIn: DuckAiUsageResetInterval,
                isDismissible: Bool,
                action: DuckAiUsageAction? = nil,
                offersModelPicker: Bool = false) {
        self.window = window
        self.message = message
        self.severity = severity
        self.percent = percent
        self.resetsIn = resetsIn
        self.isDismissible = isDismissible
        self.action = action
        self.offersModelPicker = offersModelPicker
    }
}

extension DuckAiUsageWarning {

    /// For the debug log only, so a decision reads straight across against the web banner. iOS and
    /// macOS deliberately drop web's "Reduce usage with a more efficient model" subtitle.
    var messagePreview: (title: String, button: String?) {
        let headline: String
        switch message {
        case .approaching: headline = "\(percent)% of \(window.rawValue) limit"
        case .dailyLimitReached: headline = "Daily limit reached"
        case .weeklyLimitReached: headline = "Weekly usage limit reached"
        case .advancedModelsLimitReached: headline = "Advanced AI models limit reached"
        }
        return ("\(headline) · Resets in \(resetsIn.shortDescription)", action?.buttonTitle)
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
