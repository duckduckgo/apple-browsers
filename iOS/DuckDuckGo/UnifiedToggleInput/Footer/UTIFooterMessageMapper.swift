//
//  UTIFooterMessageMapper.swift
//  DuckDuckGo
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

import AIChat
import Foundation

/// The card's copy. `DuckAiUsageWarning` has already decided what to say and what to offer; the
/// module's own `messagePreview` is debug-log-only, so the user-facing strings come from here.
struct UTIFooterMessageMapper {

    private let resetDescriber: UTIFooterResetDescriber

    init(resetDescriber: UTIFooterResetDescriber = UTIFooterResetDescriber()) {
        self.resetDescriber = resetDescriber
    }

    func message(for warning: DuckAiUsageWarning) -> UTIFooterMessage {
        UTIFooterMessage(
            icon: Self.icon(for: warning),
            title: Self.title(for: warning),
            subtitle: String(format: UserText.utiDuckAIWarningsResetsIn, resetDescriber.describe(warning.resetsIn)),
            primaryAction: Self.primaryAction(for: warning),
            isDismissible: warning.isDismissible
        )
    }

    /// Keyed off the selected model rather than the allowance, so there is no percentage, no reset
    /// line and nothing to switch to — the copy is the whole message.
    func message(for notice: DuckAiHighUsageModelNotice) -> UTIFooterMessage {
        UTIFooterMessage(
            icon: .none,
            title: String(format: UserText.utiDuckAIWarningsHighUsageModel, notice.modelShortName),
            subtitle: nil,
            primaryAction: nil,
            isDismissible: true
        )
    }

    /// The ring tracks the real percentage; a reached limit reads as an alert rather than a full ring.
    private static func icon(for warning: DuckAiUsageWarning) -> UTIFooterMessage.Icon {
        switch warning.message {
        case .approaching:
            return .usageRing(progress: Double(warning.percent) / 100, severity: warning.severity)
        case .dailyLimitReached, .weeklyLimitReached, .advancedModelsLimitReached:
            return .alert
        }
    }

    private static func title(for warning: DuckAiUsageWarning) -> String {
        switch warning.message {
        case .approaching:
            switch warning.window {
            case .daily: return String(format: UserText.utiDuckAIWarningsDailyUsageTitle, warning.percent)
            case .weekly: return String(format: UserText.utiDuckAIWarningsWeeklyUsageTitle, warning.percent)
            }
        case .dailyLimitReached:
            return UserText.utiDuckAIWarningsDailyLimitReached
        case .weeklyLimitReached:
            return UserText.utiDuckAIWarningsWeeklyLimitReached
        case .advancedModelsLimitReached:
            return UserText.utiDuckAIWarningsAdvancedModelsLimitReached
        }
    }

    private static func primaryAction(for warning: DuckAiUsageWarning) -> UTIFooterMessage.PrimaryAction? {
        guard let title = actionTitle(for: warning.action) else { return nil }
        return UTIFooterMessage.PrimaryAction(title: title)
    }

    /// `nil` hides the button. `.startUsingWeeklyLimit` has no native route yet, and a button that
    /// does nothing is worse than none.
    private static func actionTitle(for action: DuckAiUsageAction?) -> String? {
        switch action {
        case .none:
            return nil
        // One word for every model switch: the card has no room to name a model, and the toolbar's
        // own picker is where a different choice is made.
        case .switchToModel, .switchToFreeModel:
            return UserText.utiDuckAIWarningsSwitch
        case .tryForFree(let isTrialEligible):
            return isTrialEligible ? UserText.utiDuckAIWarningsTryForFree : UserText.utiDuckAIWarningsSubscribe
        case .startUsingWeeklyLimit:
            return nil
        }
    }
}
