//
//  WebExtensionManifestKeyPatcher.swift
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

import Foundation
import os.log

/// Restores the Chrome Web Store `key` of a known extension installed from a source that does not
/// carry one, so the extension keeps the Chrome identity its native messaging host expects.
///
/// See `WebExtensionKnownPublicKeys` for why the key can be missing and why embedding it is safe.
/// The extension is recognized by name, which is what a user sees and what a vendor keeps stable
/// across releases — the manifest has no other stable identity to match on precisely because the
/// `key` is what is missing.
///
/// A manifest carries more than one name, though, and which one is the vendor's plain product name
/// varies: Bitwarden's localized `name` is the store listing "Bitwarden Password Manager" while its
/// `short_name` is "Bitwarden", and 1Password's localized `name` is "1Password – Password Manager".
/// Every candidate is therefore tried in turn — the localized `name`, a literal (non-placeholder)
/// `name`, then `short_name` — and the first one the table knows wins. That keeps the table keyed on
/// short vendor names, which are far less volatile than store listing titles.
struct WebExtensionManifestKeyPatcher {

    private enum ManifestKey {
        static let key = "key"
        static let name = "name"
        static let shortName = "short_name"
        static let defaultLocale = "default_locale"
    }

    private enum Localization {
        static let directoryName = "_locales"
        static let messagesFilename = "messages.json"
        static let placeholderPrefix = "__MSG_"
        static let placeholderSuffix = "__"
        static let messageKey = "message"
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Inserts the known Web Store public key into `manifest` when it has none and its display name
    /// identifies an extension we know.
    /// - Returns: `true` when `manifest` was changed. Idempotent: a manifest that already carries a
    ///   `key`, whether its own or one we inserted earlier, is left alone.
    func insertKnownPublicKeyIfNeeded(in manifest: inout [String: Any], manifestDirectory: URL) -> Bool {
        if let existingKey = manifest[ManifestKey.key], (existingKey as? String)?.isEmpty != true {
            return false
        }

        for displayName in candidateNames(in: manifest, manifestDirectory: manifestDirectory) {
            guard let publicKey = WebExtensionKnownPublicKeys.publicKey(forDisplayName: displayName) else {
                continue
            }

            manifest[ManifestKey.key] = publicKey

            Logger.webExtensions.info("""
            🔑 Restored the Chrome Web Store key of '\(displayName)' in \(manifestDirectory.path), \
            so the extension keeps the Chrome identifier its native messaging host allows
            """)
            return true
        }

        return false
    }

    /// The names this extension could be known by, most specific first: the localized `name`, a
    /// literal `name`, then `short_name`.
    private func candidateNames(in manifest: [String: Any], manifestDirectory: URL) -> [String] {
        var names: [String] = []

        if let name = manifest[ManifestKey.name] as? String, !name.isEmpty {
            if let messageIdentifier = messageIdentifier(inPlaceholder: name) {
                if let localizedName = localizedMessage(forIdentifier: messageIdentifier,
                                                        in: manifest,
                                                        manifestDirectory: manifestDirectory) {
                    names.append(localizedName)
                }
            } else {
                names.append(name)
            }
        }

        if let shortName = manifest[ManifestKey.shortName] as? String, !shortName.isEmpty {
            names.append(shortName)
        }

        return names
    }

    /// The message identifier inside a `__MSG_extName__` placeholder, or `nil` when `value` is a
    /// literal name.
    private func messageIdentifier(inPlaceholder value: String) -> String? {
        guard value.hasPrefix(Localization.placeholderPrefix), value.hasSuffix(Localization.placeholderSuffix) else {
            return nil
        }
        let identifier = value
            .dropFirst(Localization.placeholderPrefix.count)
            .dropLast(Localization.placeholderSuffix.count)
        return identifier.isEmpty ? nil : String(identifier)
    }

    /// Looks `identifier` up in `_locales/<default_locale>/messages.json`. Chrome treats message
    /// identifiers case-insensitively, so an exact match is tried first and a case-insensitive one
    /// after it.
    private func localizedMessage(forIdentifier identifier: String,
                                  in manifest: [String: Any],
                                  manifestDirectory: URL) -> String? {
        guard let defaultLocale = manifest[ManifestKey.defaultLocale] as? String, !defaultLocale.isEmpty else {
            return nil
        }

        let messagesURL = manifestDirectory
            .appendingPathComponent(Localization.directoryName)
            .appendingPathComponent(defaultLocale)
            .appendingPathComponent(Localization.messagesFilename)

        guard let data = try? Data(contentsOf: messagesURL),
              let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let entry = messages[identifier] ?? messages.first { $0.key.caseInsensitiveCompare(identifier) == .orderedSame }?.value
        guard let message = (entry as? [String: Any])?[Localization.messageKey] as? String, !message.isEmpty else {
            return nil
        }
        return message
    }
}
