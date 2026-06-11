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

    /// The user tapped the tab switcher pill next to the escape hatch card.
    /// (The escape hatch is only shown after idle return, so no user-initiated variant is needed.)
    func escapeHatchTabSwitcherTapped()

    /// The user tapped the close-tab action on the escape hatch card.
    func escapeHatchCloseTabTapped()

    /// The user tapped the burn-tab action on the escape hatch card.
    /// - Parameter requiredConfirmation: `true` when the burn flow shows the fire confirmation prompt, `false` when the tab is burned immediately.
    func escapeHatchBurnTapped(requiredConfirmation: Bool)

    /// The user changed the Opening Screen option from the escape hatch's settings menu.
    func escapeHatchOptionChanged(to option: AfterInactivityOption)

    /// The user hid the "Return to tab" shortcut via the card's "Don't Show This" menu item.
    func escapeHatchHiddenFromMenu()
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

    func escapeHatchTabSwitcherTapped() {
        guard eligibilityManager.isEligibleForNTPAfterIdle() else { return }
        firePixel(.ntpAfterIdleEscapeHatchTabSwitcherTappedAfterIdle)
    }

    func escapeHatchCloseTabTapped() {
        firePixel(.ntpAfterIdleEscapeHatchCloseTabTapped)
    }

    func escapeHatchBurnTapped(requiredConfirmation: Bool) {
        firePixel(requiredConfirmation ? .ntpAfterIdleEscapeHatchBurnWithConfirmationTapped : .ntpAfterIdleEscapeHatchBurnImmediatelyTapped)
    }

    func escapeHatchOptionChanged(to option: AfterInactivityOption) {
        firePixel(option == .newTab ? .ntpAfterIdleEscapeHatchAfterInactivitySettingChangedToNewTab : .ntpAfterIdleEscapeHatchAfterInactivitySettingChangedToLastUsedTab)
    }

    func escapeHatchHiddenFromMenu() {
        firePixel(.ntpAfterIdleEscapeHatchHiddenFromMenu)
    }
}
