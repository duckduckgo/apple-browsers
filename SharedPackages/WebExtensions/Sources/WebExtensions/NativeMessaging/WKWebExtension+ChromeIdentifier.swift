//
//  WKWebExtension+ChromeIdentifier.swift
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

import CryptoKit
import Foundation
import WebKit

private let keyKey = "key"

/// The scheme Chrome gives extension origins.
private let chromeExtensionScheme = "chrome-extension"

/// Chrome maps each hex digit of the identifier hash into this alphabet.
private let chromeIdentifierAlphabetStart = UInt8(ascii: "a")

/// The number of hash bytes Chrome uses. Each byte yields two identifier characters, so the
/// identifier is 32 characters long.
private let chromeIdentifierHashByteCount = 16

@available(macOS 15.4, iOS 18.4, *)
public extension WKWebExtension {

    /// The identifier Chrome would give this extension, derived from the manifest `key` field.
    ///
    /// WebKit gives every extension a fresh `webkit-extension://<uuid>/` base URL, which no
    /// native messaging host recognizes. A host manifest instead lists the extensions it
    /// trusts as Chrome origins in `allowed_origins`, and a host such as 1Password's
    /// `1Password-BrowserSupport` refuses any caller it cannot find there. So to talk to such
    /// a host we have to present the same identifier Chrome would.
    ///
    /// Chrome derives it from the manifest `key`, which is the extension's public key: the
    /// value is base64-encoded DER (a `SubjectPublicKeyInfo`), and the identifier is the first
    /// 16 bytes of its SHA-256 digest, written in hex, with the digits `0`-`9a`-`f` mapped onto
    /// the letters `a`-`p`.
    ///
    /// Returns `nil` when the manifest has no `key`, or when the value is not valid base64.
    /// Unpacked extensions and our own bundled ones have no `key`, and neither has a Chrome
    /// identity to claim.
    var chromeExtensionIdentifier: String? {
        guard let key = manifest[keyKey] as? String,
              let publicKey = Data(base64Encoded: key),
              !publicKey.isEmpty else {
            return nil
        }

        let digest = SHA256.hash(data: publicKey)
        var identifier = ""
        identifier.reserveCapacity(chromeIdentifierHashByteCount * 2)

        for byte in digest.prefix(chromeIdentifierHashByteCount) {
            identifier.append(Character(UnicodeScalar(chromeIdentifierAlphabetStart + (byte >> 4))))
            identifier.append(Character(UnicodeScalar(chromeIdentifierAlphabetStart + (byte & 0x0F))))
        }
        return identifier
    }

    /// The origin Chrome passes to a native messaging host as the host process's first argument.
    ///
    /// Hosts match it against the `allowed_origins` list of their manifest, so this is the
    /// value we have to hand them in place of our own `webkit-extension://` base URL. The
    /// trailing slash is part of the origin as Chrome writes it, and as host manifests list it.
    ///
    /// Returns `nil` when the extension has no derivable ``chromeExtensionIdentifier``.
    var chromeExtensionOrigin: String? {
        guard let chromeExtensionIdentifier else { return nil }
        return "\(chromeExtensionScheme)://\(chromeExtensionIdentifier)/"
    }
}

@available(macOS 15.4, iOS 18.4, *)
public extension WKWebExtensionContext {

    /// Convenience proxy to the underlying web extension's Chrome identifier.
    var chromeExtensionIdentifier: String? {
        webExtension.chromeExtensionIdentifier
    }

    /// Convenience proxy to the underlying web extension's Chrome origin.
    var chromeExtensionOrigin: String? {
        webExtension.chromeExtensionOrigin
    }
}
