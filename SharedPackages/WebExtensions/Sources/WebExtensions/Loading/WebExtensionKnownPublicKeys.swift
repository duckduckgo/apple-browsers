//
//  WebExtensionKnownPublicKeys.swift
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

/// Chrome Web Store public keys for extensions we know about, keyed by the extension's localized
/// display name.
///
/// The Web Store injects a `key` field into the manifest of every extension it serves, and Chrome
/// derives the extension's identifier from it (see `WKWebExtension.chromeExtensionIdentifier`). The
/// release zips vendors publish on GitHub are built before that step, so they carry no `key` at all:
/// there is nothing to derive an identifier from, and a native messaging host that gates callers on
/// `allowed_origins` — Bitwarden's and 1Password's both do — rejects the extension outright. Putting
/// the store's key back restores the identifier the host expects.
///
/// The value is a *public* key, published verbatim in every copy of the extension the Web Store
/// serves, so embedding it grants nothing: it names the extension, it does not authenticate anyone.
/// A manifest that already carries a `key` is never touched.
enum WebExtensionKnownPublicKeys {

    /// Base64-encoded DER `SubjectPublicKeyInfo` values, exactly as the Web Store writes them into
    /// `manifest.json`, keyed by the display name the extension resolves to.
    static let publicKeysByDisplayName: [String: String] = [
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

    /// The Web Store public key for an extension whose resolved display name is `displayName`, or
    /// `nil` when we do not know that extension.
    static func publicKey(forDisplayName displayName: String) -> String? {
        publicKeysByDisplayName[displayName]
    }
}
