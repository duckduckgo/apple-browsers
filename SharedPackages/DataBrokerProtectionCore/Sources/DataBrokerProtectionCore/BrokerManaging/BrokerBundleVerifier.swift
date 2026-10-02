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
    case keyRevoked = "key_revoked"
    case signatureMissing = "signature_missing"
    case signatureInvalid = "signature_invalid"
    case rollback
    case digestMismatch = "digest_mismatch"
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

    // TODO: Replace with the real production and staging keys before shipping. These are test keys.
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

struct BrokerBundleVerifier {
    let keys: [BrokerBundleSigningKey]

    func hasRevokedKey(revokedKeyIDs: [String]) -> Bool {
        let revokedKeyIDs = Set(revokedKeyIDs.map { $0.lowercased() })
        return keys.contains { revokedKeyIDs.contains($0.id) }
    }

    /// Returns the key that produced `signature` over the exact bytes of `manifest`.
    func verifyingKey(manifest: Data, signature: Data?) throws -> BrokerBundleSigningKey {
        guard let signature else {
            throw BrokerBundleVerificationError.signatureMissing
        }

        let base64Signature = String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
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
