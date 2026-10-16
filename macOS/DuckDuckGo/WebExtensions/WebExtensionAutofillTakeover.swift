//
//  WebExtensionAutofillTakeover.swift
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
import PrivacyConfig
import WebExtensions

/// The extension that manages autofill instead of DuckDuckGo.
struct AutofillManagingExtension: Equatable {
    let identifier: String
    let name: String
    let icon: NSImage?

    /// The icon is left out: WebKit hands out a new image each time.
    static func == (lhs: AutofillManagingExtension, rhs: AutofillManagingExtension) -> Bool {
        lhs.identifier == rhs.identifier && lhs.name == rhs.name
    }
}

/// Whether a password manager extension has taken autofill over from DuckDuckGo.
///
/// An extension becomes the password manager the way it does in Chrome: it turns the browser's password
/// saving off through `chrome.privacy.services`, as Bitwarden does when the user makes it the default
/// password manager. DuckDuckGo's built-in password manager then steps aside entirely, for passwords,
/// addresses and cards, until the extension turns password saving back on, is uninstalled, or the user
/// gives autofill back to DuckDuckGo in Settings.
///
/// Whether an extension manages autofill is saved in the autofill preferences, where every autofill
/// decision reads it, from any thread. A change posts `.autofillUserSettingsDidChange`, which rebuilds the
/// autofill scripts, so open tabs follow on their next navigation.
///
/// It is read again when:
/// - extensions load or unload, or an extension changes its setting (`.webExtensionPrivacySettingsDidChange`);
/// - Bitwarden's catalog entry (`extensionsCatalog.bitwarden`) is turned on or off remotely;
/// - web extensions become unavailable (`extensionsDidBecomeUnavailable()`).
///
/// Handing it a new extension manager doesn't read it: its extensions haven't loaded yet, and reading
/// now would clear the saved state that tabs restored at launch rely on. The first read comes once
/// they've loaded.
final class WebExtensionAutofillTakeover {

    /// The app's extension manager. The app delegate sets it when it creates one.
    @MainActor weak var manager: WebExtensionManaging?

    /// The extension that manages autofill instead of DuckDuckGo, if any.
    @MainActor private(set) var managingExtension: AutofillManagingExtension?

    private var preferences: AutofillPreferencesPersistor
    private let readManagingExtension: (@MainActor () -> AutofillManagingExtension?)?
    private let clearSettings: (@MainActor () -> Void)?
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?
    private var flagCancellable: AnyCancellable?

    /// - Parameters:
    ///   - preferences: Where whether an extension manages autofill is saved for autofill to read.
    ///   - privacyConfigurationManager: Its Bitwarden catalog entry decides whether an extension may take autofill over.
    ///   - readManagingExtension: Which loaded extension manages autofill. Reads `manager` when `nil`.
    ///   - clearSettings: Removes every extension's control of the privacy settings. Uses `manager` when `nil`.
    init(preferences: AutofillPreferencesPersistor = AutofillPreferences(),
         privacyConfigurationManager: PrivacyConfigurationManaging,
         notificationCenter: NotificationCenter = .default,
         readManagingExtension: (@MainActor () -> AutofillManagingExtension?)? = nil,
         clearSettings: (@MainActor () -> Void)? = nil) {
        self.preferences = preferences
        self.readManagingExtension = readManagingExtension
        self.clearSettings = clearSettings
        self.notificationCenter = notificationCenter
        if #available(macOS 15.4, *) {
            observer = notificationCenter.addObserver(forName: .webExtensionPrivacySettingsDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeMainThread {
                    self?.refresh()
                }
            }
        }
        // Starts from the entry's current state, so only an actual change reads the takeover again.
        flagCancellable = privacyConfigurationManager.updatesPublisher
            .map { [privacyConfigurationManager] in
                privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(ExtensionsCatalogSubfeature.bitwarden)
            }
            .prepend(privacyConfigurationManager.privacyConfig.isSubfeatureEnabled(ExtensionsCatalogSubfeature.bitwarden))
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeMainThread {
                    self?.refresh()
                }
            }
    }

    deinit {
        observer.map(notificationCenter.removeObserver)
    }

    /// Reads again which extension manages autofill, and saves whether one does for autofill.
    @MainActor
    func refresh() {
        let updated = readManagingExtension?() ?? managingExtensionOfLoadedExtensions()
        let isManaged = updated != nil
        guard updated != managingExtension || isManaged != preferences.isManagedByExtension else { return }

        managingExtension = updated
        preferences.isManagedByExtension = isManaged
        notificationCenter.post(name: .autofillUserSettingsDidChange, object: nil)
    }

    /// Web extensions are off: no extension manages autofill, so DuckDuckGo takes it back.
    @MainActor
    func extensionsDidBecomeUnavailable() {
        manager = nil
        refresh()
    }

    /// Gives autofill back to DuckDuckGo: no extension controls any privacy setting any more, not even one
    /// that set it before the one managing autofill now. The extensions see that they aren't in control,
    /// as in Chrome.
    @MainActor
    func giveBackToDuckDuckGo() {
        if let clearSettings {
            clearSettings()
        } else {
            clearSettingsForEveryExtension()
        }
    }

    // MARK: - Extension Manager

    @MainActor
    private func managingExtensionOfLoadedExtensions() -> AutofillManagingExtension? {
        guard #available(macOS 15.4, *),
              let manager = manager as? WebExtensionManager,
              let identifier = manager.privacySettings?.identifierTurningOff(.passwordSavingEnabled),
              let context = manager.context(for: identifier) else { return nil }
        return AutofillManagingExtension(identifier: identifier,
                                         name: context.webExtension.displayName ?? identifier,
                                         icon: context.webExtension.icon(for: NSSize(width: 32, height: 32)))
    }

    @MainActor
    private func clearSettingsForEveryExtension() {
        guard #available(macOS 15.4, *),
              let store = (manager as? WebExtensionManager)?.privacySettings else { return }
        WebExtensionPrivacySetting.allCases.forEach(store.clearAll)
    }
}
