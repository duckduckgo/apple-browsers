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
import DDGError
import os.log
import PrivacyConfig

public enum BrokerBundleVerificationError: String, DDGError, CaseIterable {
    case keyRevoked = "key_revoked"
    case signatureMissing = "signature_missing"
    case signatureInvalid = "signature_invalid"
    case rollback
    case digestMismatch = "digest_mismatch"
    case other

    public static var errorDomain: String { "com.duckduckgo.databrokerprotection.BrokerBundleVerificationError" }

    public var errorCode: Int {
        switch self {
        case .keyRevoked: return 6
        case .signatureMissing: return 1
        case .signatureInvalid: return 2
        case .rollback: return 3
        case .digestMismatch: return 4
        case .other: return 5
        }
    }

    public var description: String {
        switch self {
        case .keyRevoked: return "Broker bundle signing key has been revoked"
        case .signatureMissing: return "Broker bundle signature is missing"
        case .signatureInvalid: return "Broker bundle signature is invalid"
        case .rollback: return "Broker bundle manifest version is older than the last verified version"
        case .digestMismatch: return "Broker bundle digest does not match the verified manifest"
        case .other: return "Broker bundle verification failed"
        }
    }
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
public struct BrokerBundleSigningKeys: Decodable, Equatable {
    public let production: [String]
    public let staging: [String]

    public init(production: [String], staging: [String]) {
        self.production = production
        self.staging = staging
    }

    /// Public verification keys bundled for production and staging broker updates.
    /// Must match dbp-api's `dbp-json/bundle-signing-keys.json`; the embedded-broker
    /// refresh script reads this same resource.
    /// When backend signing keys rotate, update `bundle-signing-keys.json` and the
    /// matching app-key expectations in the Swift and Bats tests together.
    public static let builtIn: BrokerBundleSigningKeys = {
        do {
            return try loadBuiltIn()
        } catch {
            Logger.dataBrokerProtection.fault("🧩 Failed to load broker bundle signing keys: \(error, privacy: .public)")
            assertionFailure("Failed to load broker bundle signing keys: \(error)")
            return BrokerBundleSigningKeys(production: [], staging: [])
        }
    }()

    static func loadBuiltIn() throws -> BrokerBundleSigningKeys {
        guard let url = Bundle.module.url(forResource: "bundle-signing-keys", withExtension: "json", subdirectory: "BundleResources") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(BrokerBundleSigningKeys.self, from: Data(contentsOf: url))
    }

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

/// PIR pauses while privacy-config lists any of the app's signing keys as revoked. This isn't stored, because the
/// list is additive only: PIR resumes once an app update drops the revoked key.
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
