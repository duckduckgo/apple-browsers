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

public enum BrokerBundleVerificationError: String, Error, CaseIterable {
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
public struct BrokerBundleSigningKeys: Decodable, Equatable {
    public let production: [String]
    public let staging: [String]

    public init(production: [String], staging: [String]) {
        self.production = production
        self.staging = staging
    }

    /// Must match dbp-api's `dbp-json/bundle-signing-keys.json`. `macOS/scripts/update_embedded_brokers.sh` reads the same file.
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
