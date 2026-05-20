//
//  IdleReturnTabCountInstrumentation.swift
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

import Core

/// Tab-count snapshot instrumentation for the NTP-after-idle Tab Bloat investigation.
///
/// Fires once per day on app foreground when the feature is available, emitting either
/// `appOpenDailyTabCountIdleNTP` or `appOpenDailyTabCountIdleLastTab` based on the user's
/// effective after-inactivity setting. Parameters mirror the existing
/// `m_tab_manager_opened_daily` pixel (via `TabSwitcherOpenDailyPixel`) so the two
/// distributions can be compared directly.
protocol IdleReturnTabCountInstrumentation: AnyObject {

    /// Records a foreground event. No-op when the NTP-after-idle feature is unavailable.
    /// Throttled to once-per-day per pixel by `DailyPixel`.
    func recordAppForeground(tabs: [Tab], browsingMode: String)
}

final class DefaultIdleReturnTabCountInstrumentation: IdleReturnTabCountInstrumentation {

    private let eligibilityManager: IdleReturnEligibilityManaging
    private let fireDaily: (Pixel.Event, [String: String]) -> Void

    init(eligibilityManager: IdleReturnEligibilityManaging,
         fireDaily: @escaping (Pixel.Event, [String: String]) -> Void = { event, params in
             DailyPixel.fireDaily(event, withAdditionalParameters: params)
         }) {
        self.eligibilityManager = eligibilityManager
        self.fireDaily = fireDaily
    }

    func recordAppForeground(tabs: [Tab], browsingMode: String) {
        guard eligibilityManager.isFeatureAvailable() else { return }

        let pixel: Pixel.Event
        switch eligibilityManager.effectiveAfterInactivityOption() {
        case .newTab: pixel = .appOpenDailyTabCountIdleNTP
        case .lastUsedTab: pixel = .appOpenDailyTabCountIdleLastTab
        }

        var params = TabSwitcherOpenDailyPixel().parameters(with: tabs)
        params[PixelParameters.browsingMode] = browsingMode
        fireDaily(pixel, params)
    }
}
