//
//  PairingV2MessageCrypto.swift
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

enum PairingV2MessageCryptoError: Error, Equatable {
    case invalidPublicKey
    case invalidPrivateKey
    case invalidTokenPartCount(Int)
    case invalidBase64URLComponent
    case unsupportedVersion(String)
    case unsupportedProtectedHeader
    case keyGenerationFailed
    case publicKeyExtractionFailed
    case publicKeyExportFailed
    case randomBytesGenerationFailed(OSStatus)
    case rsaEncryptionFailed
    case rsaDecryptionFailed
    case aesGCMEncryptionFailed
    case aesGCMDecryptionFailed
}

/// This device's pairing identity: its relay channel ID plus the RSA key pair peers use to encrypt messages to it.
struct PairingV2KeyPair {
    let channelID: String
    /// SPKI-DER public key, Base64URL-encoded, shared with the peer.
    let publicKey: String
    let privateKey: SecKey
}

enum PairingV2KeyPairFactory {

    /// RSA key size (bits) for the per-session pairing key pair (RSA-2048-OAEP-SHA256).
    private static let rsaKeySizeInBits = 2048

    static func makeKeyPair(channelID: String = UUID().uuidString) throws -> PairingV2KeyPair {
        let keyPair: RSAKeyPair
        do {
            keyPair = try RSAKeyPairGenerator.makeKeyPair(keySizeInBits: rsaKeySizeInBits)
        } catch RSAKeyPairGeneratorError.keyGenerationFailed {
            throw PairingV2MessageCryptoError.keyGenerationFailed
        } catch RSAKeyPairGeneratorError.publicKeyExtractionFailed {
            throw PairingV2MessageCryptoError.publicKeyExtractionFailed
        } catch {
            throw error
        }

        let publicKeyPKCS1: Data
        do {
            publicKeyPKCS1 = try RSAKeyPairGenerator.copyExternalRepresentation(for: keyPair.publicKey)
        } catch RSAKeyPairGeneratorError.externalRepresentationFailed {
            throw PairingV2MessageCryptoError.publicKeyExportFailed
        } catch {
            throw error
        }

        return PairingV2KeyPair(channelID: channelID,
                                publicKey: Base64URL.encode(RSAKeyDER.wrapRSAPublicKeyInSPKI(publicKeyPKCS1)),
                                privateKey: keyPair.privateKey)
    }
}

/// Encrypts/decrypts Pairing V2 application messages as RSA-OAEP-256 compact JWEs, using `kid` to carry and verify the sender channel ID.
final class PairingV2MessageCrypto {

    private let jweCompactCodec: JWECompactCodec

    init(jweCompactCodec: JWECompactCodec = JWECompactCodec()) {
        self.jweCompactCodec = jweCompactCodec
    }

    /// Encrypts a message to the recipient's public key, tagging it with the sender's channel ID as the JWE `kid`.
    func encrypt(_ message: PairingV2ApplicationMessage,
                 recipientPublicKey: String,
                 senderChannelID: String) throws -> PairingV2EncryptedMessage {
        let payload = try encode(message)
        let publicKey = try makePublicKey(fromSPKIBase64URL: recipientPublicKey)
        let compactJWE = try encrypt(payload, recipientPublicKey: publicKey, kid: senderChannelID)
        return PairingV2EncryptedMessage(payload: compactJWE)
    }

    /// Decrypts a message with this device's private key, verifying the sender channel ID when given; returns nil for unrecognized message types.
    func decrypt(_ message: PairingV2EncryptedMessage,
                 privateKey: SecKey,
                 expectedSenderChannelID: String? = nil) throws -> PairingV2ApplicationMessage? {
        try validateSupportedVersion(message.version)
        let payload = try decrypt(token: message.payload, privateKey: privateKey, expectedSenderChannelID: expectedSenderChannelID)
        return try decode(payload)
    }

    private func encode(_ message: PairingV2ApplicationMessage) throws -> Data {
        switch message {
        case .hello(let message):
            return try JSONEncoder.snakeCaseKeys.encode(message)
        case .recoveryCodeAvailable(let message),
                .recoveryCodeRequest(let message):
            return try JSONEncoder.snakeCaseKeys.encode(message)
        case .recoveryCodeAwaitingConfirmation(let message),
                .recoveryCodeConfirmed(let message):
            return try JSONEncoder.snakeCaseKeys.encode(message)
        case .recoveryCodeDenied(let message),
                .recoveryCodeUnavailable(let message):
            return try JSONEncoder.snakeCaseKeys.encode(message)
        case .recoveryCodeResponse(let message):
            return try JSONEncoder.snakeCaseKeys.encode(message)
        }
    }

