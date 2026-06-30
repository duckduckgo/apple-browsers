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
import PixelKit
import WebExtensions

/// Persisted state for the Cookie Pop-up Protection opt-in dialog (for telemetry + showing conditions + debug reset).
struct CookiePopupProtectionOptInPromptStore {
    private static let firstShownDateKey = "cookie-popup-protection.opt-in.first-shown-date"
    private static let shownCountKey = "cookie-popup-protection.opt-in.shown-count"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var firstShownDate: Date? {
        get { userDefaults.object(forKey: Self.firstShownDateKey) as? Date }
        nonmutating set { userDefaults.set(newValue, forKey: Self.firstShownDateKey) }
    }

    /// How many times the dialog has been shown on launch.
    var shownCount: Int {
        get { userDefaults.integer(forKey: Self.shownCountKey) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.shownCountKey) }
    }

    /// Bucketed time elapsed from the first-shown date to `now`, for telemetry.
    func bucketedTimeSinceFirstShown(now: Date = Date()) -> String? {
        guard let firstShownDate else { return nil }
        return CookiePopupProtectionOptInTimeBucket.bucket(for: now.timeIntervalSince(firstShownDate))
    }

    /// Clears all persisted opt-in dialog state (debug reset).
    func reset() {
        userDefaults.removeObject(forKey: Self.firstShownDateKey)
        userDefaults.removeObject(forKey: Self.shownCountKey)
    }
}

/// Maps an elapsed interval (seconds) into a coarse bucket label for telemetry.
enum CookiePopupProtectionOptInTimeBucket {
    static func bucket(for elapsed: TimeInterval) -> String {
        switch elapsed {
        case ..<60: return "0-1min"
        case ..<(5 * 60): return "1-5min"
        case ..<(60 * 60): return "5-60min"
        case ..<(24 * 60 * 60): return "1h-1d"
        default: return "1d+"
        }
    }
}

/// Presents the Cookie Pop-up Protection opt-in dialog through the promo queue.
/// Shown only while the Cookie Pop-up Protection setting feature flag is on, at most `maxShowCount` times,
/// only ≥ `minDaysSinceInstall` days after install; confirming permanently dismisses the promo (via `.actioned`),
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

        // Feature state when shown — unchanged until the user confirms, so reuse it for the confirmation pixel too.
        let autoconsentEnabled = browserTabViewController.cookiePopupProtectionPreferences.isAutoconsentEnabled

        // Skip telemetry + counting for force-shows (promo debug menu).
        if !force {
            let isFirstShow = store.shownCount == 0
            if isFirstShow {
                store.firstShownDate = Date()
            }
            store.shownCount += 1
            PixelKit.fire(isFirstShow ? CookiePopupProtectionOptInPixel.shownFirst(autoconsentEnabled: autoconsentEnabled)
                                      : .shownRepeat(autoconsentEnabled: autoconsentEnabled),
                          frequency: .standard)
        }

        return await withCheckedContinuation { continuation in
            showContinuation = continuation
            browserTabViewController.showCookiePopupProtectionOptInDialog(onConfirm: { [weak self] preference in
                if !force {
                    PixelKit.fire(CookiePopupProtectionOptInPixel.optionConfirmed(preference: preference,
                                                                                  autoconsentEnabled: autoconsentEnabled,
                                                                                  timeSinceShown: self?.store.bucketedTimeSinceFirstShown()),
                                  frequency: .standard)
                }
                self?.resume(with: .actioned)
            })
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
