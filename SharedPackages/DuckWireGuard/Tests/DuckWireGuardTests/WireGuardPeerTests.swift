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

import Foundation
import XCTest
@testable import DuckWireGuard

final class WireGuardPeerTests: XCTestCase {
    func testRejectsInvalidAndLowOrderKeys() throws {
        let (_, _, fixture) = try context()
        let privateKey = try bytes(fixture, "initiator_private")
        let publicKey = try bytes(fixture, "responder_public")
        for count in [0, 31, 33] {
            XCTAssertThrowsError(try WireGuardPeer(privateKey: Data(repeating: 1, count: count), peerPublicKey: publicKey))
            XCTAssertThrowsError(try WireGuardPeer(privateKey: privateKey, peerPublicKey: Data(repeating: 1, count: count)))
            XCTAssertThrowsError(try WireGuardPeer(privateKey: privateKey, peerPublicKey: publicKey,
                                                 presharedKey: Data(repeating: 1, count: count)))
        }
        XCTAssertThrowsError(try WireGuardPeer(privateKey: privateKey, peerPublicKey: Data(repeating: 0, count: 32)))
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

    func testPreparedPacketMatchesIndependentTransportAndKeepsItsInputSnapshot() throws {
        let (peer, _, fixture) = try context()
        var packet = try bytes(fixture, "plaintext")
        let prepared = try peer.prepare(packet)
        packet[4] ^= 1
        XCTAssertEqual(prepared.packet, try bytes(fixture, "plaintext"))
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

    func testSessionRekeyHintAndExpiryUseMonotonicTime() throws {
        let (peer, clock, fixture) = try context()
        XCTAssertFalse(peer.needsRekey)
        clock.time += 120
        XCTAssertTrue(peer.needsRekey)
        XCTAssertTrue(peer.isEstablished)
        XCTAssertNoThrow(try peer.keepalive())
        clock.time += 60
        XCTAssertFalse(peer.isEstablished)
        assertError(.sessionExpired) { _ = try peer.keepalive() }
        assertError(.sessionExpired) { _ = try peer.receive(bytes(fixture, "received_transport")) }
    }

    func testExpiredResponseDoesNotEstablishSession() throws {
        let (peer, clock, fixture) = try context(established: false)
        _ = try peer.initiateHandshake()
        clock.time += 180
        assertError(.handshakeExpired) { _ = try peer.receive(bytes(fixture, "response")) }
        XCTAssertFalse(peer.isEstablished)
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

    func testReplayWindowAcceptsReorderingAndRejectsItsLowerBoundary() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        let receive = { (counter: UInt64) in try self.transport(fixture, counter: counter, plaintext: packet) }
        XCTAssertEqual(try peer.receive(receive(9000)), .packet(packet))
        XCTAssertEqual(try peer.receive(receive(8999)), .packet(packet))
        XCTAssertEqual(try peer.receive(receive(872)), .packet(packet), "Distance 8128 is inclusive")
        assertError(.replayedPacket) { _ = try peer.receive(receive(871)) }
        assertError(.replayedPacket) { _ = try peer.receive(receive(872)) }
        assertError(.replayedPacket) { _ = try peer.receive(receive(8999)) }
        XCTAssertEqual(try peer.receive(receive(9001)), .packet(packet))
    }

    func testReplayBoundaryMatchesGoAtEveryWordAlignment() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        for offset in UInt64(0)..<64 {
            // Each jump clears the full ring, while the low six bits cover every word alignment.
            let highest = 16_384 + offset * 16_385
            let receive = { (counter: UInt64) in try self.transport(fixture, counter: counter, plaintext: packet) }
            XCTAssertEqual(try peer.receive(receive(highest)), .packet(packet))
            XCTAssertEqual(try peer.receive(receive(highest - 8128)), .packet(packet), "alignment \(offset)")
            assertError(.replayedPacket) { _ = try peer.receive(receive(highest - 8129)) }
            assertError(.replayedPacket) { _ = try peer.receive(receive(highest - 8128)) }
        }
    }

    func testReplayBitmapReusesWordsAcrossFullRingWraps() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        let receive = { (counter: UInt64) in try self.transport(fixture, counter: counter, plaintext: packet) }
        for highest in [UInt64(8192), 16_384, 24_576] {
            XCTAssertEqual(try peer.receive(receive(highest)), .packet(packet))
            XCTAssertEqual(try peer.receive(receive(highest - 8128)), .packet(packet))
            assertError(.replayedPacket) { _ = try peer.receive(receive(highest - 8129)) }
            assertError(.replayedPacket) { _ = try peer.receive(receive(highest)) }
            assertError(.replayedPacket) { _ = try peer.receive(receive(highest - 8128)) }
        }
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

    func testReplayWindowMatchesReferenceAcrossWrapsReorderingAndLargeJumps() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        var counters: [UInt64] = [
            0, 63, 64, 65, 0, 63, 127, 128, 8127, 0, 8128, 0, 8129, 1, 0,
            8191, 63, 8192, 64, 63, 8193, 65, 8256, 128, 8191, 16_383, 8255, 16_384, 8256
        ]
        var head: UInt64 = 16_384
        var seed: UInt64 = 0x82a2b175229d6a5b
        let jumps: [UInt64] = [8127, 8128, 8129, 8191, 8192, 8193, 16_384]
        for _ in 0..<4096 {
            seed = seed &* 6364136223846793005 &+ 1
            if seed & 3 < 2 {
                head += seed & 0x100 == 0 ? (seed >> 16) % 97 + 1 : jumps[Int((seed >> 16) % UInt64(jumps.count))]
                counters.append(head)
            } else {
                let distance = (seed >> 16) % 16_385
                counters.append(head >= distance ? head - distance : 0)
            }
        }
        let lastAccepted = UInt64.max - 8193
        counters += [lastAccepted, lastAccepted - 8128, lastAccepted - 8129, lastAccepted, lastAccepted - 1]
        var highest: UInt64 = 0
        // Independent set model of Go's inclusive distance limit; no ring/word operations.
        var seen = Set<UInt64>()
        for counter in counters {
            let expected = !seen.contains(counter) && (counter > highest || highest - counter <= 8128)
            if expected {
                highest = max(highest, counter)
                seen = seen.filter { highest - $0 <= 8128 }
                seen.insert(counter)
            }
            let datagram = try transport(fixture, counter: counter, plaintext: packet)
            if expected {
                XCTAssertEqual(try peer.receive(datagram), .packet(packet), "counter \(counter)")
            } else {
                assertError(.replayedPacket) { _ = try peer.receive(datagram) }
            }
        }
    }

