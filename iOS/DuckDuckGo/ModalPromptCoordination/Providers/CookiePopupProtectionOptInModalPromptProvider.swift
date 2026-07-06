//
//  CookiePopupProtectionOptInModalPromptProvider.swift
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

import BrowserServicesKit
import Core
import Persistence
import SwiftUI
import UIKit
import WebExtensions
import PrivacyConfig

/// Persisted state for the Cookie Pop-up Protection opt-in dialog (showing conditions + debug reset).
struct CookiePopupProtectionOptInPromptStore {
    private static let shownCountKey = "com.duckduckgo.cookiePopupProtection.optIn.shownCount"
    private static let hasConfirmedKey = "com.duckduckgo.cookiePopupProtection.optIn.hasConfirmed"

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    /// How many times the dialog has been shown on launch.
    var shownCount: Int {
        get { (try? keyValueStore.object(forKey: Self.shownCountKey)) as? Int ?? 0 }
        nonmutating set { try? keyValueStore.set(newValue, forKey: Self.shownCountKey) }
    }

    /// Whether the user has confirmed the dialog (it should not be shown again afterwards).
    var hasConfirmed: Bool {
        get { (try? keyValueStore.object(forKey: Self.hasConfirmedKey)) as? Bool ?? false }
        nonmutating set { try? keyValueStore.set(newValue, forKey: Self.hasConfirmedKey) }
    }

    /// Clears all persisted opt-in dialog state (debug reset).
    func reset() {
        try? keyValueStore.set(nil, forKey: Self.shownCountKey)
        try? keyValueStore.set(nil, forKey: Self.hasConfirmedKey)
    }
}

/// Shows the Cookie Pop-up Protection opt-in dialog on app launch via the modal prompt queue.
/// Shown only while the Cookie Pop-up Protection setting feature flag is on, at most `maxShowCount` times,
/// only ≥ `minDaysSinceInstall` days after install, not while the user is already on the most-private
/// setting, and never after the user confirms.
final class CookiePopupProtectionOptInModalPromptProvider: ModalPromptProvider {

    private enum Constants {
        /// Maximum number of times the dialog may be shown.
        static let maxShowCount = 3
        /// The dialog is only shown once the install is at least this many days old.
        static let minDaysSinceInstall = 2
    }

    private let store: CookiePopupProtectionOptInPromptStore
    private let statisticsStore: StatisticsStore
    private let featureFlagger: FeatureFlagger

    init(store: CookiePopupProtectionOptInPromptStore,
         statisticsStore: StatisticsStore = StatisticsUserDefaults(),
         featureFlagger: FeatureFlagger) {
        self.store = store
        self.statisticsStore = statisticsStore
        self.featureFlagger = featureFlagger
    }

    func provideModalPrompt() -> ModalPromptConfiguration? {
        guard isEligibleToShow else { return nil }
        let store = store
        return ModalPromptConfiguration(viewController: Self.makeViewController(onOptionConfirmed: { _ in
            store.hasConfirmed = true
        }))
    }

    func didPresentModal() {
        store.shownCount += 1
    }

    /// Shown only while the Cookie Pop-up Protection setting feature flag is on, at most `maxShowCount` times,
    /// only ≥ `minDaysSinceInstall` days after install, and never after the user confirms.
    private var isEligibleToShow: Bool {
        guard featureFlagger.isFeatureOn(.cookiePopupPreferenceSetting),
              featureFlagger.isFeatureOn(.cookiePopupOptInDialog) else { return false }
        // Nothing to offer users already on the most-private setting — it already accepts no-opt-out cookies.
        guard AppUserDefaults().cookiePopupPreference != .max else { return false }
        guard !store.hasConfirmed, store.shownCount < Constants.maxShowCount else { return false }
        guard let installDate = statisticsStore.installDate else { return false }
        let daysSinceInstall = Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
        return daysSinceInstall >= Constants.minDaysSinceInstall
    }

    /// Builds the opt-in dialog hosting controller, configured to dismiss itself on Confirm.
    /// Shared with the debug menu's manual presentation.
    @MainActor
    static func makeViewController(onOptionConfirmed: ((CookiePopupPreference) -> Void)? = nil) -> UIViewController {
        let variant: CookiePopupProtectionOptInVariant = AppUserDefaults().autoconsentEnabled ? .whenEnabled : .whenDisabled
        weak var controller: UIViewController?
        let hostingController = UIHostingController(rootView: CookiePopupProtectionOptInView(variant: variant, onConfirm: { selectedOption in
            let preference = Self.applyCookiePopupProtectionOptInSelection(selectedOption)
            onOptionConfirmed?(preference)
            controller?.dismiss(animated: true)
        }))
        controller = hostingController
        // Block swipe-to-dismiss — the dialog can only be dismissed via its own controls.
        hostingController.isModalInPresentation = true
        // iPad: present as a fixed-size form sheet instead of a full-height page sheet.
        if UIDevice.current.userInterfaceIdiom == .pad {
            hostingController.modalPresentationStyle = .formSheet
            hostingController.preferredContentSize = CGSize(width: 480, height: 744)
        }
        return hostingController
    }

    /// The top option turns on Cookie Pop-up Protection with the most-private handling; the bottom keeps the current setting.
    /// Returns the resulting preference.
    @discardableResult
    static func applyCookiePopupProtectionOptInSelection(_ option: CookiePopupProtectionOptInOption) -> CookiePopupPreference {
        if option == .optIn {
            AppUserDefaults().cookiePopupPreference = .max
        }
        return AppUserDefaults().cookiePopupPreference
    }
}
