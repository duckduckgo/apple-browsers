//
//  WireGuardPeerTests.swift
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

final class WireGuardPeerTests: XCTestCase {
    func testInitializerPropagatesHandshakeKeyValidationErrors() throws {
        let fixture = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        let privateKey = try bytes(fixture, "initiator_private")
        let publicKey = try bytes(fixture, "responder_public")
        assertError(.invalidKey) {
            _ = try WireGuardPeer(privateKey: Data(), peerPublicKey: publicKey)
        }
        assertError(.invalidKey) {
            _ = try WireGuardPeer(privateKey: privateKey, peerPublicKey: Data(repeating: 1, count: 31))
        }
        assertError(.invalidKey) {
            _ = try WireGuardPeer(privateKey: privateKey, peerPublicKey: publicKey, presharedKey: Data(repeating: 1, count: 33))
        }
        assertError(.invalidKey) {
            _ = try WireGuardPeer(privateKey: privateKey, peerPublicKey: Data(repeating: 0, count: 32))
        }
    }

    func testSendingRequiresAHandshake() throws {
        let (peer, _, fixture) = try context(established: false)
        XCTAssertFalse(peer.isEstablished)
        XCTAssertTrue(peer.needsRekey)
        assertError(.handshakeRequired) { _ = try peer.keepalive() }
        assertError(.handshakeRequired) { _ = try peer.encrypt(bytes(fixture, "plaintext")) }
    }

    func testAliasedPeerUsesOneIncreasingSendCounter() throws {
        let (peer, _, _) = try context()
        let alias = peer
        let first = try peer.keepalive()
        let second = try alias.keepalive()
        XCTAssertEqual(first[8], 0)
        XCTAssertEqual(second[8], 1)
        XCTAssertNotEqual(first.suffix(16), second.suffix(16))
    }