    func testRejectsCountersAtProtocolLimitWithoutOverflowing() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        let lastAccepted = UInt64.max - 8193
        XCTAssertEqual(try peer.receive(transport(fixture, counter: lastAccepted, plaintext: packet)), .packet(packet))
        for counter in [lastAccepted + 1, UInt64.max] {
            assertError(.counterExhausted) { _ = try peer.receive(transport(fixture, counter: counter, plaintext: packet)) }
        }
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

    func testRejectsInvalidIPPacketsBeforeEncryption() throws {
        let (peer, _, fixture) = try context()
        let packet = try bytes(fixture, "plaintext")
        var invalidVersion = packet
        invalidVersion[0] = 0x70
        var invalidHeader = packet
        invalidHeader[0] = 0x4f
        var invalidLength = packet
        invalidLength[3] = 21
        for invalid in [Data(), Data([0x45]), invalidVersion, invalidHeader, invalidLength, packet + Data([0])] {
            assertError(.invalidPacket) { _ = try peer.encrypt(invalid) }
        }
    }

    func testRejectsShortTransportAndNonzeroReservedFields() throws {
        let (peer, _, fixture) = try context()
        let incoming = try bytes(fixture, "received_transport")
        for count in 0..<32 {
            XCTAssertThrowsError(try peer.receive(Data(incoming.prefix(count))))
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
