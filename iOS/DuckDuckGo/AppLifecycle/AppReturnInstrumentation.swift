//
//  AppReturnInstrumentation.swift
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
import PixelKit

enum AppReturnPixel: PixelKit.Event, PixelKitEventWithCustomPrefix {

    case appReturn

    var name: String { "app_return" }

    var parameters: [String: String]? { nil }

    var standardParameters: [PixelKitStandardParameter]? { nil }

    var namePrefix: String { "m_" }
}

protocol AppReturnInstrumentation {
    func recordAppForeground(lastBackgroundDate: Date?, launchAction: LaunchAction)
}

final class DefaultAppReturnInstrumentation: AppReturnInstrumentation {

    private let eligibilityManager: IdleReturnEligibilityManaging
    private let isUnifiedInputAvailable: () -> Bool
    private let isToggleEnabled: () -> Bool
    private let now: () -> Date
    private let delay: PixelTransmissionDelaying
    private let fireDailyAndCount: (AppReturnPixel, [String: String], @escaping PixelKit.CompletionBlock) -> Void

    init(eligibilityManager: IdleReturnEligibilityManaging,
         isUnifiedInputAvailable: @escaping () -> Bool = { UnifiedToggleInputFeature().isAvailable },
         isToggleEnabled: @escaping () -> Bool,
         now: @escaping () -> Date = Date.init,
         delay: PixelTransmissionDelaying = PixelTransmissionDelay(),
         fireDailyAndCount: @escaping (AppReturnPixel, [String: String], @escaping PixelKit.CompletionBlock) -> Void = { event, params, onComplete in
             PixelKit.fire(event, frequency: .dailyAndCount, withAdditionalParameters: params, onComplete: onComplete)
         }) {
        self.eligibilityManager = eligibilityManager
        self.isUnifiedInputAvailable = isUnifiedInputAvailable
        self.isToggleEnabled = isToggleEnabled
        self.now = now
        self.delay = delay
        self.fireDailyAndCount = fireDailyAndCount
    }

    func recordAppForeground(lastBackgroundDate: Date?, launchAction: LaunchAction) {
        let thresholdSeconds = eligibilityManager.idleThresholdSeconds()
        let timeAway = lastBackgroundDate.map { now().timeIntervalSince($0) }

        let afterInactivityOption: String
        switch eligibilityManager.effectiveAfterInactivityOption() {
        case .newTab: afterInactivityOption = "new_tab"
        case .lastUsedTab: afterInactivityOption = "last_used_tab"
        }

        let parameters = [
            "time_away_bucket": Self.timeAwayBucket(for: timeAway),
            "exceeded_idle_threshold": String(timeAway.map { $0 >= Double(thresholdSeconds) } ?? false),
            "idle_threshold_seconds": String(thresholdSeconds),
            "after_inactivity_option": afterInactivityOption,
            "feature_eligible": String(eligibilityManager.isFeatureAvailable()),
            "unified_input_available": String(isUnifiedInputAvailable()),
            "toggle_enabled": String(isToggleEnabled()),
            "launch_source": Self.launchSource(for: launchAction)
        ]

        // Defer the whole fire, not just the request: the daily marker is written inside it.
        let fire = fireDailyAndCount
        delay.delaySend { requestDidFinish in
            fire(.appReturn, parameters) { _, _ in requestDidFinish() }
        }
    }

    static func timeAwayBucket(for timeAway: TimeInterval?) -> String {
        guard let timeAway else { return "cold_start" }
        switch timeAway {
        case ..<60: return "lt_1m"
        case ..<300: return "1_5m"
        case ..<900: return "5_15m"
        case ..<1800: return "15_30m"
        case ..<3600: return "30_60m"
        default: return "gt_60m"
        }
    }

    static func launchSource(for launchAction: LaunchAction) -> String {
        switch launchAction {
        case .openURL: return "url"
        case .handleShortcutItem: return "shortcut"
        case .handleUserActivity: return "user_activity"
        case .standardLaunch: return "standard"
        }
    }
}
