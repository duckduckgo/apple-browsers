//
//  BrokerBundleVerifier.swift
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
import CryptoKit
import os.log
import PrivacyConfig

public enum BrokerBundleVerificationError: String, Error, CaseIterable {
    case keyRevoked = "key_revoked"
    case signatureMissing = "signature_missing"
    case signatureInvalid = "signature_invalid"
    case rollback
    case digestMismatch = "digest_mismatch"
    case other
}

public struct BrokerBundleSigningKey {
    public let id: String
    let publicKey: P256.Signing.PublicKey

    public init?(base64SPKI: String) {
        guard let derRepresentation = Data(base64Encoded: base64SPKI),
              let publicKey = try? P256.Signing.PublicKey(derRepresentation: derRepresentation) else {
            return nil
        }

        self.id = derRepresentation.sha256HexString
        self.publicKey = publicKey
    }
}

/// Public keys used to verify `main_config.json.sig`, as base64 SPKI DER.
public struct BrokerBundleSigningKeys {
    public let production: [String]
    public let staging: [String]

    public init(production: [String], staging: [String]) {
        self.production = production
        self.staging = staging
    }

    // These are dbp-api TEST keys and must be replaced with the real production and staging keys before shipping.
    // `macOS/scripts/update_embedded_brokers.sh` reads the production list, so keep one key per line.
    public static let builtIn = BrokerBundleSigningKeys(
        production: [
            "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAErmuPs8CapwHjt32La//bKRjV9ercvqY3jTzjWFSmdtnqI8ZrxOqMgEoKR6o0He6XZUy/oKOpW70+zur/7//+KQ==",
        ],
        staging: [
            "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEqpP7ubErpgXf5cpp1OFghScG7tJbhUhrKyzkxFdXGErtklupZcJx078xfZRmdYoxLbnaIAt3NYs9XeOr1oJESA==",
        ]
    )

    func keys(isProductionEndpoint: Bool) -> [BrokerBundleSigningKey] {
        (isProductionEndpoint ? production : staging).compactMap { base64SPKI in
            guard let key = BrokerBundleSigningKey(base64SPKI: base64SPKI) else {
                assertionFailure("Invalid broker bundle signing key: \(base64SPKI)")
                return nil
            }
            return key
        }
    }
}

/// PIR pauses while privacy-config lists any of the app's signing keys for the current environment as revoked.
///
/// This is read from the current privacy-config every time rather than stored, because privacy-config's list is
/// additive only. Once an app update drops the revoked key, PIR resumes.
public struct BrokerBundleKeyRevocationChecker {
    static let revokedKeysSettingsKey = "revokedBundleSigningKeys"

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let settings: DataBrokerProtectionSettings
    private let signingKeys: BrokerBundleSigningKeys

    public init(privacyConfigurationManager: PrivacyConfigurationManaging,
                settings: DataBrokerProtectionSettings,
                signingKeys: BrokerBundleSigningKeys = .builtIn) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.settings = settings
        self.signingKeys = signingKeys
    }

    public var isAnyKeyRevoked: Bool {
        let revokedKeyIDs = privacyConfigurationManager.privacyConfig.settings(for: .dbp)[Self.revokedKeysSettingsKey] as? [String] ?? []
        guard !revokedKeyIDs.isEmpty else { return false }

        let normalizedRevokedKeyIDs = Set(revokedKeyIDs.map { $0.lowercased() })
        return signingKeys.keys(isProductionEndpoint: settings.isProductionEndpoint).contains { normalizedRevokedKeyIDs.contains($0.id) }
    }
}

struct BrokerBundleVerifier {
    let keys: [BrokerBundleSigningKey]

    /// Returns the key that produced `signature` over the exact bytes of `manifest`.
    func verifyingKey(manifest: Data, signature: Data?) throws -> BrokerBundleSigningKey {
        guard let signature else {
            throw BrokerBundleVerificationError.signatureMissing
        }

        guard let base64Signature = String(bytes: signature, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw BrokerBundleVerificationError.signatureInvalid
        }
        guard !base64Signature.isEmpty else {
            throw BrokerBundleVerificationError.signatureMissing
        }

        guard let derSignature = Data(base64Encoded: base64Signature),
              let ecdsaSignature = try? P256.Signing.ECDSASignature(derRepresentation: derSignature),
              let key = keys.first(where: { $0.publicKey.isValidSignature(ecdsaSignature, for: manifest) }) else {
            throw BrokerBundleVerificationError.signatureInvalid
        }

        return key
    }

    static func hasExpectedDigest(_ data: Data, expectedSHA256: String?) -> Bool {
        guard let expectedSHA256 else { return false }
        return data.sha256HexString == expectedSHA256.lowercased()
    }
}

extension Data {
    var sha256HexString: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
