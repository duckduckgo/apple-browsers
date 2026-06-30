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

import Core
import Persistence
import SwiftUI
import UIKit
import WebExtensions

/// Persisted state for the Cookie Pop-up Protection opt-in dialog.
/// ponytail: the modal prompt queue tracks no per-prompt history, so we keep our own one-shot flag + first-shown date.
struct CookiePopupProtectionOptInPromptStore {
    private static let hasShownLaunchPromptKey = "com.duckduckgo.cookiePopupProtection.optIn.hasShownLaunchPrompt"
    private static let firstShownDateKey = "com.duckduckgo.cookiePopupProtection.optIn.firstShownDate"

    private let keyValueStore: ThrowingKeyValueStoring

    init(keyValueStore: ThrowingKeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var hasShownLaunchPrompt: Bool {
        get { (try? keyValueStore.object(forKey: Self.hasShownLaunchPromptKey)) as? Bool ?? false }
        nonmutating set { try? keyValueStore.set(newValue, forKey: Self.hasShownLaunchPromptKey) }
    }

    /// The date the dialog was first shown on launch (set once).
    var firstShownDate: Date? {
        get {
            guard let timestamp = (try? keyValueStore.object(forKey: Self.firstShownDateKey)) as? TimeInterval else { return nil }
            return Date(timeIntervalSince1970: timestamp)
        }
        nonmutating set { try? keyValueStore.set(newValue?.timeIntervalSince1970, forKey: Self.firstShownDateKey) }
    }

    /// Bucketed time elapsed from the first-shown date to `now`, for telemetry.
    func bucketedTimeSinceFirstShown(now: Date = Date()) -> String? {
        guard let firstShownDate else { return nil }
        return CookiePopupProtectionOptInTimeBucket.bucket(for: now.timeIntervalSince(firstShownDate))
    }

    /// Clears all persisted opt-in dialog state (debug reset).
    func reset() {
        try? keyValueStore.set(nil, forKey: Self.hasShownLaunchPromptKey)
        try? keyValueStore.set(nil, forKey: Self.firstShownDateKey)
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

/// Shows the Cookie Pop-up Protection opt-in dialog on app launch via the modal prompt queue.
/// ponytail: always eligible until shown once — real conditions come later.
final class CookiePopupProtectionOptInModalPromptProvider: ModalPromptProvider {

    private let store: CookiePopupProtectionOptInPromptStore

    init(store: CookiePopupProtectionOptInPromptStore) {
        self.store = store
    }

    func provideModalPrompt() -> ModalPromptConfiguration? {
        guard !store.hasShownLaunchPrompt else { return nil }
        // The feature state stays unchanged between presentation and confirmation, so capture it now.
        let autoconsentEnabledWhenShown = AppUserDefaults().autoconsentEnabled
        let store = store
        return ModalPromptConfiguration(viewController: Self.makeViewController(onOptionConfirmed: { preference in
            var parameters = [
                PixelParameters.cookiePopupPreference: preference.rawValue,
                PixelParameters.autoconsentEnabled: autoconsentEnabledWhenShown ? "true" : "false"
            ]
            if let timeSinceShown = store.bucketedTimeSinceFirstShown() {
                parameters[PixelParameters.timeSinceShown] = timeSinceShown
            }
            Pixel.fire(pixel: .cookiePopupOptInOptionConfirmed, withAdditionalParameters: parameters)
        }))
    }

    func didPresentModal() {
        let parameters = [PixelParameters.autoconsentEnabled: AppUserDefaults().autoconsentEnabled ? "true" : "false"]
        // First launch presentation vs subsequent ones (the latter is dormant while the dialog shows once per install).
        if store.hasShownLaunchPrompt {
            Pixel.fire(pixel: .cookiePopupOptInShownRepeat, withAdditionalParameters: parameters)
        } else {
            store.firstShownDate = Date()
            Pixel.fire(pixel: .cookiePopupOptInShownFirst, withAdditionalParameters: parameters)
        }
        store.hasShownLaunchPrompt = true
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
    /// Returns the resulting preference (for telemetry).
    @discardableResult
    static func applyCookiePopupProtectionOptInSelection(_ option: CookiePopupProtectionOptInOption) -> CookiePopupPreference {
        if option == .optIn {
            AppUserDefaults().cookiePopupPreference = .max
        }
        return AppUserDefaults().cookiePopupPreference
    }
}
