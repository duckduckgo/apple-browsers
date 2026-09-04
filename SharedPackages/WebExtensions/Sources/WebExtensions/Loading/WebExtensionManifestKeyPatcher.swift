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
/// The Web Store injects a `key` field into the manifest of every extension it serves, and Chrome
/// derives the extension's identifier from it (see `WKWebExtension.chromeExtensionIdentifier`). The
/// release zips vendors publish themselves are built before that step, so they carry no `key` at
/// all: there is nothing to derive an identifier from, and a native messaging host that gates
/// callers on `allowed_origins` — Bitwarden's and 1Password's both do — rejects the extension
/// outright. Putting the store's key back restores the identifier the host expects.
///
/// The extension is recognized by name, which is what a user sees and what a vendor keeps stable
/// across releases — the manifest has no other stable identity to match on precisely because the
/// `key` is what is missing.
///
/// A manifest carries more than one name, though, and which one is the vendor's plain product name
/// varies: Bitwarden's `name` is the store listing "Bitwarden Password Manager" while its
/// `short_name` is "Bitwarden", and 1Password's `name` is "1Password – Password Manager". Both
/// candidates are therefore tried in turn — a literal `name`, then `short_name` — and the first one
/// the table knows wins. That keeps the table keyed on short vendor names, which are far less
/// volatile than store listing titles.
struct WebExtensionManifestKeyPatcher {

    /// Base64-encoded DER `SubjectPublicKeyInfo` values, exactly as the Web Store writes them into
    /// `manifest.json`, keyed by the display name the extension resolves to.
    ///
    /// The value is a *public* key, published verbatim in every copy of the extension the Web Store
    /// serves, so embedding it grants nothing: it names the extension, it does not authenticate
    /// anyone. A manifest that already carries a `key` is never touched.
    static let knownPublicKeys: [String: String] = [
        // Derives to nngceckbapebfimnlniiiahkandclblb, the id Bitwarden's
        // `com.8bit.bitwarden` host manifest lists in `allowed_origins`.
        "Bitwarden": """
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAmqKbvreshyXRuN2gikeR1idqR6KL0Di89JZcMyD4bjJRZVmQO7aznSGSALIHzS\
        AUGYocUYBNDOP5QAhImxXyQ1qG8+goXs93v9GzrNJETdVuCEhqBggC4/DFabryJZDiKvZ2Jl0DM7MsWdoybZPwrj70V3aJ/nVNOMkf868sc\
        NTMliwitCqqjT5baTANsG0DkZWQExD4lSXzSZHH9MEO8q0iZ7RRlNuGRBAkZgNV8FwZRsPKm/rwQ9dy3VpgLcmLp5GiMt+kAEncqKAkuRYn\
        hVXXBsKqIyYTMjHSLkLnpfFySyOPLBdS617i/PGNiP/MT6Xy6z//v5NozUgaAZ4gJQIDAQAB
        """,
        // Derives to aeblfdkhhhdcdjpifhhbdiojplfjncoa, the id 1Password's
        // `com.1password.1password` host manifest lists in `allowed_origins`.
        "1Password": """
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAnHpaUll4uWujpAdbIXOQY2WE6hk8PllsYsnoUaj5qHXwv4IB6A9pONqGaTL2KL\
        20u6E6XVhncY6Ae6SQSBQqiIkgjPsiG0NDNsDlju/kzBnfimKFC/bpzOrqFqbhswQHifnet5uHlpG97whTzLO3ka0M5aqB9V9mD/0qVXvN\
        gAVVnSTULH254YqpeCcAhmsKiFZSL6OrOZmCp8kZ/OeOUK9iYWYylL7VcOXVrZf10EPrlaCNXzVk7K35dPuQ7svhA0Pgju3kngB4RLa5Ioj\
        hw3IT+B5+m8pisjOSd1oKMrRmhGs7rDhF5IEtAiVxqVp7uOOMPQj3vrbMDAzf7vqLtQIDAQAB
        """
    ]

    private enum ManifestKey {
        static let key = "key"
        static let name = "name"
        static let shortName = "short_name"
        static let placeholderPrefix = "__MSG_"
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

        for displayName in candidateNames(in: manifest) {
            guard let publicKey = Self.knownPublicKeys[displayName] else {
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

    /// The names this extension could be known by, most specific first: a literal `name`, then
    /// `short_name`.
    ///
    /// A `name` that is a `__MSG_…__` localization placeholder is skipped: the placeholder itself can
    /// never match a table key, and the name it stands for is the store listing title, which is not
    /// what the table is keyed on.
    private func candidateNames(in manifest: [String: Any]) -> [String] {
        var names: [String] = []

        if let name = manifest[ManifestKey.name] as? String,
           !name.isEmpty,
           !name.hasPrefix(ManifestKey.placeholderPrefix) {
            names.append(name)
        }

        if let shortName = manifest[ManifestKey.shortName] as? String, !shortName.isEmpty {
            names.append(shortName)
        }

        return names
    }
}
