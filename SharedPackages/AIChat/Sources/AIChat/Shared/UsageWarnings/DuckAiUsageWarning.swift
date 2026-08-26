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

/// Which of the specified messages this is, named after the web app's notice ids so mapping copy
/// stays a lookup. Never derived from percentages, tier, or model rank — web decides.
public typealias DuckAiUsageMessage = DuckAiUsageNotice.ID

public enum DuckAiUsageAction: Equatable {
    case switchToModel(DuckAiModelSuggestion)
    case switchToFreeModel(DuckAiModelSuggestion)
    /// `isTrialEligible` picks the copy; both route to the same upsell.
    case tryForFree(isTrialEligible: Bool)
    /// Carries the entries web named for this hand-off; native writes them verbatim and sends no header.
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

    /// Only the weekly hand-off consumes its notice: it writes an opt-in that the payload can't
    /// reflect until web republishes, so re-showing the same drawer would read as the tap doing
    /// nothing. A model switch or an upsell leaves the notice true — and a switch drops its own
    /// button anyway, because the picker then *is* the target.
    var suppressesNoticeUntilSnapshotChanges: Bool {
        if case .startUsingWeeklyLimit = self { return true }
        return false
    }

    /// For pixels and the debug log: the web app's cta id this action came from.
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
    /// The display percentage, as sent: capped at 99 web-side until the limit is reached.
    public let percent: Int
    public let resetsIn: DuckAiUsageResetInterval
    public let isDismissible: Bool
    public let action: DuckAiUsageAction?
    /// The `>` beside the primary action, opening the native model picker.
    public let offersModelPicker: Bool

    public init(window: DuckAiUsageWindow,
                message: DuckAiUsageMessage,
                percent: Int,
                resetsIn: DuckAiUsageResetInterval,
                isDismissible: Bool,
                action: DuckAiUsageAction? = nil,
                offersModelPicker: Bool = false) {
        self.window = window
        self.message = message
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
        case .dailyReached: headline = "Daily limit reached"
        // Free users see the reached copy for whichever window ran out.
        case .freeReached: headline = window == .daily ? "Daily limit reached" : "Weekly usage limit reached"
        case .weeklyReached: headline = "Weekly usage limit reached"
        case .weeklyReachedDegraded: headline = "Advanced AI models limit reached"
        }
        return ("\(headline) · Resets in \(resetsIn.shortDescription)", action?.buttonTitle)
    }
}
