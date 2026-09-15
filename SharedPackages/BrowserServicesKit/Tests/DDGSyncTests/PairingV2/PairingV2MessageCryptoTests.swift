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

    func testWhenParsingProtocolVersionThenNormalizesZeroMinorAndPreservesFutureMinor() {
        XCTAssertEqual(PairingV2ProtocolVersion(rawValue: "2"), .v2)
        XCTAssertEqual(PairingV2ProtocolVersion(rawValue: "2.0"), .v2)
        XCTAssertEqual(PairingV2ProtocolVersion(rawValue: "2.1"), .v2Point1)
        XCTAssertEqual(PairingV2ProtocolVersion.v2.rawValue, "2")
        XCTAssertEqual(PairingV2ProtocolVersion.v2Point1.rawValue, "2.1")
        XCTAssertEqual(PairingV2ProtocolVersion(rawValue: "2.9")?.rawValue, "2.9")
    }

    func testWhenComparingProtocolVersionsThenComparesMinorNumerically() throws {
        let minorNine = try XCTUnwrap(PairingV2ProtocolVersion(rawValue: "2.9"))
        let minorTen = try XCTUnwrap(PairingV2ProtocolVersion(rawValue: "2.10"))

        XCTAssertLessThan(PairingV2ProtocolVersion.v2, .v2Point1)
        XCTAssertLessThan(minorNine, minorTen)
        XCTAssertEqual(PairingV2ProtocolVersion.v2Point1.negotiated(with: "2.10"), .v2Point1)
    }

    func testWhenCapabilityCannotBeParsedThenNegotiationFallsBackToV2() {
        for rawValue in ["", "invalid", "1", "3.4", "2.invalid", "2.-1", "2.", "2.1.0"] {
            XCTAssertNil(PairingV2ProtocolVersion(rawValue: rawValue), rawValue)
            XCTAssertEqual(PairingV2ProtocolVersion.v2Point1.negotiated(with: rawValue), .v2, rawValue)
        }
    }

    func testWhenEncryptingExistingMessageTypesThenEnvelopeRemainsV2IncludingV21Hello() throws {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair(channelID: "channel-1")
        let crypto = PairingV2MessageCrypto()
        let messages: [PairingV2ApplicationMessage] = [
            .hello(.init(channelId: "channel-2", publicKey: "public-key", version: "2.1")),
            .recoveryCodeAvailable(.init(type: "recovery_code_available", kind: .ddg, userId: "user-1")),
            .recoveryCodeRequest(.init(type: "recovery_code_request", kind: .ddg)),
            .recoveryCodeAwaitingConfirmation(.init(type: "recovery_code_awaiting_confirmation")),
            .recoveryCodeConfirmed(.init(type: "recovery_code_confirmed")),
            .recoveryCodeDenied(.init(type: "recovery_code_denied")),
            .recoveryCodeUnavailable(.init(type: "recovery_code_unavailable")),
            .recoveryCodeResponse(.init(recoveryCode: "recovery-code"))
        ]

        for message in messages {
            let encrypted = try crypto.encrypt(message, recipientPublicKey: keyPair.publicKey, senderChannelID: "sender-channel")

            XCTAssertEqual(message.minimumProtocolVersion, .v2, message.type)
            XCTAssertEqual(encrypted.version, "2", message.type)
            XCTAssertEqual(try crypto.decrypt(encrypted, privateKey: keyPair.privateKey), message)
        }
    }

    func testWhenEncryptingRecoveryCodeDoneThenUsesV21EnvelopeAndRoundTrips() throws {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair(channelID: "channel-1")
        let crypto = PairingV2MessageCrypto()
        let message = PairingV2ApplicationMessage.recoveryCodeDone(.init(reason: .success))

        let encrypted = try crypto.encrypt(message, recipientPublicKey: keyPair.publicKey, senderChannelID: "sender-channel")

        XCTAssertEqual(message.minimumProtocolVersion, .v2Point1)
        XCTAssertEqual(encrypted.version, "2.1")
        XCTAssertEqual(try crypto.decrypt(encrypted, privateKey: keyPair.privateKey), message)
    }

    func testWhenDecodingRecoveryCodeDoneThenPreservesKnownAndUnknownReasons() throws {
        let testCases: [(rawValue: String, reason: PairingV2RecoveryCodeDoneReason)] = [
            ("success", .success),
            ("login_failed", .loginFailed),
            ("scope_rejected", .scopeRejected),
            ("future_reason", .unknown("future_reason"))
        ]

        for testCase in testCases {
            let message = try decodeApplicationMessage(
                #"{"type":"recovery_code_done","reason":"\#(testCase.rawValue)"}"#,
                envelopeVersion: "2.1"
            )

            XCTAssertEqual(message, .recoveryCodeDone(.init(reason: testCase.reason)))
        }
    }

    func testWhenDecryptingUnknownMessageInFutureMinorEnvelopeThenDropsIt() throws {
        let message = try decodeApplicationMessage(#"{"type":"future_message"}"#, envelopeVersion: "2.9")

        XCTAssertNil(message)
    }

    func testWhenChannelSecretIsGeneratedThenReturns32Base64URLEncodedBytesWithoutPadding() throws {
        let secret = try PairingV2ChannelSecretFactory.makeSecret()

        XCTAssertEqual(secret.count, 43)
        XCTAssertEqual(Base64URL.decode(secret)?.count, 32)
        XCTAssertFalse(secret.contains("="))
    }

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

    func testWhenDecodingHelloWithMissingNullOrBlankVersionThenDefaultsToV2() throws {
        let versions: [Any?] = [nil, NSNull(), "", " \t\n"]
        for version in versions {
            var json: [String: Any] = ["type": "hello", "channel_id": "channel-1", "public_key": "public-key"]
            json["version"] = version
            let data = try JSONSerialization.data(withJSONObject: json)

            let hello = try JSONDecoder.snakeCaseKeys.decode(PairingV2HelloMessage.self, from: data)

            XCTAssertEqual(hello, .init(channelId: "channel-1", publicKey: "public-key", version: "2"))
        }
    }

    func testWhenDecodingHelloWithUnrecognizedVersionThenPreservesCapabilityForNegotiation() throws {
        for version in ["invalid", "1", "3.1", "2.invalid"] {
            let data = try JSONSerialization.data(withJSONObject: [
                "type": "hello", "channel_id": "channel-1", "public_key": "public-key", "version": version
            ])

            let hello = try JSONDecoder.snakeCaseKeys.decode(PairingV2HelloMessage.self, from: data)

            XCTAssertEqual(hello.version, version)
        }
    }

    func testWhenDecodingHelloWithInvalidShapeThenStillThrows() throws {
        let invalidMessages = [
            #"{"type":"hello","public_key":"public-key"}"#,
            #"{"type":"hello","channel_id":"channel-1"}"#,
            #"{"type":"hello","channel_id":"channel-1","public_key":"public-key","version":42}"#
        ]
        for json in invalidMessages {
            let data = Data(json.utf8)

            XCTAssertThrowsError(try JSONDecoder.snakeCaseKeys.decode(PairingV2HelloMessage.self, from: data)) { error in
                XCTAssertTrue(error is DecodingError)
            }
        }
    }

    func testWhenQRCodeVersionIsMissingMalformedOrUnsupportedThenRejectsInsteadOfFallingBack() throws {
        let versions: [Any?] = [nil, NSNull(), "", " \t\n", "invalid", "2.invalid", "2.-1", "2.", "1", "3", "3.1"]
        for version in versions {
            var json: [String: Any] = ["channel_id": "channel-1", "public_key": "public-key"]
            json["version"] = version
            let encodedPayload = Base64URL.encode(try JSONSerialization.data(withJSONObject: json))
            let url = try XCTUnwrap(URL(string: "https://duckduckgo.com/sync/pairing/#&code2=\(encodedPayload)"))

            XCTAssertNil(PairingV2QRCodePayload(url: url), String(describing: version))
        }
    }

    func testWhenEnvelopeVersionIsMissingThenDecodingStillThrows() throws {
        for json in [#"{"payload":"encrypted-message"}"#, #"{"version":null,"payload":"encrypted-message"}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(PairingV2EncryptedMessage.self, from: Data(json.utf8))) { error in
                XCTAssertTrue(error is DecodingError)
            }
        }
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

    func testWhenEnvelopeVersionIsMalformedOrUnsupportedThenThrowsInsteadOfFallingBack() throws {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair(channelID: "channel-1")
        let crypto = PairingV2MessageCrypto()
        let message = try crypto.encrypt(
            .recoveryCodeRequest(.init(type: PairingV2ApplicationMessage.MessageType.recoveryCodeRequest,
                                       kind: .ddg)),
            recipientPublicKey: keyPair.publicKey,
            senderChannelID: "sender-channel"
        )
        for version in ["", " \t\n", "invalid", "2.invalid", "2.-1", "2.", "1", "3", "3.1"] {
            let unsupportedMessage = PairingV2EncryptedMessage(version: version, payload: message.payload)

            XCTAssertThrowsError(try crypto.decrypt(unsupportedMessage, privateKey: keyPair.privateKey)) { error in
                XCTAssertEqual(error as? PairingV2MessageCryptoError, .unsupportedVersion(version))
            }
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

    private func decodeApplicationMessage(_ json: String, envelopeVersion: String = "2") throws -> PairingV2ApplicationMessage? {
        let keyPair = try PairingV2KeyPairFactory.makeKeyPair(channelID: "channel-1")
        let crypto = PairingV2MessageCrypto()
        let data = try XCTUnwrap(json.data(using: .utf8))
        // keyPair.publicKey is the base64url SPKI string; encryptRSAOAEP256 needs the SecKey,
        // which is the public half of the keypair's private key.
        let recipientPublicKey = try XCTUnwrap(SecKeyCopyPublicKey(keyPair.privateKey))
        let encryptedMessage = PairingV2EncryptedMessage(
            version: envelopeVersion,
            payload: try JWECompactCodec().encryptRSAOAEP256(payload: data,
                                                             recipientPublicKey: recipientPublicKey,
                                                             kid: "sender-channel")
        )

        return try crypto.decrypt(encryptedMessage, privateKey: keyPair.privateKey, expectedSenderChannelID: "sender-channel")
    }
}
