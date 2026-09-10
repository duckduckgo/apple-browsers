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

/// Presentation only: which colour the usage ring draws in. Not a decision — web says which message
/// to show, this just reads the percentage it sent.
public enum DuckAiUsageSeverity: Int, Comparable {
    case info
    case warning
    case critical
    case reached

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    static func from(percentUsed: Int, reached: Bool) -> Self {
        guard !reached else { return .reached }

        switch percentUsed {
        case 90...: return .critical
        case 75...: return .warning
        default: return .info
        }
    }

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

/// Named after web's notice ids so mapping copy stays a lookup rather than a derivation.
public typealias DuckAiUsageMessage = DuckAiUsageNotice.ID

public enum DuckAiUsageAction: Equatable {
    case switchToModel(DuckAiModelSuggestion)
    case switchToFreeModel(DuckAiModelSuggestion)
    /// `isTrialEligible` picks the copy; both route to the same upsell.
    case tryForFree(isTrialEligible: Bool)
    /// Native writes these verbatim and sends no header — web builds that from the entry itself.
    case startUsingWeeklyLimit(entries: [DuckAiNativeStorageEntry])

    /// The `>` modifies a model switch, so it never pairs with the upsell or the weekly hand-off.
    var offersModelPicker: Bool {
        switch self {
        case .switchToModel, .switchToFreeModel: return true
        case .tryForFree, .startUsingWeeklyLimit: return false
        }
    }

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

    /// True for anything that changes what the user is about to spend: the payload can't reflect it
    /// until web republishes, so leaving the message up would read as the tap having done nothing.
    var suppressesNoticeUntilSnapshotChanges: Bool {
        switch self {
        case .switchToModel, .switchToFreeModel, .startUsingWeeklyLimit: return true
        case .tryForFree: return false
        }
    }

    /// The model the message is offering, for spotting the user picking it somewhere else.
    var suggestedModelId: String? {
        switch self {
        case .switchToModel(let suggestion), .switchToFreeModel(let suggestion): return suggestion.modelId
        case .tryForFree, .startUsingWeeklyLimit: return nil
        }
    }

    /// The web app's cta id this action came from, for the debug log.
    var ctaID: DuckAiUsageCta.ID {
        switch self {
        case .switchToModel: return .switchToCheaper
        case .switchToFreeModel: return .switchToFree
        case .tryForFree: return .subscribe
        case .startUsingWeeklyLimit: return .bypassWeekly
        }
    }
}

public struct DuckAiUsageWarning: Equatable {

    public let window: DuckAiUsageWindow
    public let message: DuckAiUsageMessage
    /// As sent: capped at 99 web-side until the limit is reached.
    public let severity: DuckAiUsageSeverity
    public let percent: Int
    public let resetsIn: DuckAiUsageResetInterval
    public let isDismissible: Bool
    public let action: DuckAiUsageAction?
    /// The `>` beside the primary action, opening the native model picker.
    public let offersModelPicker: Bool

    /// The allowance is spent, so the next prompt can't be: the input goes inert and this message
    /// is the only thing left to act on, as it is on the web app.
    public var blocksInput: Bool { severity == .reached }

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

    /// The free-model message is shown *because* the advanced allowance is spent, so offering an
    /// advanced model behind its `>` contradicts the sentence it hangs off.
    public var modelPickerOffersFreeModelsOnly: Bool {
        if case .switchToFreeModel = action { return true }
        return false
    }

    /// Debug log only, so a decision reads straight across against the web banner.
    var messagePreview: (title: String, button: String?) {
        let headline: String
        switch message {
        case .approaching: headline = "\(percent)% of \(window.rawValue) limit"
        case .dailyReached: headline = "Daily limit reached"
        // One id whichever window ran out, so the window picks the noun.
        case .freeReached: headline = window == .daily ? "Daily limit reached" : "Weekly usage limit reached"
        case .weeklyReached: headline = "Weekly usage limit reached"
        case .weeklyReachedDegraded: headline = "Advanced AI models limit reached"
        }
        return ("\(headline) · Resets in \(resetsIn.shortDescription)", action?.buttonTitle)
    }
}
