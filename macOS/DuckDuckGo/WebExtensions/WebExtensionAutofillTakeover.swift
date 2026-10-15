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
enum ExtensionManagedAutofillKind: CaseIterable {
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
/// The answer is kept up to date on the main thread and can be read from any thread, because the
/// autofill user scripts are built off it. A change posts `.autofillUserSettingsDidChange`, which
/// rebuilds them, so open tabs follow on their next navigation.
final class WebExtensionAutofillTakeover {

    typealias ManagingExtensions = [ExtensionManagedAutofillKind: AutofillManagingExtension]

    static let shared = WebExtensionAutofillTakeover()

    private let lock = NSLock()
    private var managingExtensions: ManagingExtensions = [:]
    private let readManagingExtensions: @MainActor () -> ManagingExtensions
    private let clearSetting: @MainActor (ExtensionManagedAutofillKind) -> Void
    private let notificationCenter: NotificationCenter
    private var observer: NSObjectProtocol?

    /// - Parameters:
    ///   - readManagingExtensions: Which loaded extension manages each kind. Reads the app's extension
    ///     manager by default.
    ///   - clearSetting: Removes every extension's control of a kind. Uses the app's extension manager
    ///     by default.
    init(readManagingExtensions: @escaping @MainActor () -> ManagingExtensions = WebExtensionAutofillTakeover.managingExtensionsOfLoadedExtensions,
         clearSetting: @escaping @MainActor (ExtensionManagedAutofillKind) -> Void = WebExtensionAutofillTakeover.clearSettingForEveryExtension,
         notificationCenter: NotificationCenter = .default) {
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
    func managingExtension(for kind: ExtensionManagedAutofillKind) -> AutofillManagingExtension? {
        lock.withLock { managingExtensions[kind] }
    }

    /// Whether an extension manages `kind`, so DuckDuckGo autofill leaves it alone.
    func isManagedByExtension(_ kind: ExtensionManagedAutofillKind) -> Bool {
        managingExtension(for: kind) != nil
    }

    /// Reads again which extensions manage which kinds.
    @MainActor
    func refresh() {
        let updated = readManagingExtensions()
        let hasChanged = lock.withLock {
            guard managingExtensions != updated else { return false }
            managingExtensions = updated
            return true
        }
        if hasChanged {
            notificationCenter.post(name: .autofillUserSettingsDidChange, object: nil)
        }
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
