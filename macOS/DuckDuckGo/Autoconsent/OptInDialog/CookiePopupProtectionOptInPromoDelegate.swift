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
import Combine
import PixelKit
import WebExtensions

/// Persisted first-shown date for the Cookie Pop-up Protection opt-in dialog (for telemetry + debug reset).
struct CookiePopupProtectionOptInPromptStore {
    private static let firstShownDateKey = "cookie-popup-protection.opt-in.first-shown-date"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var firstShownDate: Date? {
        get { userDefaults.object(forKey: Self.firstShownDateKey) as? Date }
        nonmutating set { userDefaults.set(newValue, forKey: Self.firstShownDateKey) }
    }

    /// Bucketed time elapsed from the first-shown date to `now`, for telemetry.
    func bucketedTimeSinceFirstShown(now: Date = Date()) -> String? {
        guard let firstShownDate else { return nil }
        return CookiePopupProtectionOptInTimeBucket.bucket(for: now.timeIntervalSince(firstShownDate))
    }

    /// Clears all persisted opt-in dialog state (debug reset).
    func reset() {
        userDefaults.removeObject(forKey: Self.firstShownDateKey)
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
/// ponytail: always eligible for now — real show conditions come later.
final class CookiePopupProtectionOptInPromoDelegate: InternalPromoDelegate {

    private let isEligibleSubject = CurrentValueSubject<Bool, Never>(true)
    private var showContinuation: CheckedContinuation<PromoResult, Never>?
    private let store = CookiePopupProtectionOptInPromptStore()

    var isEligible: Bool { isEligibleSubject.value }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        isEligibleSubject.removeDuplicates().eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        guard let browserTabViewController = Application.appDelegate.windowControllersManager
            .lastKeyMainWindowController?.mainViewController.browserTabViewController else {
            return .noChange
        }

        // Feature state when shown — unchanged until the user confirms, so reuse it for the confirmation pixel too.
        let autoconsentEnabled = browserTabViewController.cookiePopupProtectionPreferences.isAutoconsentEnabled

        // Skip telemetry for force-shows (promo debug menu). First launch presentation vs subsequent ones
        // (the latter is dormant while the dialog shows once per install).
        if !force {
            let isFirstShow = store.firstShownDate == nil
            if isFirstShow {
                store.firstShownDate = Date()
            }
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
