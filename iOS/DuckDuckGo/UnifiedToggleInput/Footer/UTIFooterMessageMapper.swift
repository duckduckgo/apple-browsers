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

import Foundation

struct UTIFooterMessageMapper {

    private let resetDescriber: UTIFooterResetDescriber

    init(resetDescriber: UTIFooterResetDescriber = UTIFooterResetDescriber()) {
        self.resetDescriber = resetDescriber
    }

    func message(for warning: UTIFooterWarning, now: Date) -> UTIFooterMessage {
        switch warning {
        case .usageThreshold(let window, let threshold, let resetsAt):
            UTIFooterMessage(
                icon: .usageRing(progress: Double(threshold.rawValue) / 100),
                title: Self.thresholdTitle(percent: threshold.rawValue, window: window),
                subtitle: subtitle(resetsAt: resetsAt, now: now),
                primaryAction: .init(title: UserText.utiDuckAIWarningsReduceUsage, action: .reduceUsage),
                isDismissible: true
            )
        case .limitReached(let window, let resetsAt):
            UTIFooterMessage(
                icon: .alert,
                title: Self.limitReachedTitle(window: window),
                subtitle: subtitle(resetsAt: resetsAt, now: now),
                primaryAction: .init(title: UserText.utiDuckAIWarningsSwitch, action: .switchModel),
                isDismissible: true
            )
        }
    }

    private func subtitle(resetsAt: Date, now: Date) -> String {
        String(format: UserText.utiDuckAIWarningsResetsIn, resetDescriber.describe(until: resetsAt, from: now))
    }

    private static func thresholdTitle(percent: Int, window: UTIFooterUsageWindow) -> String {
        switch window {
        case .weekly: String(format: UserText.utiDuckAIWarningsWeeklyUsageTitle, percent)
        case .daily: String(format: UserText.utiDuckAIWarningsDailyUsageTitle, percent)
        }
    }

    private static func limitReachedTitle(window: UTIFooterUsageWindow) -> String {
        switch window {
        case .weekly: UserText.utiDuckAIWarningsWeeklyLimitReached
        case .daily: UserText.utiDuckAIWarningsDailyLimitReached
        }
    }
}
