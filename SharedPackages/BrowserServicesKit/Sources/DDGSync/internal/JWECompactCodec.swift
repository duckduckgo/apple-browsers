//
//  JWECompactCodec.swift
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

enum JWECompactCodecError: Error, Equatable {
    case invalidTokenPartCount(Int)
    case invalidDirectTokenShape
    case invalidBase64URLComponent
    case unsupportedProtectedHeader
    case invalidDirectProtectedHeaderKid
    case invalidPublicKey
    case invalidPrivateKey
    case randomBytesGenerationFailed(OSStatus)
    case invalidContentEncryptionKeyLength(Int)
    case rsaEncryptionFailed
    case rsaDecryptionFailed
    case aesGCMEncryptionFailed
    case aesGCMDecryptionFailed
}

/// JWE compact codec for A256GCM content encryption.
///
/// Supports direct mode (`alg=dir`) and RSA-OAEP-256 key wrapping while sharing
/// compact serialization and AES-GCM handling.
final class JWECompactCodec {

    private static let contentEncryptionKeyLength = 32
    private static let ivLength = 12
    private static let authenticationTagLength = 16

    static func directProtectedHeader(kid: String) -> String {
        #"{"alg":"dir","enc":"A256GCM","kid":"\#(kid)"}"#
    }

    static func encodedDirectProtectedHeader(kid: String) -> String {
        Base64URL.encode(Data(directProtectedHeader(kid: kid).utf8))
    }

    static func rsaOAEP256ProtectedHeader(kid: String) -> String {
        #"{"alg":"RSA-OAEP-256","enc":"A256GCM","kid":"\#(kid)"}"#
    }

    static func encodedRSAOAEP256ProtectedHeader(kid: String) -> String {
        Base64URL.encode(Data(rsaOAEP256ProtectedHeader(kid: kid).utf8))
    }

    /// Encrypts using direct JWE compact mode (`alg=dir`, `enc=A256GCM`) with
    /// a `kid` in the protected header and compact shape:
    /// `header..iv.ciphertext.tag`
    func encryptDirect(payload: Data,
                       contentEncryptionKey: Data,
                       kid: String,
                       iv suppliedIV: Data? = nil) throws -> String {
        guard contentEncryptionKey.count == Self.contentEncryptionKeyLength else {
            throw JWECompactCodecError.invalidContentEncryptionKeyLength(contentEncryptionKey.count)
        }
        guard !kid.isEmpty else {
            throw JWECompactCodecError.invalidDirectProtectedHeaderKid
        }
        let nonceBytes = try makeIV(suppliedIV)
        let protectedHeader = Self.encodedDirectProtectedHeader(kid: kid)
        let ciphertextAndTag = try aesGCMEncrypt(plaintext: payload,
                                                 contentEncryptionKey: contentEncryptionKey,
                                                 iv: nonceBytes,
                                                 additionalAuthenticatedData: Data(protectedHeader.utf8))

        return compactToken(protectedHeader: protectedHeader,
                            encryptedContentEncryptionKey: Data(),
                            iv: nonceBytes,
                            ciphertext: ciphertextAndTag.ciphertext,
                            authenticationTag: ciphertextAndTag.authenticationTag)
    }

    /// Decrypts direct JWE compact tokens created by `encryptDirect`.
    func decryptDirect(token: String,
                       contentEncryptionKey: Data) throws -> Data {
        guard contentEncryptionKey.count == Self.contentEncryptionKeyLength else {
            throw JWECompactCodecError.invalidContentEncryptionKeyLength(contentEncryptionKey.count)
        }
        let components = try decodeCompactToken(token)
        _ = try decodeDirectProtectedHeader(components.protectedHeader)
        guard components.encryptedContentEncryptionKey.isEmpty else {
            throw JWECompactCodecError.invalidDirectTokenShape
        }

        return try aesGCMDecrypt(ciphertext: components.ciphertext,
                                 authenticationTag: components.authenticationTag,
                                 contentEncryptionKey: contentEncryptionKey,
                                 iv: components.iv,
                                 additionalAuthenticatedData: Data(components.protectedHeader.utf8))
    }

