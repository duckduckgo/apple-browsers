//
//  WireGuardResponderTests.swift
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
import XCTest
@testable import DuckWireGuard

final class WireGuardResponderTests: XCTestCase {
    func testResponderMatchesIndependentWireFormatAndWaitsForConfirmationWithAndWithoutPSK() throws {
        for vector in try vectors() {
            let clock = try Clock(vector)
            let peer = try responder(vector, clock: clock)
            XCTAssertEqual(try peer.receive(bytes(vector, "initiation")), .handshakeResponse(try bytes(vector, "response")))
            XCTAssertFalse(peer.isEstablished)
            XCTAssertTrue(peer.isAwaitingConfirmation)
            XCTAssertEqual(peer.handshakeGeneration, 0)
            XCTAssertThrowsError(try peer.keepalive())
            XCTAssertEqual(try peer.receive(bytes(vector, "sent_transport")), .packet(try bytes(vector, "plaintext")))
            XCTAssertTrue(peer.isEstablished)
            XCTAssertFalse(peer.isAwaitingConfirmation)
            XCTAssertEqual(peer.handshakeGeneration, 1)
            XCTAssertEqual(try peer.encrypt(bytes(vector, "plaintext")), try bytes(vector, "received_transport"))
            XCTAssertThrowsError(try peer.receive(bytes(vector, "sent_transport")))
            XCTAssertEqual(peer.handshakeGeneration, 1)
        }
    }

    func testUnauthenticatedAndMalformedInitiationsCannotInstallResponderKeys() throws {
        let vector = try XCTUnwrap(vectors().first)
        let peer = try responder(vector, clock: Clock(vector))
        let valid = try bytes(vector, "initiation")
        for length in 0..<valid.count { XCTAssertThrowsError(try peer.receive(Data(valid.prefix(length)))) }
        XCTAssertThrowsError(try peer.receive(valid + Data([0])))
        for offset in [1, 2, 3, 8, 40, 88, 116] {
            var forged = valid
            forged[offset] ^= 1
            if offset < 116 { authenticateInitiation(&forged, recipient: peer.publicKey) }
            XCTAssertThrowsError(try peer.receive(forged), "offset \(offset)")
            XCTAssertFalse(peer.isAwaitingConfirmation)
            XCTAssertFalse(peer.isEstablished)
        }
        XCTAssertEqual(try peer.receive(valid), .handshakeResponse(try bytes(vector, "response")))
    }

    func testConfiguredPeerIdentityIsRequiredBeforeResponding() throws {
        let vector = try XCTUnwrap(vectors().first)
        let unrelated = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let peer = try WireGuardPeer(privateKey: bytes(vector, "responder_private"), peerPublicKey: unrelated)
        XCTAssertThrowsError(try peer.receive(bytes(vector, "initiation")))
        XCTAssertFalse(peer.isAwaitingConfirmation)
        XCTAssertEqual(peer.handshakeGeneration, 0)
    }

    func testWrongPSKCannotBeConfirmed() throws {
        let vector = try XCTUnwrap(vectors().last)
        let clock = try Clock(vector)
        let peer = try responder(vector, clock: clock, psk: Data(repeating: 0x66, count: 32))
        guard case .handshakeResponse(let response) = try peer.receive(bytes(vector, "initiation")) else {
            return XCTFail("Expected a response")
        }
        XCTAssertNotEqual(response, try bytes(vector, "response"))
        XCTAssertThrowsError(try peer.receive(bytes(vector, "sent_transport")))
        XCTAssertFalse(peer.isEstablished)
        XCTAssertTrue(peer.isAwaitingConfirmation)
    }