    private func decode(_ payload: Data) throws -> PairingV2ApplicationMessage? {
        let type = try JSONDecoder.snakeCaseKeys.decode(MessageTypeProbe.self, from: payload).type
        switch type {
        case PairingV2HelloMessage.messageType:
            return .hello(try JSONDecoder.snakeCaseKeys.decode(PairingV2HelloMessage.self, from: payload))
        case PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable:
            return .recoveryCodeAvailable(try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeStatusMessage.self, from: payload))
        case PairingV2ApplicationMessage.MessageType.recoveryCodeRequest:
            return .recoveryCodeRequest(try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeStatusMessage.self, from: payload))
        case PairingV2ApplicationMessage.MessageType.recoveryCodeAwaitingConfirmation:
            return .recoveryCodeAwaitingConfirmation(try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeTerminalMessage.self, from: payload))
        case PairingV2ApplicationMessage.MessageType.recoveryCodeConfirmed:
            return .recoveryCodeConfirmed(try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeTerminalMessage.self, from: payload))
        case PairingV2ApplicationMessage.MessageType.recoveryCodeDenied:
            return .recoveryCodeDenied(try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeTerminalMessage.self, from: payload))
        case PairingV2ApplicationMessage.MessageType.recoveryCodeUnavailable:
            return .recoveryCodeUnavailable(try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeTerminalMessage.self, from: payload))
        case PairingV2RecoveryCodeResponseMessage.messageType:
            return .recoveryCodeResponse(try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeResponseMessage.self, from: payload))
        default:
            return nil
        }
    }

    private func encrypt(_ payload: Data, recipientPublicKey: SecKey, kid: String) throws -> String {
        do {
            return try jweCompactCodec.encryptRSAOAEP256(payload: payload,
                                                         recipientPublicKey: recipientPublicKey,
                                                         kid: kid)
        } catch let error as JWECompactCodecError {
            throw pairingError(for: error)
        }
    }

    private func decrypt(token: String, privateKey: SecKey, expectedSenderChannelID: String?) throws -> Data {
        do {
            return try jweCompactCodec.decryptRSAOAEP256(token: token,
                                                         privateKey: privateKey,
                                                         expectedKid: expectedSenderChannelID)
        } catch let error as JWECompactCodecError {
            throw pairingError(for: error)
        }
    }

    private func validateSupportedVersion(_ version: String) throws {
        guard PairingV2ProtocolVersion.supports(version) else {
            throw PairingV2MessageCryptoError.unsupportedVersion(version)
        }
    }

    private func makePublicKey(fromSPKIBase64URL publicKey: String) throws -> SecKey {
        guard let spki = Base64URL.decode(publicKey),
              let publicKeyPKCS1 = try? RSAKeyDER.unwrapRSAPublicKeySPKI(spki) else {
            throw PairingV2MessageCryptoError.invalidPublicKey
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 2048
        ]
        guard let key = SecKeyCreateWithData(publicKeyPKCS1 as CFData, attributes as CFDictionary, nil) else {
            throw PairingV2MessageCryptoError.invalidPublicKey
        }
        return key
    }

    private func pairingError(for error: JWECompactCodecError) -> PairingV2MessageCryptoError {
        switch error {
        case .invalidTokenPartCount(let count):
            return .invalidTokenPartCount(count)
        case .invalidBase64URLComponent:
            return .invalidBase64URLComponent
        case .unsupportedProtectedHeader,
                .invalidDirectTokenShape,
                .invalidDirectProtectedHeaderKid:
            return .unsupportedProtectedHeader
        case .invalidPublicKey:
            return .invalidPublicKey
        case .invalidPrivateKey:
            return .invalidPrivateKey
        case .randomBytesGenerationFailed(let status):
            return .randomBytesGenerationFailed(status)
        case .invalidContentEncryptionKeyLength:
            return .aesGCMEncryptionFailed
        case .rsaEncryptionFailed:
            return .rsaEncryptionFailed
        case .rsaDecryptionFailed:
            return .rsaDecryptionFailed
        case .aesGCMEncryptionFailed:
            return .aesGCMEncryptionFailed
        case .aesGCMDecryptionFailed:
            return .aesGCMDecryptionFailed
        }
    }

    private struct MessageTypeProbe: Decodable {
        let type: String
    }
}
