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
/// decision reads them, from any thread. Being saved, they also apply to tabs restored at launch,
/// before extensions finish loading. A change posts `.autofillUserSettingsDidChange`, which
/// rebuilds the autofill scripts, so open tabs follow on their next navigation.
///
/// The app delegate owns the one instance, and refreshes it when extensions load or unload, when the
/// extension manager goes away, and when the Bitwarden flag changes.
final class WebExtensionAutofillTakeover {

    typealias ManagingExtensions = [ExtensionManagedAutofillKind: AutofillManagingExtension]

    private var preferences: AutofillPreferencesPersistor
    private var managingExtensions: ManagingExtensions = [:]
    private let readManagingExtensions: @MainActor () -> ManagingExtensions
    private let clearSetting: @MainActor (ExtensionManagedAutofillKind) -> Void
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?

    /// - Parameters:
    ///   - preferences: Where the managed kinds are saved for autofill to read.
    ///   - readManagingExtensions: Which loaded extension manages each kind. Reads the app's extension
    ///     manager by default.
    ///   - clearSetting: Removes every extension's control of a kind. Uses the app's extension manager
    ///     by default.
    init(preferences: AutofillPreferencesPersistor = AutofillPreferences(),
         readManagingExtensions: @escaping @MainActor () -> ManagingExtensions = WebExtensionAutofillTakeover.managingExtensionsOfLoadedExtensions,
         clearSetting: @escaping @MainActor (ExtensionManagedAutofillKind) -> Void = WebExtensionAutofillTakeover.clearSettingForEveryExtension,
         notificationCenter: NotificationCenter = .default) {
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
        let updated = readManagingExtensions()
        let kinds = Set(updated.keys)
        guard updated != managingExtensions || kinds != preferences.kindsManagedByExtension else { return }

        managingExtensions = updated
        preferences.kindsManagedByExtension = kinds
        notificationCenter.post(name: .autofillUserSettingsDidChange, object: nil)
    }

    /// Gives `kind` back to DuckDuckGo: no extension controls the setting any more, not even one that
    /// set it before the one managing it now. The extensions see that they aren't in control, as in Chrome.
    @MainActor
    func giveBackToDuckDuckGo(_ kind: ExtensionManagedAutofillKind) {
        clearSetting(kind)
    }

    // MARK: - App Extension Manager

    @MainActor
    static func managingExtensionsOfLoadedExtensions() -> ManagingExtensions {
        guard #available(macOS 15.4, *),
              let manager = NSApp.delegateTyped.webExtensionManager as? WebExtensionManager,
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
    static func clearSettingForEveryExtension(_ kind: ExtensionManagedAutofillKind) {
        guard #available(macOS 15.4, *),
              let store = (NSApp.delegateTyped.webExtensionManager as? WebExtensionManager)?.privacySettings else { return }
        store.clearAll(kind.privacySetting)
    }
}