    func testTimestampReplayWatermarkSurvivesKeyResetAndFreshRekeyIsAccepted() throws {
        let vector = try XCTUnwrap(vectors().first)
        let clock = try Clock(vector)
        let peer = try responder(vector, clock: clock)
        _ = try peer.receive(bytes(vector, "initiation"))
        clock.time += 1
        XCTAssertThrowsError(try peer.receive(bytes(vector, "initiation"))) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, .replayedHandshake)
        }
        peer.reset()
        XCTAssertFalse(peer.isAwaitingConfirmation)
        XCTAssertThrowsError(try peer.receive(bytes(vector, "initiation")))
        let rekey = try XCTUnwrap(vector["rekey"] as? [String: Any])
        try clock.use(rekey)
        XCTAssertEqual(try peer.receive(bytes(rekey, "initiation")), .handshakeResponse(try bytes(rekey, "response")))
    }

    func testFloodedFreshInitiationDoesNotConsumeTimestampOrReplacePendingKeys() throws {
        let vector = try XCTUnwrap(vectors().first)
        let clock = try Clock(vector)
        let peer = try responder(vector, clock: clock)
        _ = try peer.receive(bytes(vector, "initiation"))
        let rekey = try XCTUnwrap(vector["rekey"] as? [String: Any])
        clock.time += 0.01
        try clock.use(rekey)
        XCTAssertThrowsError(try peer.receive(bytes(rekey, "initiation"))) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, .handshakeRateLimited)
        }
        clock.time += 0.02
        XCTAssertEqual(try peer.receive(bytes(rekey, "initiation")), .handshakeResponse(try bytes(rekey, "response")))
    }

    func testForgedConfirmationCannotPromoteOrConsumeReplayCounter() throws {
        let vector = try XCTUnwrap(vectors().first)
        let clock = try Clock(vector)
        let peer = try responder(vector, clock: clock)
        _ = try peer.receive(bytes(vector, "initiation"))
        var forged = try bytes(vector, "sent_transport")
        forged[forged.count - 1] ^= 1
        XCTAssertThrowsError(try peer.receive(forged))
        XCTAssertFalse(peer.isEstablished)
        XCTAssertEqual(peer.handshakeGeneration, 0)
        XCTAssertEqual(try peer.receive(bytes(vector, "sent_transport")), .packet(try bytes(vector, "plaintext")))
        XCTAssertEqual(peer.handshakeGeneration, 1)
    }

    func testAuthenticatedMalformedIPConfirmsKeysButStillDropsThePacket() throws {
        let vector = try XCTUnwrap(vectors().first)
        let peer = try responder(vector, clock: Clock(vector))
        _ = try peer.receive(bytes(vector, "initiation"))
        let receiver = try XCTUnwrap(vector["responder_index"] as? UInt32)
        let header = little(UInt32(4)) + little(receiver) + little(UInt64(0))
        let malformed = header + (try WireGuardCrypto.seal(key: bytes(vector, "sending_key"), counter: 0, plaintext: Data([7])))
        XCTAssertThrowsError(try peer.receive(malformed)) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, .invalidPacket)
        }
        XCTAssertTrue(peer.isEstablished)
        XCTAssertEqual(peer.handshakeGeneration, 1)
        XCTAssertThrowsError(try peer.receive(bytes(vector, "sent_transport")), "Its authenticated counter was already consumed")
        XCTAssertEqual(try peer.encrypt(bytes(vector, "plaintext")), try bytes(vector, "received_transport"))
    }

    func testUnconfirmedResponderKeysExpireWithoutBecomingSendable() throws {
        let vector = try XCTUnwrap(vectors().first)
        let clock = try Clock(vector)
        let peer = try responder(vector, clock: clock)
        _ = try peer.receive(bytes(vector, "initiation"))
        clock.time += 180
        XCTAssertThrowsError(try peer.receive(bytes(vector, "sent_transport")))
        XCTAssertFalse(peer.isEstablished)
        XCTAssertFalse(peer.isAwaitingConfirmation)
        XCTAssertEqual(peer.handshakeGeneration, 0)
    }

    func testResponderRekeyPreservesCurrentKeysUntilConfirmationAndPreviousReplayHistoryAfterwards() throws {
        let vector = try XCTUnwrap(vectors().first)
        let clock = try Clock(vector)
        let peer = try responder(vector, clock: clock)
        let packet = try bytes(vector, "plaintext")
        _ = try peer.receive(bytes(vector, "initiation"))
        _ = try peer.receive(bytes(vector, "sent_transport"))
        let prepared = try peer.prepare(packet)
        clock.time += 5
        let rekey = try XCTUnwrap(vector["rekey"] as? [String: Any])
        try clock.use(rekey)
        XCTAssertEqual(try peer.receive(bytes(rekey, "initiation")), .handshakeResponse(try bytes(rekey, "response")))
        XCTAssertTrue(peer.canSend(prepared), "The current keys remain sendable before key confirmation")
        XCTAssertEqual(try peer.receive(bytes(rekey, "sent_transport")), .packet(packet))
        XCTAssertFalse(peer.canSend(prepared))
        XCTAssertEqual(peer.handshakeGeneration, 2)
        XCTAssertThrowsError(try peer.receive(bytes(vector, "sent_transport")), "Previous-session replay history survives promotion")
        let oldHeader = little(UInt32(4)) + little(try XCTUnwrap(vector["responder_index"] as? UInt32)) + little(UInt64(1))
        let old = oldHeader + (try WireGuardCrypto.seal(key: bytes(vector, "sending_key"), counter: 1, plaintext: packet + Data(repeating: 0, count: 12)))
        XCTAssertEqual(try peer.receive(old), .packet(packet))
        XCTAssertEqual(try peer.encrypt(packet), try bytes(rekey, "received_transport"))
    }

    func testConfirmedResponderDoesNotStartTimeBasedRekeyAt120Seconds() throws {
        let vector = try XCTUnwrap(vectors().first)
        let clock = try Clock(vector)
        let peer = try responder(vector, clock: clock)
        _ = try peer.receive(bytes(vector, "initiation"))
        _ = try peer.receive(bytes(vector, "sent_transport"))
        clock.time += 120
        XCTAssertFalse(peer.needsRekey)
        clock.time += 60
        XCTAssertTrue(peer.needsRekey)
        XCTAssertFalse(peer.isEstablished)
    }

    func testCrossedInitiationsRejectSupersededResponsesThenRecoverWithAFreshRetry() throws {
        let vector = try XCTUnwrap(vectors().first)
        var leftIndex: UInt32 = 0x01020304
        var rightIndex: UInt32 = 0x05060708
        var time: TimeInterval = 1000
        var timestamp = try bytes(vector, "timestamp")
        var leftEphemeral = Data(repeating: 0x33, count: 32)
        var rightEphemeral = Data(repeating: 0x44, count: 32)
        let left = try WireGuardPeer(privateKey: bytes(vector, "initiator_private"), peerPublicKey: bytes(vector, "responder_public"),
                                     ephemeralPrivateKey: { leftEphemeral },
                                     senderIndex: { defer { leftIndex += 1 }; return leftIndex }, now: { time }, timestamp: { timestamp })
        let right = try WireGuardPeer(privateKey: bytes(vector, "responder_private"), peerPublicKey: bytes(vector, "initiator_public"),
                                      ephemeralPrivateKey: { rightEphemeral },
                                      senderIndex: { defer { rightIndex += 1 }; return rightIndex }, now: { time }, timestamp: { timestamp })
        let leftInit = try left.initiateHandshake(), rightInit = try right.initiateHandshake()
        guard case .handshakeResponse(let rightResponse) = try right.receive(leftInit),
              case .handshakeResponse(let leftResponse) = try left.receive(rightInit) else { return XCTFail("Expected responses") }
        XCTAssertThrowsError(try left.receive(rightResponse), "An incoming initiation supersedes our old initiator transcript")
        XCTAssertThrowsError(try right.receive(leftResponse))
        XCTAssertFalse(left.isEstablished)
        XCTAssertFalse(right.isEstablished)
        time += 5.1
        timestamp = try bytes(try XCTUnwrap(vector["rekey"] as? [String: Any]), "timestamp")
        leftEphemeral = Data(repeating: 0x66, count: 32)
        rightEphemeral = Data(repeating: 0x77, count: 32)
        let retry = try left.initiateHandshake()
        guard case .handshakeResponse(let response) = try right.receive(retry) else { return XCTFail("Expected retry response") }
        XCTAssertEqual(try left.receive(response), .handshakeComplete)
        XCTAssertEqual(try right.receive(left.keepalive()), .keepalive)
        XCTAssertTrue(left.isEstablished)
        XCTAssertTrue(right.isEstablished)
        XCTAssertThrowsError(try left.receive(response), "A duplicate response cannot reinstall keys or rewind the nonce")
        XCTAssertThrowsError(try left.receive(rightResponse))
        let packet = try bytes(vector, "plaintext")
        let encrypted = try left.encrypt(packet)
        XCTAssertEqual(encrypted[8], 1)
        XCTAssertEqual(try right.receive(encrypted), .packet(packet))
        XCTAssertEqual(try left.receive(right.encrypt(packet)), .packet(packet))
    }

    func testCookieReplyToAResponseIsCachedForTheNextAuthenticatedInitiation() throws {
        let vector = try XCTUnwrap(vectors().first)
        let clock = try Clock(vector)
        let peer = try responder(vector, clock: clock)
        let response = try bytes(vector, "response")
        _ = try peer.receive(bytes(vector, "initiation"))
        let nonce = Data(repeating: 0x88, count: 24)
        let cookie = Data(repeating: 0x99, count: 16)
        let key = WireGuardCrypto.hash(Data("cookie--".utf8) + (try bytes(vector, "initiator_public")))
        let subkey = try WireGuardCrypto.hchacha20(key: key, nonce: Data(nonce.prefix(16)))
        let shortNonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + nonce.suffix(8))
        let sealed = try ChaChaPoly.seal(cookie, using: SymmetricKey(data: subkey), nonce: shortNonce,
                                       authenticating: Data(response[60..<76]))
        let reply = little(UInt32(3)) + little(clock.index) + nonce + sealed.ciphertext + sealed.tag
        XCTAssertEqual(try peer.receive(reply), .cookieReceived)
        XCTAssertFalse(peer.isEstablished)
        clock.time += 5
        let rekey = try XCTUnwrap(vector["rekey"] as? [String: Any])
        try clock.use(rekey)
        guard case .handshakeResponse(let nextResponse) = try peer.receive(bytes(rekey, "initiation")) else {
            return XCTFail("Expected a response using the cached cookie")
        }
        XCTAssertEqual(Data(nextResponse.prefix(76)), Data(try bytes(rekey, "response").prefix(76)))
        XCTAssertEqual(Data(nextResponse.suffix(16)), WireGuardCrypto.mac(key: cookie, data: Data(nextResponse.prefix(76))))
    }

    func testResponderIndexCollisionCannotReplaceLiveStateOrConsumeTheFreshTimestamp() throws {
        let vector = try XCTUnwrap(vectors().first)
        let clock = try Clock(vector)
        let peer = try responder(vector, clock: clock)
        _ = try peer.receive(bytes(vector, "initiation"))
        _ = try peer.receive(bytes(vector, "sent_transport"))
        clock.time += 5
        let rekey = try XCTUnwrap(vector["rekey"] as? [String: Any])
        XCTAssertThrowsError(try peer.receive(bytes(rekey, "initiation"))) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, .indexCollision)
        }
        XCTAssertTrue(peer.isEstablished)
        XCTAssertFalse(peer.isAwaitingConfirmation)
        try clock.use(rekey)
        XCTAssertEqual(try peer.receive(bytes(rekey, "initiation")), .handshakeResponse(try bytes(rekey, "response")))
    }

    func testMac1ValidInvalidInitiationsExhaustBudgetBeforeDHAndRefillAllowsTheLegitimatePeer() throws {
        let vector = try XCTUnwrap(vectors().first)
        let clock = try Clock(vector)
        let peer = try responder(vector, clock: clock)
        var invalid = try bytes(vector, "initiation")
        invalid.replaceSubrange(8..<40, with: Data(repeating: 0, count: 32))
        authenticateInitiation(&invalid, recipient: peer.publicKey)
        for _ in 0..<8 {
            XCTAssertThrowsError(try peer.receive(invalid)) {
                XCTAssertTrue([WireGuardPeer.Error.authenticationFailed, .invalidKey].contains($0 as? WireGuardPeer.Error ?? .invalidMessage),
                              "The low-order ephemeral reaches DH rejection inside the budget")
            }
        }
        XCTAssertThrowsError(try peer.receive(invalid)) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, .handshakeRateLimited, "The next attempt is rejected before DH")
        }
        XCTAssertFalse(peer.isAwaitingConfirmation)
        XCTAssertEqual(peer.handshakeGeneration, 0)
        clock.time += 0.03
        XCTAssertEqual(try peer.receive(bytes(vector, "initiation")), .handshakeResponse(try bytes(vector, "response")))
        XCTAssertEqual(try peer.receive(bytes(vector, "sent_transport")), .packet(try bytes(vector, "plaintext")))
    }

    func testForgedMac1DoesNotConsumeTheExpensiveHandshakeBudget() throws {
        let vector = try XCTUnwrap(vectors().first)
        let peer = try responder(vector, clock: Clock(vector))
        var invalid = try bytes(vector, "initiation")
        invalid[116] ^= 1
        for _ in 0..<32 {
            XCTAssertThrowsError(try peer.receive(invalid)) {
                XCTAssertEqual($0 as? WireGuardPeer.Error, .authenticationFailed)
            }
        }
        XCTAssertEqual(try peer.receive(bytes(vector, "initiation")), .handshakeResponse(try bytes(vector, "response")))
    }

    func testAttemptBudgetSurvivesResetAndLongSleepRefillsOnlyOneBoundedBurst() throws {
        let vector = try XCTUnwrap(vectors().first)
        let clock = try Clock(vector)
        let peer = try responder(vector, clock: clock)
        var invalid = try bytes(vector, "initiation")
        invalid.replaceSubrange(8..<40, with: Data(repeating: 0, count: 32))
        authenticateInitiation(&invalid, recipient: peer.publicKey)
        for _ in 0..<8 { XCTAssertThrowsError(try peer.receive(invalid)) }
        peer.reset()
        XCTAssertThrowsError(try peer.receive(invalid)) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, .handshakeRateLimited)
        }
        clock.time += 1_000_000
        for _ in 0..<8 {
            XCTAssertThrowsError(try peer.receive(invalid)) {
                XCTAssertTrue([WireGuardPeer.Error.authenticationFailed, .invalidKey].contains($0 as? WireGuardPeer.Error ?? .invalidMessage))
            }
        }
        XCTAssertThrowsError(try peer.receive(invalid)) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, .handshakeRateLimited, "Elapsed time cannot accumulate more than eight tokens")
        }
    }

    func testAttemptExhaustionCannotMutateCurrentPendingKeysOrTransportReplayHistory() throws {
        let vector = try XCTUnwrap(vectors().first)
        let clock = try Clock(vector)
        let peer = try responder(vector, clock: clock)
        let packet = try bytes(vector, "plaintext")
        _ = try peer.receive(bytes(vector, "initiation"))
        _ = try peer.receive(bytes(vector, "sent_transport"))
        let oldPrepared = try peer.prepare(packet)
        clock.time += 5
        let rekey = try XCTUnwrap(vector["rekey"] as? [String: Any])
        try clock.use(rekey)
        _ = try peer.receive(bytes(rekey, "initiation"))
        var invalid = try bytes(rekey, "initiation")
        invalid.replaceSubrange(8..<40, with: Data(repeating: 0, count: 32))
        authenticateInitiation(&invalid, recipient: peer.publicKey)
        for _ in 0..<8 { XCTAssertThrowsError(try peer.receive(invalid)) }
        XCTAssertTrue(peer.isEstablished)
        XCTAssertTrue(peer.isAwaitingConfirmation)
        XCTAssertTrue(peer.canSend(oldPrepared))
        XCTAssertEqual(peer.handshakeGeneration, 1)
        XCTAssertThrowsError(try peer.receive(bytes(vector, "sent_transport")), "Current-session replay history is unchanged")
        let oldHeader = little(UInt32(4)) + little(try XCTUnwrap(vector["responder_index"] as? UInt32)) + little(UInt64(1))
        let oldPacket = oldHeader + (try WireGuardCrypto.seal(key: bytes(vector, "sending_key"), counter: 1,
                                                           plaintext: packet + Data(repeating: 0, count: 12)))
        XCTAssertEqual(try peer.receive(oldPacket), .packet(packet))
        XCTAssertEqual(try peer.receive(bytes(rekey, "sent_transport")), .packet(packet), "Confirmation bypasses the initiation-only budget")
        XCTAssertEqual(peer.handshakeGeneration, 2)
        XCTAssertFalse(peer.canSend(oldPrepared))
        XCTAssertEqual(try peer.encrypt(packet), try bytes(rekey, "received_transport"))
    }

    private final class Clock {
        var time: TimeInterval = 1000
        var ephemeral: Data
        var index: UInt32
        init(_ vector: [String: Any]) throws {
            ephemeral = Data(repeating: 0x44, count: 32)
            index = try XCTUnwrap(vector["responder_index"] as? UInt32)
        }
        func use(_ vector: [String: Any]) throws {
            ephemeral = Data(repeating: 0x77, count: 32)
            index = try XCTUnwrap(vector["responder_index"] as? UInt32)
        }
    }

    private func responder(_ vector: [String: Any], clock: Clock, psk: Data? = nil) throws -> WireGuardPeer {
        try WireGuardPeer(privateKey: bytes(vector, "responder_private"), peerPublicKey: bytes(vector, "initiator_public"),
                          presharedKey: psk ?? bytes(vector, "preshared_key"), ephemeralPrivateKey: { clock.ephemeral },
                          senderIndex: { clock.index }, now: { clock.time }, timestamp: { Data(repeating: 0, count: 12) })
    }

    private func authenticateInitiation(_ data: inout Data, recipient: Data) {
        let key = WireGuardCrypto.hash(Data("mac1----".utf8) + recipient)
        data.replaceSubrange(116..<132, with: WireGuardCrypto.mac(key: key, data: data.prefix(116)))
    }

    private func vectors() throws -> [[String: Any]] {
        try WireGuardTestData.handshakeVectors()
    }

    private func bytes(_ vector: [String: Any], _ name: String) throws -> Data {
        try WireGuardTestData.hexBytes(XCTUnwrap(vector[name] as? String))
    }

    private func little<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
