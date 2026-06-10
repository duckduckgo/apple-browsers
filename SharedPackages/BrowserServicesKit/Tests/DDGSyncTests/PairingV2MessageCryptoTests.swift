//
//  PairingV2MessageCryptoTests.swift
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

import XCTest

@testable import DDGSync

final class PairingV2MessageCryptoTests: XCTestCase {

    func testWhenEncryptingHelloThenEnvelopeHasExpectedShapeAndRoundTrips() throws {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair(channelID: "channel-1")
        let crypto = PairingV2MessageCrypto()
        let message = PairingV2ApplicationMessage.hello(.init(channelId: "channel-2", publicKey: "public-key"))

        let encryptedMessage = try crypto.encrypt(message,
                                                  recipientPublicKey: keyPair.publicKey,
                                                  senderChannelID: "sender-channel")
        let parts = encryptedMessage.payload.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let decryptedMessage = try crypto.decrypt(encryptedMessage, privateKey: keyPair.privateKey)

        XCTAssertEqual(encryptedMessage.version, "2")
        XCTAssertEqual(parts.count, 5)
        XCTAssertEqual(parts[0], JWECompactCodec.encodedRSAOAEP256ProtectedHeader(kid: "sender-channel"))
        XCTAssertFalse(parts[1].isEmpty)
        XCTAssertEqual(decryptedMessage, message)
    }

    func testWhenEncodingHelloThenUsesCanonicalShapeAndDefaultVersion() throws {
        let message = PairingV2HelloMessage(channelId: "channel-1", publicKey: "public-key")
        let data = try JSONEncoder.snakeCaseKeys.encode(message)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(json, [
            "type": "hello",
            "channel_id": "channel-1",
            "public_key": "public-key",
            "version": "2"
        ])
    }

    func testWhenDecodingPythonReferencePairingURLThenReturnsQRCodePayload() throws {
        let encodedPayload = Base64URL.encode(try JSONEncoder.snakeCaseKeys.encode(PairingV2QRCodePayload(version: "2",
                                                                                                           channelId: "channel-1",
                                                                                                           publicKey: "public-key")))
        let url = try XCTUnwrap(URL(string: "https://duckduckgo.com/sync/pairing/#&code2=\(encodedPayload)"))

        let payload = try XCTUnwrap(PairingV2QRCodePayload(url: url))

        XCTAssertEqual(payload.version, "2")
        XCTAssertEqual(payload.channelId, "channel-1")
        XCTAssertEqual(payload.publicKey, "public-key")
    }

    func testWhenDecodingPairingURLWithNewMinorVersionThenReturnsQRCodePayload() throws {
        let encodedPayload = Base64URL.encode(try JSONEncoder.snakeCaseKeys.encode(PairingV2QRCodePayload(version: "2.1",
                                                                                                           channelId: "channel-1",
                                                                                                           publicKey: "public-key")))
        let url = try XCTUnwrap(URL(string: "https://duckduckgo.com/sync/pairing/#&code2=\(encodedPayload)"))

        let payload = try XCTUnwrap(PairingV2QRCodePayload(url: url))

        XCTAssertEqual(payload.version, "2.1")
        XCTAssertEqual(payload.channelId, "channel-1")
        XCTAssertEqual(payload.publicKey, "public-key")
    }

    func testWhenEncodingRecoveryCodeAvailableThenUsesCanonicalShape() throws {
        let message = PairingV2RecoveryCodeStatusMessage(
            type: PairingV2ApplicationMessage.MessageType.recoveryCodeAvailable,
            name: "Device",
            kind: .ddg,
            userId: "user-1"
        )
        let data = try JSONEncoder.snakeCaseKeys.encode(message)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(json, [
            "type": "recovery_code_available",
            "name": "Device",
            "kind": "ddg",
            "user_id": "user-1"
        ])
    }

    func testWhenEncodingRecoveryCodeResponseThenUsesCanonicalShape() throws {
        let message = PairingV2RecoveryCodeResponseMessage(recoveryCode: "full-recovery-code")
        let data = try JSONEncoder.snakeCaseKeys.encode(message)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(json, [
            "type": "recovery_code_response",
            "recovery_code": "full-recovery-code"
        ])
    }

