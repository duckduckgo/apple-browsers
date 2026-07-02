//
//  CookiePopupProtectionOptInPromoDelegate.swift
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

import AppKit
import BrowserServicesKit
import Combine
import FeatureFlags
import WebExtensions

/// Persisted state for the Cookie Pop-up Protection opt-in dialog (showing conditions + debug reset).
struct CookiePopupProtectionOptInPromptStore {
    private static let shownCountKey = "cookie-popup-protection.opt-in.shown-count"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// How many times the dialog has been shown on launch.
    var shownCount: Int {
        get { userDefaults.integer(forKey: Self.shownCountKey) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.shownCountKey) }
    }

    /// Clears all persisted opt-in dialog state (debug reset).
    func reset() {
        userDefaults.removeObject(forKey: Self.shownCountKey)
    }
}

/// Presents the Cookie Pop-up Protection opt-in dialog through the promo queue.
/// Shown only while the Cookie Pop-up Protection setting feature flag is on, at most `maxShowCount` times,
/// only ≥ `minDaysSinceInstall` days after install, and not while the user is already on the max
/// (Reject, Hide, or Accept) setting; confirming permanently dismisses the promo (via `.actioned`),
/// so it isn't shown again afterwards.
final class CookiePopupProtectionOptInPromoDelegate: InternalPromoDelegate {

    /// Maximum number of times the dialog may be shown.
    private static let maxShowCount = 3
    /// The dialog is only shown once the install is at least this many days old.
    private static let minDaysSinceInstall = 2

    private var showContinuation: CheckedContinuation<PromoResult, Never>?
    private let store = CookiePopupProtectionOptInPromptStore()
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(false)

    init() {
        refreshEligibility()
    }

    var isEligible: Bool { computeEligibility() }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        isEligibleSubject.removeDuplicates().eraseToAnyPublisher()
    }

    func refreshEligibility() {
        isEligibleSubject.send(computeEligibility())
    }

    private func computeEligibility() -> Bool {
        let featureFlagger = Application.appDelegate.featureFlagger
        guard featureFlagger.isFeatureOn(.cookiePopupPreferenceSetting),
              featureFlagger.isFeatureOn(.cookiePopupOptInDialog) else { return false }
        // Nothing to offer users already on the most-private setting — it already accepts no-opt-out cookies.
        guard Application.appDelegate.cookiePopupProtectionPreferences.cookiePopupPreference != .max else { return false }
        guard store.shownCount < Self.maxShowCount else { return false }
        guard let installDate = LocalStatisticsStore().installDate else { return false }
        let daysSinceInstall = Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
        return daysSinceInstall >= Self.minDaysSinceInstall
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        guard let browserTabViewController = Application.appDelegate.windowControllersManager
            .lastKeyMainWindowController?.mainViewController.browserTabViewController else {
            return .noChange
        }

        return await withCheckedContinuation { continuation in
            showContinuation = continuation
            let presented = browserTabViewController.showCookiePopupProtectionOptInDialog(onConfirm: { [weak self] _ in
                self?.resume(with: .actioned)
            })
            // The dialog couldn't be presented (no window, or one is already up): finish the session
            // immediately instead of leaving the promo hanging on an unresolved continuation.
            guard presented else {
                resume(with: .noChange)
                return
            }
            // Skip counting for force-shows (promo debug menu).
            if !force {
                store.shownCount += 1
            }
        }
    }

    @MainActor
    func hide() {
        Application.appDelegate.windowControllersManager
            .lastKeyMainWindowController?.mainViewController.browserTabViewController
            .dismissCookiePopupProtectionOptInDialog()
        resume(with: .noChange)
    }

    private func resume(with result: PromoResult) {
        showContinuation?.resume(returning: result)
        showContinuation = nil
    }
}