    func testPreparationAcceptsSlicedInputAndMatchesIndependentTransport() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        let sliced = (Data([0xaa, 0xbb, 0xcc]) + packet).dropFirst(3)
        XCTAssertEqual(sliced.startIndex, 3)
        let prepared = try peer.prepare(sliced)
        XCTAssertEqual(prepared.packet, packet)
        XCTAssertEqual(try prepared.encrypt(), try bytes(fixture, "sent_transport"))
        XCTAssertTrue(peer.canSend(prepared))
    }

    func testPreparedAndDiscardedWorkReserveUniqueNoncesAlongsideKeepalives() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        let first = try peer.prepare(packet)
        _ = try peer.prepare(packet) // Discarding work must not recycle its nonce.
        let keepalive = try peer.keepalive()
        let fourth = try peer.prepare(packet)
        XCTAssertEqual(try first.encrypt()[8], 0)
        XCTAssertEqual(keepalive[8], 2)
        XCTAssertEqual(try fourth.encrypt()[8], 3)
        XCTAssertEqual(try peer.encrypt(packet)[8], 4)
    }

    func testPreparedPacketBindsPaddingAtANonAlignedMTU() throws {
        let (peer, _, fixture) = try context()
        var packet = try bytes(fixture, "plaintext")
        packet.append(Data(repeating: 0xab, count: 1281 - packet.count))
        packet[2] = 0x05
        packet[3] = 0x01
        var limit = 1281
        let prepared = try peer.prepare(packet, maximumPacketLength: limit)
        limit = 1400
        let datagram = try prepared.encrypt()
        XCTAssertEqual(datagram.count, 1281 + 32, "Padding must not exceed the reserved IP-packet limit")
        XCTAssertEqual(try prepared.encrypt(), datagram, "A prepared nonce always encrypts the same bound plaintext")
        XCTAssertEqual(try WireGuardCrypto.open(key: bytes(fixture, "sending_key"), counter: 0,
                                               ciphertext: datagram.dropFirst(16)), packet)
        let largerLimit = try peer.prepare(packet, maximumPacketLength: limit).encrypt()
        XCTAssertEqual(largerLimit.count, 1296 + 32)
        XCTAssertEqual(largerLimit[8], 1, "Changing the padding policy requires a new nonce reservation")
    }

    func testPreparedPaddingCapsPartialPaddingAtThePacketLimit() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        let prepared = try peer.prepare(packet, maximumPacketLength: packet.count + 1)
        let datagram = try prepared.encrypt()
        let plaintext = try WireGuardCrypto.open(key: bytes(fixture, "sending_key"), counter: 0,
                                                 ciphertext: datagram.dropFirst(16))
        XCTAssertEqual(plaintext, packet + Data([0]))
        XCTAssertEqual(datagram.count, packet.count + 1 + 32)
    }

    func testInvalidPacketLimitsDoNotConsumeANonce() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        for limit in [-1, 0, packet.count - 1] {
            assertError(.invalidPacket) { _ = try peer.prepare(packet, maximumPacketLength: limit) }
        }
        XCTAssertEqual(try peer.prepare(packet, maximumPacketLength: Int.max).encrypt(), try bytes(fixture, "sent_transport"))
    }

    func testInvalidPreparationDoesNotConsumeANonce() throws {
        let (peer, _, fixture) = try context()
        assertError(.invalidPacket) { _ = try peer.prepare(Data([0x45])) }
        XCTAssertEqual(try peer.prepare(bytes(fixture, "plaintext")).encrypt(), try bytes(fixture, "sent_transport"))
    }

    func testPreparedPacketCannotBeSubmittedAfterExpiryResetOrByAnotherPeer() throws {
        let (peer, clock, fixture) = try context()
        let prepared = try peer.prepare(bytes(fixture, "plaintext"))
        let (otherPeer, _, _) = try context()
        XCTAssertFalse(otherPeer.canSend(prepared), "Session identity also distinguishes peers with identical fixture keys")
        clock.time += 179.999
        XCTAssertTrue(peer.canSend(prepared))
        clock.time = 1180
        XCTAssertFalse(peer.canSend(prepared))
        peer.reset()
        XCTAssertFalse(peer.canSend(prepared))
    }

    func testPreparedPacketsEncryptConcurrentlyWithoutChangingReservedOutput() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        let prepared = try (0..<64).map { _ in try peer.prepare(packet) }
        let expected = try prepared.map { try $0.encrypt() }
        let completed = expectation(description: "immutable packets encrypted concurrently")
        DispatchQueue(label: "wireguard-test-workers").async {
            DispatchQueue.concurrentPerform(iterations: prepared.count) { index in
                XCTAssertFalse(Thread.isMainThread)
                XCTAssertEqual(try? prepared[index].encrypt(), expected[index])
            }
            completed.fulfill()
        }
        wait(for: [completed], timeout: 3)
        XCTAssertEqual(try peer.keepalive()[8], 64)
    }

    func testTimestampEncodingMatchesTAI64NByteLayout() throws {
        let cases: [(TimeInterval, String)] = [
            (0, "400000000000000a00000000"),
            (1, "400000000000000b00000000"),
            (0.5, "400000000000000a1dcd6500"),
            (4_294_967_296.25, "400000010000000a0ee6b280")
        ]
        for (time, expected) in cases {
            XCTAssertEqual(WireGuardPeer.makeTimestamp(at: time), try WireGuardTestData.hexBytes(expected), "Unix time \(time)")
        }
    }

    func testSessionRekeyHintAndExpiryUseRoleAndMonotonicTime() throws {
        for isInitiator in [true, false] {
            let clock = Clock()
            let (peer, fixture) = try counterPeer(isInitiator: isInitiator, initialSendCounter: 0, now: { clock.time })
            for age in [0.0, 119.999, 120, 179.999] {
                clock.time = 1000 + age
                XCTAssertEqual(peer.needsRekey, isInitiator && age >= 120, "age \(age), initiator \(isInitiator)")
                XCTAssertTrue(peer.isEstablished)
                XCTAssertNoThrow(try peer.keepalive())
            }
            clock.time = 1180
            XCTAssertTrue(peer.needsRekey)
            XCTAssertFalse(peer.isEstablished)
            assertError(.sessionExpired) { _ = try peer.keepalive() }
            let incoming = try bytes(fixture, isInitiator ? "received_transport" : "sent_transport")
            assertError(.sessionExpired) { _ = try peer.receive(incoming) }
        }
    }

    func testExpiredResponseDoesNotEstablishSession() throws {
        let (peer, clock, fixture) = try context(established: false)
        _ = try peer.initiateHandshake()
        clock.time += 180
        assertError(.handshakeExpired) { _ = try peer.receive(bytes(fixture, "response")) }
        XCTAssertFalse(peer.isEstablished)
    }

    func testReceiveRekeyHintRequiresEstablishedKeys() throws {
        let (peer, clock, _) = try context(established: false)
        XCTAssertFalse(peer.needsRekeyAfterReceiving)
        _ = try peer.initiateHandshake()
        clock.time += 166
        XCTAssertFalse(peer.needsRekeyAfterReceiving)
    }

    func testReceiveRekeyHintUsesInitiatorRoleAndStrictTimeBoundary() throws {
        for isInitiator in [true, false] {
            let clock = Clock()
            let (peer, _) = try counterPeer(isInitiator: isInitiator, initialSendCounter: 0, now: { clock.time })
            for age in [0.0, 164.999, 165, 165.001, 179.999, 180] {
                clock.time = 1000 + age
                XCTAssertEqual(peer.needsRekeyAfterReceiving, isInitiator && age > 165, "age \(age), initiator \(isInitiator)")
            }
            peer.reset()
            XCTAssertFalse(peer.needsRekeyAfterReceiving)
        }
    }

    func testHandshakeRateLimitPreservesPendingState() throws {
        let (peer, _, fixture) = try context(established: false)
        _ = try peer.initiateHandshake()
        assertError(.handshakeRateLimited) { _ = try peer.initiateHandshake() }
        XCTAssertEqual(try peer.receive(bytes(fixture, "response")), .handshakeComplete)
    }

    func testManualHandshakeDoesNotDiscardLiveSession() throws {
        let (peer, clock, fixture) = try context()
        clock.time += 5
        clock.index += 1
        _ = try peer.initiateHandshake()
        XCTAssertTrue(peer.isEstablished)
        XCTAssertEqual(try peer.receive(bytes(fixture, "received_transport")), .packet(try bytes(fixture, "plaintext")))
        XCTAssertNoThrow(try peer.keepalive())
    }

    func testRejectsAnIndexThatWouldCollideWithLiveSession() throws {
        let (peer, clock, _) = try context()
        clock.time += 5
        assertError(.indexCollision) { _ = try peer.initiateHandshake() }
        XCTAssertTrue(peer.isEstablished)
        XCTAssertNoThrow(try peer.keepalive())
    }

    func testRekeyRetainsPreviousReceiveSessionAndItsReplayWindow() throws {
        let (_, _, fixture) = try context(established: false)
        let rekey = try XCTUnwrap(fixture["rekey"] as? [String: Any])
        let clock = Clock()
        var ephemeral = try bytes(fixture, "initiator_ephemeral")
        var timestamp = try bytes(fixture, "timestamp")
        let peer = try WireGuardPeer(
            privateKey: bytes(fixture, "initiator_private"), peerPublicKey: bytes(fixture, "responder_public"),
            ephemeralPrivateKey: { ephemeral }, senderIndex: { clock.index }, now: { clock.time }, timestamp: { timestamp }
        )
        XCTAssertEqual(try peer.initiateHandshake(), try bytes(fixture, "initiation"))
        XCTAssertEqual(try peer.receive(bytes(fixture, "response")), .handshakeComplete)
        let packet = try bytes(fixture, "plaintext")
        let oldPrepared = try peer.prepare(packet)
        XCTAssertTrue(peer.canSend(oldPrepared))
        XCTAssertEqual(try peer.receive(bytes(fixture, "received_transport")), .packet(packet))
        XCTAssertEqual(try peer.receive(transport(fixture, counter: 6000, plaintext: packet)), .packet(packet))

        clock.time += 5
        clock.index += 1
        ephemeral = try bytes(rekey, "initiator_ephemeral")
        timestamp = try bytes(rekey, "timestamp")
        XCTAssertEqual(try peer.initiateHandshake(), try bytes(rekey, "initiation"))
        XCTAssertTrue(peer.canSend(oldPrepared), "A pending handshake still permits the active session")
        XCTAssertEqual(try peer.receive(bytes(rekey, "response")), .handshakeComplete)
        XCTAssertFalse(peer.canSend(oldPrepared), "Completed rekey invalidates old upload snapshots")
        XCTAssertEqual(try peer.encrypt(packet), try bytes(rekey, "sent_transport"))
        XCTAssertEqual(try peer.receive(bytes(rekey, "received_transport")), .packet(packet))
        XCTAssertEqual(try peer.receive(bytes(fixture, "received_transport_next")), .packet(packet))
        assertError(.replayedPacket) { _ = try peer.receive(bytes(fixture, "received_transport")) }

        clock.time += 175
        XCTAssertTrue(peer.isEstablished)
        assertError(.sessionExpired) { _ = try peer.receive(bytes(fixture, "received_transport_next")) }
        XCTAssertEqual(try peer.receive(bytes(rekey, "received_transport_next")), .packet(packet))
    }

    func testAuthenticatedTransportGenerationIgnoresForgeriesAndReplaysButCountsRejectedInnerPackets() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        XCTAssertEqual(peer.authenticatedTransportGeneration, 0)
        let valid = try transport(fixture, counter: 0, plaintext: packet)
        XCTAssertEqual(try peer.receive(valid), .packet(packet))
        XCTAssertEqual(peer.authenticatedTransportGeneration, 1)
        assertError(.replayedPacket) { _ = try peer.receive(valid) }
        XCTAssertEqual(peer.authenticatedTransportGeneration, 1)

        let malformed = try transport(fixture, counter: 1, plaintext: Data([0x70]))
        var forged = malformed
        forged[forged.count - 1] ^= 1
        assertError(.authenticationFailed) { _ = try peer.receive(forged) }
        XCTAssertEqual(peer.authenticatedTransportGeneration, 1)
        assertError(.invalidPacket) { _ = try peer.receive(malformed) }
        XCTAssertEqual(peer.authenticatedTransportGeneration, 2)
        assertError(.replayedPacket) { _ = try peer.receive(malformed) }
        XCTAssertEqual(peer.authenticatedTransportGeneration, 2)
        XCTAssertEqual(try peer.receive(transport(fixture, counter: 2, plaintext: packet)), .packet(packet))
        XCTAssertEqual(peer.authenticatedTransportGeneration, 3)
    }

    func testThirdSessionEvictsOldestKeysAndPreservesPreviousReplayHistoryForBothRoles() throws {
        let (_, _, fixture) = try context(established: false)
        let packet = try bytes(fixture, "plaintext")
        var time: TimeInterval = 1000
        var timestamp = try bytes(fixture, "timestamp")
        var initiatorIndex: UInt32 = 1
        var responderIndex: UInt32 = 1001
        var initiatorEphemeral = Data(repeating: 0x30, count: 32)
        var responderEphemeral = Data(repeating: 0x60, count: 32)
        let initiator = try WireGuardPeer(
            privateKey: bytes(fixture, "initiator_private"), peerPublicKey: bytes(fixture, "responder_public"),
            ephemeralPrivateKey: { initiatorEphemeral }, senderIndex: { defer { initiatorIndex += 1 }; return initiatorIndex },
            now: { time }, timestamp: { timestamp }
        )
        let responder = try WireGuardPeer(
            privateKey: bytes(fixture, "responder_private"), peerPublicKey: bytes(fixture, "initiator_public"),
            ephemeralPrivateKey: { responderEphemeral }, senderIndex: { defer { responderIndex += 1 }; return responderIndex },
            now: { time }, timestamp: { timestamp }
        )
        var fromInitiator: [(received: Data, delayed: Data, held: Data)] = []
        var fromResponder: [(received: Data, delayed: Data, held: Data)] = []

        for generation in 0..<3 {
            time = 1000 + Double(generation) * 6
            timestamp[11] = UInt8(generation + 1)
            initiatorEphemeral = Data(repeating: UInt8(0x30 + generation), count: 32)
            responderEphemeral = Data(repeating: UInt8(0x60 + generation), count: 32)
            let initiation = try initiator.initiateHandshake()
            guard case .handshakeResponse(let response) = try responder.receive(initiation) else {
                return XCTFail("Expected a response for generation \(generation)")
            }
            XCTAssertEqual(try initiator.receive(response), .handshakeComplete)
            let confirmation = try initiator.keepalive()
            XCTAssertEqual(Data(confirmation[8..<16]), Data(repeating: 0, count: 8))
            XCTAssertEqual(try responder.receive(confirmation), .keepalive)
            let outgoing = try initiator.encrypt(packet)
            let incoming = try responder.encrypt(packet)
            XCTAssertEqual(Data(incoming[8..<16]), Data(repeating: 0, count: 8))
            XCTAssertEqual(try responder.receive(outgoing), .packet(packet))
            XCTAssertEqual(try initiator.receive(incoming), .packet(packet))
            fromInitiator.append((outgoing, try initiator.encrypt(packet), try initiator.encrypt(packet)))
            fromResponder.append((incoming, try responder.encrypt(packet), try responder.encrypt(packet)))

            if generation > 0 {
                XCTAssertEqual(try responder.receive(fromInitiator[generation - 1].delayed), .packet(packet))
                XCTAssertEqual(try initiator.receive(fromResponder[generation - 1].delayed), .packet(packet))
                assertError(.replayedPacket) { _ = try responder.receive(fromInitiator[generation - 1].received) }
                assertError(.replayedPacket) { _ = try initiator.receive(fromResponder[generation - 1].received) }
            }
        }

        // Keys are only twelve seconds old, so rejection proves rotation rather than expiry (WireGuard §6.3).
        assertError(.unexpectedMessage) { _ = try responder.receive(fromInitiator[0].held) }
        assertError(.unexpectedMessage) { _ = try initiator.receive(fromResponder[0].held) }
        XCTAssertEqual(try responder.receive(fromInitiator[1].held), .packet(packet))
        XCTAssertEqual(try initiator.receive(fromResponder[1].held), .packet(packet))
        assertError(.replayedPacket) { _ = try responder.receive(fromInitiator[1].held) }
        assertError(.replayedPacket) { _ = try initiator.receive(fromResponder[1].held) }
        XCTAssertEqual(initiator.handshakeGeneration, 3)
        XCTAssertEqual(responder.handshakeGeneration, 3)
        let initiatorKeepalive = try initiator.keepalive()
        let responderKeepalive = try responder.keepalive()
        XCTAssertEqual(initiatorKeepalive[8], 4, "Receiving old traffic cannot rewind the current sending counter")
        XCTAssertEqual(responderKeepalive[8], 3)
        XCTAssertEqual(try responder.receive(initiatorKeepalive), .keepalive)
        XCTAssertEqual(try initiator.receive(responderKeepalive), .keepalive)
    }

    func testCookieChallengeCachesCookieWithoutSendingARetry() throws {
        let (peer, _, fixture) = try context(established: false)
        _ = try peer.initiateHandshake()
        let challenge = try bytes(fixture, "cookie_reply")
        var forged = challenge
        forged[32] ^= 1
        assertError(.authenticationFailed) { _ = try peer.receive(forged) }
        XCTAssertEqual(try peer.receive(challenge), .cookieReceived)
        XCTAssertEqual(try peer.receive(bytes(fixture, "response")), .handshakeComplete)
    }

    func testForgedCounterCannotEvictAuthenticatedReorderedPackets() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        XCTAssertEqual(try peer.receive(transport(fixture, counter: 9000, plaintext: packet)), .packet(packet))
        var forged = try transport(fixture, counter: UInt64.max - 8193, plaintext: packet)
        forged[16] ^= 1
        assertError(.authenticationFailed) { _ = try peer.receive(forged) }
        let boundary = try transport(fixture, counter: 872, plaintext: packet)
        XCTAssertEqual(try peer.receive(boundary), .packet(packet))
        assertError(.replayedPacket) { _ = try peer.receive(boundary) }
    }

    func testReceiveThroughputWithAFullReplayWindow() throws {
        let (peer, _, fixture) = try context()
        var packet = try bytes(fixture, "plaintext")
        packet.append(Data(repeating: 0xab, count: 1200 - packet.count))
        packet[2] = 0x04
        packet[3] = 0xb0
        let warmup = 8192
        let count = 5000
        // Generate authenticated traffic before timing, so sender-side work is excluded.
        let datagrams = try (0..<(warmup + count)).map {
            try transport(fixture, counter: UInt64($0), plaintext: packet)
        }
        for datagram in datagrams.prefix(warmup) { _ = try peer.receive(datagram) }
        var receivedBytes = 0
        let start = ProcessInfo.processInfo.systemUptime
        for datagram in datagrams.dropFirst(warmup) {
            if case .packet(let received) = try peer.receive(datagram) { receivedBytes += received.count }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        XCTAssertEqual(receivedBytes, count * packet.count)
        print(String(format: "WG receive benchmark: %d packets, %.3f seconds, %.1f microseconds/packet, %.1f payload Mbit/s",
                     count, elapsed, elapsed * 1_000_000 / Double(count), Double(receivedBytes) * 8 / elapsed / 1_000_000))
    }

    func testPeerRekeyHintReflectsTransportMessageCountForBothRoles() throws {
        let rekeyAfterMessages: UInt64 = 1 << 60
        for isInitiator in [true, false] {
            let (peer, _) = try counterPeer(isInitiator: isInitiator, initialSendCounter: rekeyAfterMessages - 1)
            XCTAssertFalse(peer.needsRekey)
            _ = try peer.keepalive()
            XCTAssertTrue(peer.needsRekey)
        }
    }

    func testDiscardedReservationsConsumeCountersAndExhaustionDoesNotInvalidateTheLastLegalPacket() throws {
        let rejectAfterMessages = UInt64.max - 8192
        for isInitiator in [true, false] {
            let (peer, fixture) = try counterPeer(isInitiator: isInitiator, initialSendCounter: rejectAfterMessages - 2)
            let packet = try bytes(fixture, "plaintext")
            _ = try peer.prepare(packet)
            let lastLegal = try peer.prepare(packet)
            try assertOutgoingPacket(lastLegal.encrypt(), counter: rejectAfterMessages - 1, fixture: fixture, isInitiator: isInitiator)
            assertError(.counterExhausted) { _ = try peer.prepare(packet) }
            assertError(.counterExhausted) { _ = try peer.encrypt(packet) }
            assertError(.counterExhausted) { _ = try peer.keepalive() }
            XCTAssertTrue(peer.canSend(lastLegal))
            XCTAssertTrue(peer.isEstablished)
            XCTAssertTrue(peer.needsRekey)
        }
    }

    func testPublicInitializerStartsBothSendingRolesAtCounterZero() throws {
        let fixture = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        let initiator = try WireGuardPeer(privateKey: bytes(fixture, "initiator_private"), peerPublicKey: bytes(fixture, "responder_public"))
        let responder = try WireGuardPeer(privateKey: bytes(fixture, "responder_private"), peerPublicKey: bytes(fixture, "initiator_public"))
        guard case .handshakeResponse(let response) = try responder.receive(initiator.initiateHandshake()) else {
            return XCTFail("Expected an authenticated handshake response")
        }
        XCTAssertEqual(try initiator.receive(response), .handshakeComplete)
        let packet = try bytes(fixture, "plaintext")
        let outgoing = try initiator.encrypt(packet)
        XCTAssertEqual(Data(outgoing[8..<16]), Data(repeating: 0, count: 8))
        XCTAssertEqual(try responder.receive(outgoing), .packet(packet))
        let incoming = try responder.encrypt(packet)
        XCTAssertEqual(Data(incoming[8..<16]), Data(repeating: 0, count: 8))
        XCTAssertEqual(try initiator.receive(incoming), .packet(packet))
    }

    func testRejectsCountersAtProtocolLimitWithoutOverflowing() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        let lastAccepted = UInt64.max - 8193
        XCTAssertEqual(try peer.receive(transport(fixture, counter: lastAccepted, plaintext: packet)), .packet(packet))
        assertError(.counterExhausted) { _ = try peer.receive(transport(fixture, counter: lastAccepted + 1, plaintext: packet)) }
    }

    func testAcceptsEmptyKeepalive() throws {
        let (peer, _, fixture) = try context()
        XCTAssertEqual(try peer.receive(transport(fixture, counter: 0, plaintext: Data())), .keepalive)
    }

    func testIPv6LengthRemovesPadding() throws {
        let (peer, _, fixture) = try context()
        var packet = Data(repeating: 0, count: 43)
        packet[0] = 0x60
        packet[5] = 3
        packet[6] = 59
        packet[7] = 64
        packet[40] = 1
        packet[41] = 2
        packet[42] = 3
        XCTAssertEqual(try peer.receive(transport(fixture, counter: 0, plaintext: packet)), .packet(packet))
        XCTAssertEqual(try peer.encrypt(packet).count, 80)
    }

    func testInvalidOutgoingIPDoesNotConsumeANonce() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        var invalidVersion = packet
        invalidVersion[0] = 0x70
        for invalid in [invalidVersion, packet + Data([0])] {
            assertError(.invalidPacket) { _ = try peer.encrypt(invalid) }
        }
        XCTAssertEqual(try peer.encrypt(packet), try bytes(fixture, "sent_transport"))
    }

    func testMalformedTransportFramesDoNotConsumeTheAuthenticPacket() throws {
        let (peer, _, fixture) = try context()
        let incoming = try bytes(fixture, "received_transport")
        for count in [3, 31] {
            assertError(.invalidMessage) { _ = try peer.receive(Data(incoming.prefix(count))) }
        }
        var invalidReserved = incoming
        invalidReserved[1] = 1
        assertError(.unexpectedMessage) { _ = try peer.receive(invalidReserved) }
        XCTAssertEqual(try peer.receive(incoming), .packet(try bytes(fixture, "plaintext")))
    }

    func testResetDiscardsAllSessionState() throws {
        let (peer, _, fixture) = try context()
        peer.reset()
        XCTAssertFalse(peer.isEstablished)
        XCTAssertTrue(peer.needsRekey)
        assertError(.handshakeRequired) { _ = try peer.keepalive() }
        XCTAssertThrowsError(try peer.receive(bytes(fixture, "received_transport")))
        XCTAssertNoThrow(try peer.initiateHandshake())
    }

    private final class Clock {
        var time: TimeInterval = 1_000
        var index: UInt32 = 0x01020304
    }

    private func context(established: Bool = true) throws -> (WireGuardPeer, Clock, [String: Any]) {
        let fixtures = try WireGuardTestData.handshakeVectors()
        let fixture = try XCTUnwrap(fixtures.first)
        let clock = Clock()
        let ephemeral = try bytes(fixture, "initiator_ephemeral")
        let timestamp = try bytes(fixture, "timestamp")
        let peer = try WireGuardPeer(
            privateKey: bytes(fixture, "initiator_private"), peerPublicKey: bytes(fixture, "responder_public"),
            ephemeralPrivateKey: { ephemeral }, senderIndex: { clock.index }, now: { clock.time }, timestamp: { timestamp }
        )
        if established {
            _ = try peer.initiateHandshake()
            _ = try peer.receive(bytes(fixture, "response"))
        }
        return (peer, clock, fixture)
    }

    private func counterPeer(isInitiator: Bool, initialSendCounter: UInt64,
                             now: @escaping () -> TimeInterval = { 1000 }) throws -> (WireGuardPeer, [String: Any]) {
        let fixture = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        let ephemeral = try bytes(fixture, isInitiator ? "initiator_ephemeral" : "responder_ephemeral")
        let index = try XCTUnwrap(fixture[isInitiator ? "initiator_index" : "responder_index"] as? NSNumber).uint32Value
        let timestamp = try bytes(fixture, "timestamp")
        let peer = try WireGuardPeer(
            privateKey: bytes(fixture, isInitiator ? "initiator_private" : "responder_private"),
            peerPublicKey: bytes(fixture, isInitiator ? "responder_public" : "initiator_public"),
            ephemeralPrivateKey: { ephemeral }, senderIndex: { index }, now: now, timestamp: { timestamp },
            initialSendCounter: initialSendCounter
        )
        if isInitiator {
            XCTAssertEqual(try peer.initiateHandshake(), try bytes(fixture, "initiation"))
            XCTAssertEqual(try peer.receive(bytes(fixture, "response")), .handshakeComplete)
        } else {
            XCTAssertEqual(try peer.receive(bytes(fixture, "initiation")), .handshakeResponse(try bytes(fixture, "response")))
            XCTAssertEqual(try peer.receive(bytes(fixture, "sent_transport")), .packet(try bytes(fixture, "plaintext")))
        }
        return (peer, fixture)
    }

    private func assertOutgoingPacket(_ datagram: Data, counter: UInt64, fixture: [String: Any], isInitiator: Bool,
                                      file: StaticString = #filePath, line: UInt = #line) throws {
        let reference = try bytes(fixture, isInitiator ? "sent_transport" : "received_transport")
        XCTAssertEqual(Data(datagram.prefix(8)), Data(reference.prefix(8)), file: file, line: line)
        let counterBytes = withUnsafeBytes(of: counter.littleEndian) { Data($0) }
        XCTAssertEqual(Data(datagram[8..<16]), counterBytes, file: file, line: line)
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + counterBytes)
        let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: datagram[16..<(datagram.count - 16)], tag: datagram.suffix(16))
        let key = try bytes(fixture, isInitiator ? "sending_key" : "receiving_key")
        let plaintext = try ChaChaPoly.open(box, using: SymmetricKey(data: key))
        let packet = try bytes(fixture, "plaintext")
        let expected = packet + Data(repeating: 0, count: (16 - packet.count % 16) % 16)
        XCTAssertEqual(plaintext, expected, file: file, line: line)
    }

    private func transport(_ fixture: [String: Any], counter: UInt64, plaintext: Data) throws -> Data {
        let padded = plaintext + Data(repeating: 0, count: (16 - plaintext.count % 16) % 16)
        let ciphertext = try WireGuardCrypto.seal(key: bytes(fixture, "receiving_key"), counter: counter, plaintext: padded)
        let index: UInt32 = 0x01020304
        let header = Data([4, 0, 0, 0])
            + Data((0..<4).map { UInt8(truncatingIfNeeded: index >> ($0 * 8)) })
            + Data((0..<8).map { UInt8(truncatingIfNeeded: counter >> ($0 * 8)) })
        return header + ciphertext
    }

    private func bytes(_ fixture: [String: Any], _ field: String) throws -> Data {
        try WireGuardTestData.hexBytes(XCTUnwrap(fixture[field] as? String))
    }

    private func assertError(_ expected: WireGuardPeer.Error, file: StaticString = #filePath,
                             line: UInt = #line, _ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? WireGuardPeer.Error, expected, file: file, line: line)
        }
    }
}
