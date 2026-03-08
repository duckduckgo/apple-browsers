//
//  NTPAfterIdleInstrumentation.swift
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

/// Domain-event hooks for the NTP-after-idle feature.
///
/// All methods are no-ops when the feature is disabled (feature flag off or
/// user setting not set to New Tab). The `afterIdle` parameter distinguishes
/// NTPs shown by the idle-return flow from user-initiated ones.
protocol NTPAfterIdleInstrumentation: AnyObject {

    /// The NTP was displayed (either after idle or user-initiated).
    func ntpShown(afterIdle: Bool)

    /// The user tapped the "Return to [page]" escape hatch card.
    func returnToPageTapped(afterIdle: Bool)

    /// The user submitted a query from the address bar while on the NTP.
    func barUsedFromNTP(afterIdle: Bool)

    /// The user toggled between search and Duck.ai while on the NTP.
    func toggleUsedFromNTP(afterIdle: Bool)

    /// The user tapped the back (defocus) button while on the NTP.
    func backButtonUsedFromNTP(afterIdle: Bool)

    /// The app was backgrounded while the NTP was visible.
    func appBackgroundedFromNTP(afterIdle: Bool)

    /// The user opened the tab switcher while on the NTP.
    func tabSwitcherSelectedFromNTP(afterIdle: Bool)
}

final class DefaultNTPAfterIdleInstrumentation: NTPAfterIdleInstrumentation {

    private let eligibilityManager: IdleReturnEligibilityManaging
    private let firePixel: (Pixel.Event) -> Void

    init(eligibilityManager: IdleReturnEligibilityManaging,
         firePixel: @escaping (Pixel.Event) -> Void = { DailyPixel.fireDailyAndCount(pixel: $0) }) {
        self.eligibilityManager = eligibilityManager
        self.firePixel = firePixel
    }

    func ntpShown(afterIdle: Bool) {
        guard eligibilityManager.isEligibleForNTPAfterIdle() else { return }
        firePixel(afterIdle ? .ntpAfterIdleNTPShownAfterIdle : .ntpAfterIdleNTPShownUserInitiated)
    }

    func returnToPageTapped(afterIdle: Bool) {
        guard eligibilityManager.isEligibleForNTPAfterIdle() else { return }
        firePixel(afterIdle ? .ntpAfterIdleReturnToPageTappedAfterIdle : .ntpAfterIdleReturnToPageTappedUserInitiated)
    }

    func barUsedFromNTP(afterIdle: Bool) {
        guard eligibilityManager.isEligibleForNTPAfterIdle() else { return }
        firePixel(afterIdle ? .ntpAfterIdleBarUsedAfterIdle : .ntpAfterIdleBarUsedUserInitiated)
    }

    func toggleUsedFromNTP(afterIdle: Bool) {
        guard eligibilityManager.isEligibleForNTPAfterIdle() else { return }
        firePixel(afterIdle ? .ntpAfterIdleToggleUsedAfterIdle : .ntpAfterIdleToggleUsedUserInitiated)
    }

    func backButtonUsedFromNTP(afterIdle: Bool) {
        guard eligibilityManager.isEligibleForNTPAfterIdle() else { return }
        firePixel(afterIdle ? .ntpAfterIdleBackButtonUsedAfterIdle : .ntpAfterIdleBackButtonUsedUserInitiated)
    }

    func appBackgroundedFromNTP(afterIdle: Bool) {
        guard eligibilityManager.isEligibleForNTPAfterIdle() else { return }
        firePixel(afterIdle ? .ntpAfterIdleAppBackgroundedAfterIdle : .ntpAfterIdleAppBackgroundedUserInitiated)
    }

    func tabSwitcherSelectedFromNTP(afterIdle: Bool) {
        guard eligibilityManager.isEligibleForNTPAfterIdle() else { return }
        firePixel(afterIdle ? .ntpAfterIdleTabSwitcherSelectedAfterIdle : .ntpAfterIdleTabSwitcherSelectedUserInitiated)
    }
}
