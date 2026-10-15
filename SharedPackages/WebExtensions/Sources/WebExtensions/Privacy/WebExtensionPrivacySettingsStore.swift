//
//  WebExtensionPrivacySettingsStore.swift
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

#if os(macOS)
import Foundation
import os.log
import Persistence

/// A `chrome.privacy.services` setting an extension can take control of. Turning one off is how a
/// password manager extension, such as Bitwarden, becomes the browser's password manager.
public enum WebExtensionPrivacySetting: String, CaseIterable, Codable {
    case passwordSavingEnabled
    case autofillAddressEnabled
    case autofillCreditCardEnabled
}

/// How much say an extension has over a setting, as Chrome's `ChromeSetting.get` reports it.
public enum WebExtensionPrivacyLevelOfControl: String {
    case notControllable = "not_controllable"
    case controlledByOtherExtensions = "controlled_by_other_extensions"
    case controllableByThisExtension = "controllable_by_this_extension"
    case controlledByThisExtension = "controlled_by_this_extension"
}

/// The `chrome.privacy.services` values extensions have set, and which extension controls each setting.
///
/// Like Chrome, an extension that sets a value controls the setting until it clears it, and when
/// several extensions set the same setting the most recent one controls it. Only extensions that
/// `canControl` allows count, so one that is not loaded, or that doesn't declare `privacy`, controls
/// nothing. The values are saved per installation in the key-value store; an update copies them to the
/// replacement installation and uninstalling removes them.
@available(macOS 15.4, *)
@MainActor
public final class WebExtensionPrivacySettingsStore {

    /// A value an extension set, and when, which decides who controls a setting.
    struct Override: Codable, Equatable {
        let value: Bool
        let date: Date
    }

    private static let key = "web-extension-privacy-settings"

    /// The permission an extension declares to control these settings.
    public static let permission = "privacy"

    /// Whether an installation may control settings: it is loaded and declares `privacy`.
    public var canControl: (String) -> Bool = { _ in false }

    private let keyValueStore: any ThrowingKeyValueStoring
    private let now: () -> Date

    nonisolated public init(keyValueStore: any ThrowingKeyValueStoring, now: @escaping () -> Date = Date.init) {
        self.keyValueStore = keyValueStore
        self.now = now
    }

    // MARK: - Queries

    /// The installation that controls `setting`, if any.
    public func controllingIdentifier(for setting: WebExtensionPrivacySetting) -> String? {
        controller(of: setting)?.identifier
    }

    /// The installation that turned `setting` off, which DuckDuckGo then leaves to it, if any.
    public func identifierTurningOff(_ setting: WebExtensionPrivacySetting) -> String? {
        guard let controller = controller(of: setting), !controller.override.value else { return nil }
        return controller.identifier
    }

    /// The value and level of control `identifier` sees for `setting`, as `ChromeSetting.get` answers.
    public func details(of setting: WebExtensionPrivacySetting, for identifier: String) -> (value: Bool, levelOfControl: WebExtensionPrivacyLevelOfControl) {
        guard canControl(identifier) else { return (true, .notControllable) }
        guard let controller = controller(of: setting) else { return (true, .controllableByThisExtension) }
        let level: WebExtensionPrivacyLevelOfControl = controller.identifier == identifier ? .controlledByThisExtension : .controlledByOtherExtensions
        return (controller.override.value, level)
    }

    // MARK: - Changes

    /// Records the value `identifier` set. Returns `false`, changing nothing, when it may not control settings.
    @discardableResult
    public func set(_ value: Bool, for setting: WebExtensionPrivacySetting, by identifier: String) -> Bool {
        guard canControl(identifier) else { return false }
        update { overrides in
            overrides[identifier, default: [:]][setting.rawValue] = Override(value: value, date: now())
        }
        return true
    }

    /// Removes the value `identifier` set, so the setting goes back to its default or to another extension.
    public func clear(_ setting: WebExtensionPrivacySetting, for identifier: String) {
        update { overrides in
            overrides[identifier]?[setting.rawValue] = nil
            if overrides[identifier]?.isEmpty == true {
                overrides[identifier] = nil
            }
        }
    }

    /// Copies the values of an installation to the installation that replaces it in an update.
    public func copySettingsForUpdate(from oldIdentifier: String, to newIdentifier: String) {
        update { overrides in
            guard let old = overrides[oldIdentifier] else { return }
            overrides[newIdentifier] = old
        }
    }

    /// Removes the values of an installation.
    public func removeSettings(for identifier: String) {
        update { overrides in
            overrides[identifier] = nil
        }
    }

    /// Tells observers that who controls the settings may have changed, for example because an
    /// extension was loaded or unloaded.
    nonisolated public func notifyControlMayHaveChanged() {
        NotificationCenter.default.post(name: .webExtensionPrivacySettingsDidChange, object: self)
    }

    // MARK: - Storage

    private func controller(of setting: WebExtensionPrivacySetting) -> (identifier: String, override: Override)? {
        loadOverrides()
            .compactMap { identifier, settings -> (String, Override)? in
                guard let override = settings[setting.rawValue], canControl(identifier) else { return nil }
                return (identifier, override)
            }
            // The latest wins; the identifier breaks a tie so the answer doesn't depend on dictionary order.
            .max { ($0.1.date, $0.0) < ($1.1.date, $1.0) }
            .map { (identifier: $0.0, override: $0.1) }
    }

    /// The overrides by installation, then by setting name.
    private func loadOverrides() -> [String: [String: Override]] {
        do {
            guard let data = try keyValueStore.object(forKey: Self.key) as? Data else { return [:] }
            return try JSONDecoder().decode([String: [String: Override]].self, from: data)
        } catch {
            Logger.webExtensions.error("Could not read extension privacy settings: \(error.localizedDescription)")
            return [:]
        }
    }

    private func update(_ mutate: (inout [String: [String: Override]]) -> Void) {
        var overrides = loadOverrides()
        let original = overrides
        mutate(&overrides)
        guard overrides != original else { return }

        do {
            if overrides.isEmpty {
                try keyValueStore.removeObject(forKey: Self.key)
            } else {
                try keyValueStore.set(JSONEncoder().encode(overrides), forKey: Self.key)
            }
        } catch {
            Logger.webExtensions.error("Could not save extension privacy settings: \(error.localizedDescription)")
        }
        notifyControlMayHaveChanged()
    }
}

public extension Notification.Name {

    /// Posted by `WebExtensionPrivacySettingsStore` when the extension controlling a `chrome.privacy`
    /// setting may have changed.
    static let webExtensionPrivacySettingsDidChange = Notification.Name("webExtensionPrivacySettingsDidChange")
}
#endif
