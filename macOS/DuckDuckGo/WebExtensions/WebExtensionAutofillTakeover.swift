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
import FeatureFlags_macOS
import PrivacyConfig
import WebExtensions

/// A kind of autofill data an extension can take over from DuckDuckGo.
enum ExtensionManagedAutofillKind: String, CaseIterable {
    case passwords
    case addresses
    case cards

    /// The `chrome.privacy.services` setting an extension turns off to take this kind over.
    @available(macOS 15.4, *)
    var privacySetting: WebExtensionPrivacySetting {
        switch self {
        case .passwords: return .passwordSavingEnabled
        case .addresses: return .autofillAddressEnabled
        case .cards: return .autofillCreditCardEnabled
        }
    }
}

/// The extension that manages a kind of autofill data instead of DuckDuckGo.
struct AutofillManagingExtension: Equatable {
    let identifier: String
    let name: String
    let icon: NSImage?

    /// The icon is left out: WebKit hands out a new image each time.
    static func == (lhs: AutofillManagingExtension, rhs: AutofillManagingExtension) -> Bool {
        lhs.identifier == rhs.identifier && lhs.name == rhs.name
    }
}

/// Which kinds of autofill data an installed extension has taken over from DuckDuckGo.
///
/// An extension takes a kind over the way it does in Chrome: it turns the browser's setting off
/// through `chrome.privacy.services`, as Bitwarden does when the user makes it the default password
/// manager. DuckDuckGo autofill then steps aside for that kind, until the extension clears the
/// setting, is uninstalled, or the user gives the kind back to DuckDuckGo in Settings.
///
/// The kinds an extension manages are saved in the autofill preferences, where every autofill
/// decision reads them, from any thread. A change posts `.autofillUserSettingsDidChange`, which
/// rebuilds the autofill scripts, so open tabs follow on their next navigation.
///
/// The kinds are read again when:
/// - extensions load or unload, or an extension changes its setting (`.webExtensionPrivacySettingsDidChange`);
/// - the `webExtensionBitwarden` flag changes;
/// - web extensions become unavailable (`extensionsDidBecomeUnavailable()`).
///
/// Handing it a new extension manager doesn't read them: its extensions haven't loaded yet, and
/// reading now would clear the saved kinds that tabs restored at launch rely on. The first read
/// comes once they've loaded.
final class WebExtensionAutofillTakeover {

    typealias ManagingExtensions = [ExtensionManagedAutofillKind: AutofillManagingExtension]

    /// The app's extension manager. The app delegate sets it when it creates one.
    @MainActor weak var manager: WebExtensionManaging?

    private var preferences: AutofillPreferencesPersistor
    private var managingExtensions: ManagingExtensions = [:]
    private let readManagingExtensions: (@MainActor () -> ManagingExtensions)?
    private let clearSetting: (@MainActor (ExtensionManagedAutofillKind) -> Void)?
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?
    private var flagCancellable: AnyCancellable?

    /// - Parameters:
    ///   - preferences: Where the managed kinds are saved for autofill to read.
    ///   - featureFlagger: Decides whether an extension may take autofill over.
    ///   - readManagingExtensions: Which loaded extension manages each kind. Reads `manager` when `nil`.
    ///   - clearSetting: Removes every extension's control of a kind. Uses `manager` when `nil`.
    init(preferences: AutofillPreferencesPersistor = AutofillPreferences(),
         featureFlagger: FeatureFlagger,
         notificationCenter: NotificationCenter = .default,
         readManagingExtensions: (@MainActor () -> ManagingExtensions)? = nil,
         clearSetting: (@MainActor (ExtensionManagedAutofillKind) -> Void)? = nil) {
        self.preferences = preferences
        self.readManagingExtensions = readManagingExtensions
        self.clearSetting = clearSetting
        self.notificationCenter = notificationCenter
        if #available(macOS 15.4, *) {
            observer = notificationCenter.addObserver(forName: .webExtensionPrivacySettingsDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeMainThread {
                    self?.refresh()
                }
            }
        }
        // Starts from the flag's current value, so only an actual change reads the kinds again.
        flagCancellable = featureFlagger.updatesPublisher
            .compactMap { [weak featureFlagger] in
                featureFlagger?.isFeatureOn(.webExtensionBitwarden)
            }
            .prepend(featureFlagger.isFeatureOn(.webExtensionBitwarden))
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

    /// The extension that manages `kind` instead of DuckDuckGo, if any.
    @MainActor
    func managingExtension(for kind: ExtensionManagedAutofillKind) -> AutofillManagingExtension? {
        managingExtensions[kind]
    }

    /// Reads again which extensions manage which kinds, and saves the kinds for autofill.
    @MainActor
    func refresh() {
        let updated = readManagingExtensions?() ?? managingExtensionsOfLoadedExtensions()
        let kinds = Set(updated.keys)
        guard updated != managingExtensions || kinds != preferences.kindsManagedByExtension else { return }

        managingExtensions = updated
        preferences.kindsManagedByExtension = kinds
        notificationCenter.post(name: .autofillUserSettingsDidChange, object: nil)
    }

    /// Web extensions are off: no extension manages anything, so DuckDuckGo autofill takes every kind back.
    @MainActor
    func extensionsDidBecomeUnavailable() {
        manager = nil
        refresh()
    }

    /// Gives `kind` back to DuckDuckGo: no extension controls the setting any more, not even one that
    /// set it before the one managing it now. The extensions see that they aren't in control, as in Chrome.
    @MainActor
    func giveBackToDuckDuckGo(_ kind: ExtensionManagedAutofillKind) {
        if let clearSetting {
            clearSetting(kind)
        } else {
            clearSettingForEveryExtension(kind)
        }
    }

    // MARK: - Extension Manager

    @MainActor
    private func managingExtensionsOfLoadedExtensions() -> ManagingExtensions {
        guard #available(macOS 15.4, *),
              let manager = manager as? WebExtensionManager,
              let store = manager.privacySettings else { return [:] }

        var result: ManagingExtensions = [:]
        for kind in ExtensionManagedAutofillKind.allCases {
            guard let identifier = store.identifierTurningOff(kind.privacySetting),
                  let context = manager.context(for: identifier) else { continue }
            result[kind] = AutofillManagingExtension(identifier: identifier,
                                                     name: context.webExtension.displayName ?? identifier,
                                                     icon: context.webExtension.icon(for: NSSize(width: 32, height: 32)))
        }
        return result
    }

    @MainActor
    private func clearSettingForEveryExtension(_ kind: ExtensionManagedAutofillKind) {
        guard #available(macOS 15.4, *),
              let store = (manager as? WebExtensionManager)?.privacySettings else { return }
        store.clearAll(kind.privacySetting)
    }
}