    func testWhenDecodingTypeOnlyRecoveryCodeDeniedThenSucceeds() throws {
        let data = try XCTUnwrap(#"{"type":"recovery_code_denied"}"#.data(using: .utf8))
        let message = try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeTerminalMessage.self, from: data)

        XCTAssertEqual(message, .init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeDenied))
    }

    func testWhenDecodingTypeOnlyRecoveryCodeUnavailableThenSucceeds() throws {
        let data = try XCTUnwrap(#"{"type":"recovery_code_unavailable"}"#.data(using: .utf8))
        let message = try JSONDecoder.snakeCaseKeys.decode(PairingV2RecoveryCodeTerminalMessage.self, from: data)

        XCTAssertEqual(message, .init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeUnavailable))
    }

    func testWhenDecodingPythonReferenceConfirmationStatusesThenSucceeds() throws {
        let awaitingConfirmation = try decodeApplicationMessage(#"{"type":"recovery_code_awaiting_confirmation"}"#)
        let confirmed = try decodeApplicationMessage(#"{"type":"recovery_code_confirmed"}"#)

        XCTAssertEqual(awaitingConfirmation, .recoveryCodeAwaitingConfirmation(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeAwaitingConfirmation)))
        XCTAssertEqual(confirmed, .recoveryCodeConfirmed(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeConfirmed)))
    }

    func testWhenDecryptingUnsupportedVersionThenThrowsUnsupportedVersion() throws {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair(channelID: "channel-1")
        let crypto = PairingV2MessageCrypto()
        let message = try crypto.encrypt(
            .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                                       kind: .ddg)),
            recipientPublicKey: keyPair.publicKey,
            senderChannelID: "sender-channel"
        )
        let unsupportedMessage = PairingV2EncryptedMessage(version: "3", payload: message.payload)

        XCTAssertThrowsError(try crypto.decrypt(unsupportedMessage, privateKey: keyPair.privateKey)) { error in
            XCTAssertEqual(error as? PairingV2MessageCryptoError, .unsupportedVersion("3"))
        }
    }

    func testWhenDecryptingDifferentMinorVersionThenSucceeds() throws {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair(channelID: "channel-1")
        let crypto = PairingV2MessageCrypto()
        let message = try crypto.encrypt(
            .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                                       kind: .ddg)),
            recipientPublicKey: keyPair.publicKey,
            senderChannelID: "sender-channel"
        )
        let minorVersionMessage = PairingV2EncryptedMessage(version: "2.1", payload: message.payload)

        let decryptedMessage = try crypto.decrypt(minorVersionMessage, privateKey: keyPair.privateKey)

        XCTAssertEqual(
            decryptedMessage,
            .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest, kind: .ddg))
        )
    }

    func testWhenDecryptingTokenWithWrongPartCountThenThrowsInvalidTokenPartCount() throws {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair(channelID: "channel-1")
        let crypto = PairingV2MessageCrypto()
        let message = PairingV2EncryptedMessage(payload: "a.b.c")

        XCTAssertThrowsError(try crypto.decrypt(message, privateKey: keyPair.privateKey)) { error in
            XCTAssertEqual(error as? PairingV2MessageCryptoError, .invalidTokenPartCount(3))
        }
    }

    func testWhenDecryptingTokenWithInvalidAuthenticationTagLengthThenThrowsInvalidBase64URLComponent() throws {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair(channelID: "channel-1")
        let crypto = PairingV2MessageCrypto()
        let message = try crypto.encrypt(
            .hello(.init(channelId: "channel-2", publicKey: "public-key")),
            recipientPublicKey: keyPair.publicKey,
            senderChannelID: "sender-channel"
        )
        var parts = message.payload.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        parts[4] = Base64URL.encode(Data(repeating: 0x00, count: 15))
        let invalidMessage = PairingV2EncryptedMessage(payload: parts.joined(separator: "."))

        XCTAssertThrowsError(try crypto.decrypt(invalidMessage, privateKey: keyPair.privateKey)) { error in
            XCTAssertEqual(error as? PairingV2MessageCryptoError, .invalidBase64URLComponent)
        }
    }

    func testWhenDecryptingTokenWithWrongAuthenticationTagThenThrowsAESGCMDecryptionFailed() throws {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair(channelID: "channel-1")
        let crypto = PairingV2MessageCrypto()
        let message = try crypto.encrypt(
            .hello(.init(channelId: "channel-2", publicKey: "public-key")),
            recipientPublicKey: keyPair.publicKey,
            senderChannelID: "sender-channel"
        )
        var parts = message.payload.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        parts[4] = Base64URL.encode(Data(repeating: 0x00, count: 16))
        let invalidMessage = PairingV2EncryptedMessage(payload: parts.joined(separator: "."))

        XCTAssertThrowsError(try crypto.decrypt(invalidMessage, privateKey: keyPair.privateKey)) { error in
            XCTAssertEqual(error as? PairingV2MessageCryptoError, .aesGCMDecryptionFailed)
        }
    }

    func testWhenDecryptingWithUnexpectedSenderChannelThenThrowsUnsupportedHeader() throws {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair(channelID: "channel-1")
        let crypto = PairingV2MessageCrypto()
        let message = try crypto.encrypt(
            .hello(.init(channelId: "channel-2", publicKey: "public-key")),
            recipientPublicKey: keyPair.publicKey,
            senderChannelID: "expected-sender"
        )

        XCTAssertThrowsError(try crypto.decrypt(message, privateKey: keyPair.privateKey, expectedSenderChannelID: "other-sender")) { error in
            XCTAssertEqual(error as? PairingV2MessageCryptoError, .unsupportedProtectedHeader)
        }
    }

    private func decodeApplicationMessage(_ json: String) throws -> PairingV2ApplicationMessage? {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair(channelID: "channel-1")
        let crypto = PairingV2MessageCrypto()
        let data = try XCTUnwrap(json.data(using: .utf8))
        // keyPair.publicKey is the base64url SPKI string; encryptRSAOAEP256 needs the SecKey,
        // which is the public half of the keypair's private key.
        let recipientPublicKey = try XCTUnwrap(SecKeyCopyPublicKey(keyPair.privateKey))
        let encryptedMessage = PairingV2EncryptedMessage(
            payload: try JWECompactCodec().encryptRSAOAEP256(payload: data,
                                                             recipientPublicKey: recipientPublicKey,
                                                             kid: "sender-channel")
        )

        return try crypto.decrypt(encryptedMessage, privateKey: keyPair.privateKey, expectedSenderChannelID: "sender-channel")
    }
}