    /// Encrypts using JWE compact mode with RSA-OAEP-256 key wrapping and A256GCM content encryption.
    func encryptRSAOAEP256(payload: Data,
                           recipientPublicKey: SecKey,
                           kid: String,
                           contentEncryptionKey suppliedContentEncryptionKey: Data? = nil,
                           iv suppliedIV: Data? = nil) throws -> String {
        let contentEncryptionKey = try makeContentEncryptionKey(suppliedContentEncryptionKey)
        guard contentEncryptionKey.count == Self.contentEncryptionKeyLength else {
            throw JWECompactCodecError.invalidContentEncryptionKeyLength(contentEncryptionKey.count)
        }
        let encryptedContentEncryptionKey = try encryptContentEncryptionKey(contentEncryptionKey, recipientPublicKey: recipientPublicKey)
        let nonceBytes = try makeIV(suppliedIV)
        let protectedHeader = Self.encodedRSAOAEP256ProtectedHeader(kid: kid)
        let ciphertextAndTag = try aesGCMEncrypt(plaintext: payload,
                                                 contentEncryptionKey: contentEncryptionKey,
                                                 iv: nonceBytes,
                                                 additionalAuthenticatedData: Data(protectedHeader.utf8))

        return compactToken(protectedHeader: protectedHeader,
                            encryptedContentEncryptionKey: encryptedContentEncryptionKey,
                            iv: nonceBytes,
                            ciphertext: ciphertextAndTag.ciphertext,
                            authenticationTag: ciphertextAndTag.authenticationTag)
    }

    /// Decrypts RSA-OAEP-256/A256GCM JWE compact tokens created by `encryptRSAOAEP256`.
    func decryptRSAOAEP256(token: String,
                           privateKey: SecKey,
                           expectedKid: String? = nil) throws -> Data {
        let components = try decodeCompactToken(token)
        let protectedHeader = try decodeRSAOAEP256ProtectedHeader(components.protectedHeader)
        if let expectedKid, protectedHeader.kid != expectedKid {
            throw JWECompactCodecError.unsupportedProtectedHeader
        }

        let contentEncryptionKey = try decryptContentEncryptionKey(components.encryptedContentEncryptionKey, privateKey: privateKey)
        return try aesGCMDecrypt(ciphertext: components.ciphertext,
                                 authenticationTag: components.authenticationTag,
                                 contentEncryptionKey: contentEncryptionKey,
                                 iv: components.iv,
                                 additionalAuthenticatedData: Data(components.protectedHeader.utf8))
    }

    private func decodeDirectProtectedHeader(_ encodedHeader: String) throws -> DirectProtectedHeader {
        guard let protectedHeaderData = Base64URL.decode(encodedHeader),
              let protectedHeader = try? JSONDecoder().decode(DirectProtectedHeader.self, from: protectedHeaderData),
              protectedHeader.alg == "dir",
              protectedHeader.enc == "A256GCM"
        else {
            throw JWECompactCodecError.unsupportedProtectedHeader
        }
        guard !protectedHeader.kid.isEmpty else {
            throw JWECompactCodecError.invalidDirectProtectedHeaderKid
        }
        return protectedHeader
    }

    private func decodeRSAOAEP256ProtectedHeader(_ encodedHeader: String) throws -> RSAOAEP256ProtectedHeader {
        guard let protectedHeaderData = Base64URL.decode(encodedHeader),
              let protectedHeader = try? JSONDecoder().decode(RSAOAEP256ProtectedHeader.self, from: protectedHeaderData),
              protectedHeader.alg == "RSA-OAEP-256",
              protectedHeader.enc == "A256GCM"
        else {
            throw JWECompactCodecError.unsupportedProtectedHeader
        }
        return protectedHeader
    }

    private func makeContentEncryptionKey(_ suppliedContentEncryptionKey: Data?) throws -> Data {
        if let suppliedContentEncryptionKey {
            return suppliedContentEncryptionKey
        }
        return try randomBytes(count: Self.contentEncryptionKeyLength)
    }

    private func makeIV(_ suppliedIV: Data?) throws -> Data {
        if let suppliedIV {
            return suppliedIV
        }
        return try randomBytes(count: Self.ivLength)
    }

    private func compactToken(protectedHeader: String,
                              encryptedContentEncryptionKey: Data,
                              iv: Data,
                              ciphertext: Data,
                              authenticationTag: Data) -> String {
        [
            protectedHeader,
            Base64URL.encode(encryptedContentEncryptionKey),
            Base64URL.encode(iv),
            Base64URL.encode(ciphertext),
            Base64URL.encode(authenticationTag)
        ].joined(separator: ".")
    }

