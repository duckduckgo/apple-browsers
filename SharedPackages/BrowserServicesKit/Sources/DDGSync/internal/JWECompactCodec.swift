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

import CryptoKit
import Foundation
import Security

enum JWECompactCodecError: Error, Equatable {
    case invalidTokenPartCount(Int)
    case invalidDirectTokenShape
    case invalidBase64URLComponent
    case unsupportedProtectedHeader
    case invalidDirectProtectedHeaderKid
    case randomBytesGenerationFailed(OSStatus)
    case invalidContentEncryptionKeyLength(Int)
    case aesGCMEncryptionFailed
    case aesGCMDecryptionFailed
}

/// JWE compact codec for direct mode (`alg=dir`, `enc=A256GCM`):
/// - Protected header: `{"alg":"dir","enc":"A256GCM","kid":"<kid>"}`
/// - Five-part compact serialization:
///   `header..iv.ciphertext.tag`
/// - AES-256-GCM for content encryption
final class JWECompactCodec {

    static func directProtectedHeader(kid: String) -> String {
        #"{"alg":"dir","enc":"A256GCM","kid":"\#(kid)"}"#
    }

    static func encodedDirectProtectedHeader(kid: String) -> String {
        Base64URL.encode(Data(directProtectedHeader(kid: kid).utf8))
    }

    /// Encrypts using direct JWE compact mode (`alg=dir`, `enc=A256GCM`) with
    /// a `kid` in the protected header and compact shape:
    /// `header..iv.ciphertext.tag`
    func encryptDirect(payload: Data,
                       contentEncryptionKey: Data,
                       kid: String,
                       iv: Data? = nil) throws -> String {
        guard contentEncryptionKey.count == 32 else {
            throw JWECompactCodecError.invalidContentEncryptionKeyLength(contentEncryptionKey.count)
        }
        guard !kid.isEmpty else {
            throw JWECompactCodecError.invalidDirectProtectedHeaderKid
        }
        let nonceBytes = try iv ?? randomBytes(count: 12)
        let protectedHeader = Self.encodedDirectProtectedHeader(kid: kid)
        let protectedHeaderData = Data(protectedHeader.utf8)
        let ciphertextAndTag = try aesGCMEncrypt(plaintext: payload,
                                                 contentEncryptionKey: contentEncryptionKey,
                                                 iv: nonceBytes,
                                                 additionalAuthenticatedData: protectedHeaderData)

        return [
            protectedHeader,
            "",
            Base64URL.encode(nonceBytes),
            Base64URL.encode(ciphertextAndTag.ciphertext),
            Base64URL.encode(ciphertextAndTag.authenticationTag)
        ].joined(separator: ".")
    }

    /// Decrypts direct JWE compact tokens created by `encryptDirect`.
    func decryptDirect(token: String,
                       contentEncryptionKey: Data) throws -> Data {
        guard contentEncryptionKey.count == 32 else {
            throw JWECompactCodecError.invalidContentEncryptionKeyLength(contentEncryptionKey.count)
        }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5 else {
            throw JWECompactCodecError.invalidTokenPartCount(parts.count)
        }
        _ = try decodeDirectProtectedHeader(parts[0])
        guard parts[1].isEmpty else {
            throw JWECompactCodecError.invalidDirectTokenShape
        }
        guard
            let iv = Base64URL.decode(parts[2]),
            let ciphertext = Base64URL.decode(parts[3]),
            let authenticationTag = Base64URL.decode(parts[4]),
            authenticationTag.count == 16
        else {
            throw JWECompactCodecError.invalidBase64URLComponent
        }

        return try aesGCMDecrypt(ciphertext: ciphertext,
                                 authenticationTag: authenticationTag,
                                 contentEncryptionKey: contentEncryptionKey,
                                 iv: iv,
                                 additionalAuthenticatedData: Data(parts[0].utf8))
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

    private func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return errSecParam
            }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }
        guard status == errSecSuccess else {
            throw JWECompactCodecError.randomBytesGenerationFailed(status)
        }
        return data
    }

    private func aesGCMEncrypt(plaintext: Data,
                               contentEncryptionKey: Data,
                               iv: Data,
                               additionalAuthenticatedData: Data) throws -> (ciphertext: Data, authenticationTag: Data) {
        do {
            let symmetricKey = SymmetricKey(data: contentEncryptionKey)
            let nonce = try AES.GCM.Nonce(data: iv)
            let sealedBox = try AES.GCM.seal(plaintext,
                                             using: symmetricKey,
                                             nonce: nonce,
                                             authenticating: additionalAuthenticatedData)
            return (sealedBox.ciphertext, sealedBox.tag)
        } catch {
            throw JWECompactCodecError.aesGCMEncryptionFailed
        }
    }

    private func aesGCMDecrypt(ciphertext: Data,
                               authenticationTag: Data,
                               contentEncryptionKey: Data,
                               iv: Data,
                               additionalAuthenticatedData: Data) throws -> Data {
        do {
            let symmetricKey = SymmetricKey(data: contentEncryptionKey)
            let nonce = try AES.GCM.Nonce(data: iv)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: authenticationTag)
            return try AES.GCM.open(sealedBox, using: symmetricKey, authenticating: additionalAuthenticatedData)
        } catch {
            throw JWECompactCodecError.aesGCMDecryptionFailed
        }
    }

}

private struct DirectProtectedHeader: Decodable {
    let alg: String
    let enc: String
    let kid: String
}
