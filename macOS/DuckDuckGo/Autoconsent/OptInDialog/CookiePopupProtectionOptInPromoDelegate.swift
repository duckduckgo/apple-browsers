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
import Persistence
import PixelKit
import PrivacyConfig
import WebExtensions

/// Persisted state for the Cookie Pop-up Protection opt-in dialog (for telemetry + showing conditions + debug reset).
struct CookiePopupProtectionOptInPromptStore {
    private static let firstShownDateKey = "cookie-popup-protection.opt-in.first-shown-date"
    private static let shownCountKey = "cookie-popup-protection.opt-in.shown-count"

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    /// The date the dialog was first shown on launch (set once), for telemetry.
    var firstShownDate: Date? {
        get {
            guard let timestamp = (try? keyValueStore.object(forKey: Self.firstShownDateKey)) as? TimeInterval else { return nil }
            return Date(timeIntervalSince1970: timestamp)
        }
        nonmutating set { try? keyValueStore.set(newValue?.timeIntervalSince1970, forKey: Self.firstShownDateKey) }
    }

    /// How many times the dialog has been shown on launch.
    var shownCount: Int {
        get { (try? keyValueStore.object(forKey: Self.shownCountKey)) as? Int ?? 0 }
        nonmutating set { try? keyValueStore.set(newValue, forKey: Self.shownCountKey) }
    }

    /// Bucketed time elapsed from the first-shown date to `now`, for telemetry.
    func bucketedTimeSinceFirstShown(now: Date = Date()) -> String? {
        guard let firstShownDate else { return nil }
        return CookiePopupProtectionOptInTimeBucket.bucket(for: now.timeIntervalSince(firstShownDate))
    }

    /// Clears all persisted opt-in dialog state (debug reset).
    func reset() {
        try? keyValueStore.removeObject(forKey: Self.shownCountKey)
        try? keyValueStore.removeObject(forKey: Self.firstShownDateKey)
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
/// only ≥ `minDaysSinceInstall` days after install, and not while the user is already on the max
/// (Reject, Hide, or Accept) setting; confirming permanently dismisses the promo (via `.actioned`),
/// so it isn't shown again afterwards.
final class CookiePopupProtectionOptInPromoDelegate: InternalPromoDelegate {

    /// Maximum number of times the dialog may be shown.
    private static let maxShowCount = 3
    /// The dialog is only shown once the install is at least this many days old.
    private static let minDaysSinceInstall = 2

    private let featureFlagger: FeatureFlagger
    private let cookiePopupProtectionPreferences: CookiePopupProtectionPreferences
    private let windowControllersManager: WindowControllersManagerProtocol
    private let store: CookiePopupProtectionOptInPromptStore

    private var showContinuation: CheckedContinuation<PromoResult, Never>?
    private var hostingWindowCloseObserver: NSObjectProtocol?
    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(false)

    init(featureFlagger: FeatureFlagger,
         cookiePopupProtectionPreferences: CookiePopupProtectionPreferences,
         windowControllersManager: WindowControllersManagerProtocol,
         store: CookiePopupProtectionOptInPromptStore) {
        self.featureFlagger = featureFlagger
        self.cookiePopupProtectionPreferences = cookiePopupProtectionPreferences
        self.windowControllersManager = windowControllersManager
        self.store = store
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
        guard featureFlagger.isFeatureOn(.cookiePopupPreferenceSetting),
              featureFlagger.isFeatureOn(.cookiePopupOptInDialog) else { return false }
        // Nothing to offer users already on the most-private setting — it already accepts no-opt-out cookies.
        guard cookiePopupProtectionPreferences.cookiePopupPreference != .max else { return false }
        guard store.shownCount < Self.maxShowCount else { return false }
        guard let installDate = LocalStatisticsStore().installDate else { return false }
        let daysSinceInstall = Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
        return daysSinceInstall >= Self.minDaysSinceInstall
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        guard let browserTabViewController = windowControllersManager
            .lastKeyMainWindowController?.mainViewController.browserTabViewController else {
            return .noChange
        }

        // A/B experiment: this is the last point both arms share before diverging, so enroll here.
        // `resolveCohort` assigns + enrolls the user; `control` is held back (dialog suppressed), while
        // `treatment`/unassigned fall through to the current presentation. Skipped for debug force-shows.
        if !force,
           featureFlagger.resolveCohort(for: FeatureFlag.cookiePopupOptInDialogExperiment) as? FeatureFlag.CookiePopupOptInDialogCohort == .control {
            return .noChange
        }

        // Feature state when shown — unchanged until the user confirms, so reuse it for the confirmation pixel too.
        let autoconsentEnabled = browserTabViewController.cookiePopupProtectionPreferences.isAutoconsentEnabled

        return await withCheckedContinuation { continuation in
            showContinuation = continuation
            let presented = browserTabViewController.showCookiePopupProtectionOptInDialog(onConfirm: { [weak self] preference in
                if !force {
                    PixelKit.fire(CookiePopupProtectionOptInPixel.optionConfirmed(preference: preference,
                                                                                  autoconsentEnabled: autoconsentEnabled,
                                                                                  timeSinceShown: self?.store.bucketedTimeSinceFirstShown()),
                                  frequency: .standard)
                }
                self?.resume(with: .actioned)
            })
            // The dialog couldn't be presented (no window, or one is already up): finish the session
            // immediately instead of leaving the promo hanging on an unresolved continuation.
            guard presented else {
                resume(with: .noChange)
                return
            }
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
            // If the hosting window closes (cmd+W or the File menu) while the dialog is up, neither
            // onConfirm nor hide() fires — resume here so the promo queue isn't blocked until the next launch.
            observeHostingWindowClose(browserTabViewController.view.window)
        }
    }

    @MainActor
    func hide() {
        windowControllersManager
            .lastKeyMainWindowController?.mainViewController.browserTabViewController
            .dismissCookiePopupProtectionOptInDialog()
        resume(with: .noChange)
    }

    private func observeHostingWindowClose(_ window: NSWindow?) {
        guard let window else { return }
        hostingWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            self?.resume(with: .noChange)
        }
    }

    private func resume(with result: PromoResult) {
        if let hostingWindowCloseObserver {
            NotificationCenter.default.removeObserver(hostingWindowCloseObserver)
            self.hostingWindowCloseObserver = nil
        }
        showContinuation?.resume(returning: result)
        showContinuation = nil
    }
}
