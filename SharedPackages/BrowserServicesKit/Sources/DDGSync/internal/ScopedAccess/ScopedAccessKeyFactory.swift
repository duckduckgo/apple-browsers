//
//  ScopedAccessKeyFactory.swift
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
import Security

enum ScopedAccessKeyFactoryError: Error {
    case randomBytesGenerationFailed(OSStatus)
    case keyGenerationFailed
    case publicKeyExtractionFailed
    case publicKeyExportFailed
    case privateKeyExportFailed
    case invalidRSAPublicKeyDER
    case invalidWrappingKeyLength(Int)
}

enum ScopedAccessKeyFactory {

    private static let scopedPasswordLength = 32
    private static let rsaKeySizeInBits = 2048

    struct RSAKeyMaterial {
        let publicKeyJWK: ProtectedKeyPublicKey
        let privateKeyPKCS8: Data
    }

    static func makeScopedPassword() throws -> Data {
        try randomBytes(count: scopedPasswordLength)
    }

    static func makeRSAKeyMaterial() throws -> RSAKeyMaterial {
        let keyPair = try makeRSAKeyPair()
        let publicKeyPKCS1 = try copyExternalRepresentation(for: keyPair.publicKey,
                                                            error: .publicKeyExportFailed)
        let privateKeyPKCS1 = try copyExternalRepresentation(for: keyPair.privateKey,
                                                             error: .privateKeyExportFailed)

        return RSAKeyMaterial(
            publicKeyJWK: try makeRSAPublicJWK(fromPKCS1DER: publicKeyPKCS1),
            privateKeyPKCS8: RSAKeyDER.wrapRSAPrivateKeyInPKCS8(privateKeyPKCS1)
        )
    }

    /// Generates a fresh RSA-2048 KEK pair and wraps its private key using direct JWE
    /// (`alg=dir`, `enc=A256GCM`).
    ///
    /// Native `ddg` key creation encrypts keys with the account secret, not direct JWE.
    /// Keep this helper for JWE-based wrapping use cases, including 3party keys and test fixtures.
    static func makeJWEProtectedKey(wrappingKey: Data,
                                    encryptedWith: String,
                                    purpose: String) throws -> ProtectedKey {
        let keyMaterial = try makeRSAKeyMaterial()
        let encryptedPrivateKey = try encryptAsDirectJWE(keyMaterial.privateKeyPKCS8,
                                                         withWrappingKey: wrappingKey,
                                                         kid: encryptedWith)

        return ProtectedKey(kid: UUID().uuidString,
                            encryptedPrivateKey: encryptedPrivateKey,
                            publicKey: keyMaterial.publicKeyJWK,
                            encryptedWith: encryptedWith,
                            purpose: purpose)
    }

    private static func makeRSAKeyPair() throws -> RSAKeyPair {
        do {
            return try RSAKeyPairGenerator.makeKeyPair(keySizeInBits: rsaKeySizeInBits)
        } catch RSAKeyPairGeneratorError.keyGenerationFailed {
            throw ScopedAccessKeyFactoryError.keyGenerationFailed
        } catch RSAKeyPairGeneratorError.publicKeyExtractionFailed {
            throw ScopedAccessKeyFactoryError.publicKeyExtractionFailed
        } catch {
            throw error
        }
    }

    private static func copyExternalRepresentation(for key: SecKey,
                                                   error failure: ScopedAccessKeyFactoryError) throws -> Data {
        do {
            return try RSAKeyPairGenerator.copyExternalRepresentation(for: key)
        } catch RSAKeyPairGeneratorError.externalRepresentationFailed {
            throw failure
        } catch let error {
            throw error
        }
    }

    private static func encryptAsDirectJWE(_ plaintext: Data,
                                           withWrappingKey wrappingKey: Data,
                                           kid: String) throws -> String {
        guard wrappingKey.count == 32 else {
            throw ScopedAccessKeyFactoryError.invalidWrappingKeyLength(wrappingKey.count)
        }
        return try JWECompactCodec().encryptDirect(payload: plaintext,
                                                   contentEncryptionKey: wrappingKey,
                                                   kid: kid)
    }

    private static func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        guard status == errSecSuccess else {
            throw ScopedAccessKeyFactoryError.randomBytesGenerationFailed(status)
        }
        return data
    }

    private static func makeRSAPublicJWK(fromPKCS1DER der: Data) throws -> ProtectedKeyPublicKey {
        let (modulus, exponent) = try parseRSAPublicKeyComponents(fromPKCS1DER: der)
        return ProtectedKeyPublicKey(alg: "RSA-OAEP-256",
                                     e: Base64URL.encode(stripLeadingZeroByteIfPresent(exponent)),
                                     ext: true,
                                     keyOps: ["encrypt"],
                                     kty: "RSA",
                                     n: Base64URL.encode(stripLeadingZeroByteIfPresent(modulus)),
                                     use: "enc")
    }

    private static func parseRSAPublicKeyComponents(fromPKCS1DER der: Data) throws -> (modulus: Data, exponent: Data) {
        do {
            return try RSAKeyDER.parseRSAPublicKeyComponents(fromPKCS1DER: der)
        } catch RSAKeyDERError.invalidDER {
            throw ScopedAccessKeyFactoryError.invalidRSAPublicKeyDER
        } catch {
            throw error
        }
    }

    private static func stripLeadingZeroByteIfPresent(_ value: Data) -> Data {
        guard value.first == 0x00 else {
            return value
        }
        return value.dropFirst()
    }
}