    private func decodeCompactToken(_ token: String) throws -> CompactTokenComponents {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5 else {
            throw JWECompactCodecError.invalidTokenPartCount(parts.count)
        }

        guard let encryptedContentEncryptionKey = Base64URL.decode(parts[1]),
              let iv = Base64URL.decode(parts[2]),
              let ciphertext = Base64URL.decode(parts[3]),
              let authenticationTag = Base64URL.decode(parts[4]),
              authenticationTag.count == Self.authenticationTagLength else {
            throw JWECompactCodecError.invalidBase64URLComponent
        }

        return CompactTokenComponents(protectedHeader: parts[0],
                                      encryptedContentEncryptionKey: encryptedContentEncryptionKey,
                                      iv: iv,
                                      ciphertext: ciphertext,
                                      authenticationTag: authenticationTag)
    }

    private func encryptContentEncryptionKey(_ contentEncryptionKey: Data, recipientPublicKey: SecKey) throws -> Data {
        guard SecKeyIsAlgorithmSupported(recipientPublicKey, .encrypt, .rsaEncryptionOAEPSHA256) else {
            throw JWECompactCodecError.invalidPublicKey
        }

        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(recipientPublicKey,
                                                        .rsaEncryptionOAEPSHA256,
                                                        contentEncryptionKey as CFData,
                                                        &error) as Data? else {
            throw JWECompactCodecError.rsaEncryptionFailed
        }
        return encrypted
    }

    private func decryptContentEncryptionKey(_ encryptedContentEncryptionKey: Data, privateKey: SecKey) throws -> Data {
        guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, .rsaEncryptionOAEPSHA256) else {
            throw JWECompactCodecError.invalidPrivateKey
        }

        var error: Unmanaged<CFError>?
        guard let decrypted = SecKeyCreateDecryptedData(privateKey,
                                                        .rsaEncryptionOAEPSHA256,
                                                        encryptedContentEncryptionKey as CFData,
                                                        &error) as Data? else {
            throw JWECompactCodecError.rsaDecryptionFailed
        }
        return decrypted
    }

    private func randomBytes(count: Int) throws -> Data {
        do {
            return try JWEA256GCMCipher.randomBytes(count: count)
        } catch JWEA256GCMCipherError.randomBytesGenerationFailed(let status) {
            throw JWECompactCodecError.randomBytesGenerationFailed(status)
        } catch {
            throw error
        }
    }

    private func aesGCMEncrypt(plaintext: Data,
                               contentEncryptionKey: Data,
                               iv: Data,
                               additionalAuthenticatedData: Data) throws -> (ciphertext: Data, authenticationTag: Data) {
        do {
            return try JWEA256GCMCipher.aesGCMEncrypt(plaintext: plaintext,
                                                      contentEncryptionKey: contentEncryptionKey,
                                                      iv: iv,
                                                      additionalAuthenticatedData: additionalAuthenticatedData)
        } catch JWEA256GCMCipherError.aesGCMEncryptionFailed {
            throw JWECompactCodecError.aesGCMEncryptionFailed
        } catch {
            throw error
        }
    }

    private func aesGCMDecrypt(ciphertext: Data,
                               authenticationTag: Data,
                               contentEncryptionKey: Data,
                               iv: Data,
                               additionalAuthenticatedData: Data) throws -> Data {
        do {
            return try JWEA256GCMCipher.aesGCMDecrypt(ciphertext: ciphertext,
                                                      authenticationTag: authenticationTag,
                                                      contentEncryptionKey: contentEncryptionKey,
                                                      iv: iv,
                                                      additionalAuthenticatedData: additionalAuthenticatedData)
        } catch JWEA256GCMCipherError.aesGCMDecryptionFailed {
            throw JWECompactCodecError.aesGCMDecryptionFailed
        } catch {
            throw error
        }
    }

}

private struct DirectProtectedHeader: Decodable {
    let alg: String
    let enc: String
    let kid: String
}

private struct RSAOAEP256ProtectedHeader: Decodable {
    let alg: String
    let enc: String
    let kid: String?
}

private struct CompactTokenComponents {
    let protectedHeader: String
    let encryptedContentEncryptionKey: Data
    let iv: Data
    let ciphertext: Data
    let authenticationTag: Data
}
