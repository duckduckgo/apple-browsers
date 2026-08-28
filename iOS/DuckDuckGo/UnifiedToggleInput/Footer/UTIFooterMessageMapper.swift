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

    func message(for notice: CreateImageModelSwitchNotice) -> UTIFooterMessage {
        let subtitleFormat = notice.previousModelHasExtraPrivacyProtections
            ? UserText.utiCreateImageModelSwitchPrivacyPreservingSubtitle
            : UserText.utiCreateImageModelSwitchSubtitle

        return UTIFooterMessage(
            icon: .modelSwitch,
            title: String(format: UserText.utiCreateImageModelSwitchTitle, notice.newModelShortName),
            subtitle: String(format: subtitleFormat, notice.previousModelShortName),
            primaryAction: nil,
            isDismissible: true
        )
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

    /// The ring tracks the real percentage; a reached limit reads as an alert rather than a full ring.
    private static func icon(for warning: DuckAiUsageWarning) -> UTIFooterMessage.Icon {
        switch warning.message {
        case .approaching:
            return .usageRing(progress: Double(warning.percent) / 100)
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
        return UTIFooterMessage.PrimaryAction(title: title, showsModelPicker: warning.offersModelPicker)
    }

    /// `nil` hides the button. `.startUsingWeeklyLimit` has no native route yet, and a button that
    /// does nothing is worse than none.
    private static func actionTitle(for action: DuckAiUsageAction?) -> String? {
        switch action {
        case .none:
            return nil
        case .switchToModel(let suggestion):
            return suggestion.modelShortName.map { String(format: UserText.utiDuckAIWarningsSwitchToModel, $0) }
                ?? UserText.utiDuckAIWarningsSwitchModel
        case .switchToFreeModel:
            return UserText.utiDuckAIWarningsSwitchToFreeModel
        case .tryForFree(let isTrialEligible):
            return isTrialEligible ? UserText.utiDuckAIWarningsTryForFree : UserText.utiDuckAIWarningsSubscribe
        case .startUsingWeeklyLimit:
            return nil
        }
    }
}
