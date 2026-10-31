//
//  WireGuardConformanceTests.swift
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

/// Wire-format and adversarial state-transition checks, supplementing the independent reference fixtures.
/// Timer scheduling, socket lifecycle, IP policy, and responder-role handshakes belong to other layers.
final class WireGuardConformanceTests: XCTestCase {
    func testUnsolicitedResponsesCookiesAndDataCannotEstablishSession() throws {
        let context = try makeContext(established: false)
        for field in ["response", "cookie_reply", "received_transport"] {
            XCTAssertThrowsError(try context.peer.receive(context.vector.bytes(field)), field)
            XCTAssertFalse(context.peer.isEstablished, field)
        }
        // This initiation addresses the other fixture identity, so it cannot create responder state here.
        assertError(.authenticationFailed) {
            _ = try context.peer.receive(context.vector.bytes("initiation"))
        }
        XCTAssertNoThrow(try context.peer.initiateHandshake())
    }

    func testResponseWithValidPublicMacStillRejectsTamperedEncryptedPayload() throws {
        let context = try makeContext(established: false)
        _ = try context.peer.initiateHandshake()
        for offset in 44..<60 {
            var forged = try context.vector.bytes("response")
            forged[offset] ^= 1
            authenticateResponse(&forged, publicKey: context.peer.publicKey)
            assertError(.authenticationFailed) { _ = try context.peer.receive(forged) }
            XCTAssertFalse(context.peer.isEstablished)
        }
        XCTAssertEqual(try context.peer.receive(context.vector.bytes("response")), .handshakeComplete)
    }

    func testLowOrderResponseEphemeralWithValidPublicMacIsRejected() throws {
        let context = try makeContext(established: false)
        _ = try context.peer.initiateHandshake()
        var forged = try context.vector.bytes("response")
        forged.replaceSubrange(12..<44, with: repeatElement(UInt8(0), count: 32))
        authenticateResponse(&forged, publicKey: context.peer.publicKey)
        XCTAssertThrowsError(try context.peer.receive(forged))
        XCTAssertFalse(context.peer.isEstablished)
        XCTAssertEqual(try context.peer.receive(context.vector.bytes("response")), .handshakeComplete)
    }

    func testResponseReceiverReservedFieldsAndExtraBytesAreRejected() throws {
        let context = try makeContext(established: false)
        _ = try context.peer.initiateHandshake()
        let response = try context.vector.bytes("response")
        for offset in [1, 2, 3, 8] {
            var invalid = response
            invalid[offset] ^= 1
            assertError(.unexpectedMessage) { _ = try context.peer.receive(invalid) }
        }
        assertError(.invalidMessage) { _ = try context.peer.receive(response + Data([0])) }
        XCTAssertEqual(try context.peer.receive(response), .handshakeComplete)
    }

    func testDuplicateResponseCannotResetAnEstablishedSendCounter() throws {
        let context = try makeContext()
        XCTAssertEqual(counter(in: try context.peer.keepalive()), 0)
        assertError(.handshakeRequired) { _ = try context.peer.receive(context.vector.bytes("response")) }
        assertError(.handshakeRequired) { _ = try context.peer.receive(context.vector.bytes("cookie_reply")) }
        XCTAssertTrue(context.peer.isEstablished)
        XCTAssertEqual(counter(in: try context.peer.keepalive()), 1)
    }

    func testZeroPresharedKeyMatchesTheAbsentPresharedKeyWireFormat() throws {
        let context = try makeContext(established: false, presharedKey: Data(repeating: 0, count: 32))
        XCTAssertEqual(try context.peer.initiateHandshake(), try context.vector.bytes("initiation"))
        XCTAssertEqual(try context.peer.receive(context.vector.bytes("response")), .handshakeComplete)
        XCTAssertEqual(try context.peer.encrypt(context.vector.bytes("plaintext")), try context.vector.bytes("sent_transport"))
    }

    func testFreshRetryReplacesPendingHandshakeAndRejectsDelayedOldResponses() throws {
        let context = try makeContext(established: false)
        _ = try context.peer.initiateHandshake()
        context.inputs.time += 5
        let retry = try prepareFreshHandshake(context)
        XCTAssertEqual(try context.peer.initiateHandshake(), try retry.bytes("initiation"))
        assertError(.unexpectedMessage) { _ = try context.peer.receive(context.vector.bytes("response")) }
        XCTAssertFalse(context.peer.isEstablished)
        XCTAssertEqual(try context.peer.receive(retry.bytes("response")), .handshakeComplete)
    }

    func testInvalidFreshEphemeralDoesNotReplaceThePreviousPendingHandshake() throws {
        let context = try makeContext(established: false)
        _ = try context.peer.initiateHandshake()
        context.inputs.time += 5
        context.inputs.index += 1
        context.inputs.ephemeral = Data(repeating: 1, count: 31)
        assertError(.invalidKey) { _ = try context.peer.initiateHandshake() }
        XCTAssertEqual(try context.peer.receive(context.vector.bytes("response")), .handshakeComplete)
    }

    func testInvalidTimestampDoesNotConsumeTheInitiationBudget() throws {
        let context = try makeContext(established: false)
        let timestamp = context.inputs.timestamp
        context.inputs.timestamp = Data(repeating: 0, count: 11)
        assertError(.invalidTimestamp) { _ = try context.peer.initiateHandshake() }
        context.inputs.timestamp = timestamp
        XCTAssertEqual(try context.peer.initiateHandshake(), try context.vector.bytes("initiation"))
    }

    func testCookieReceiptCachesWithoutSendingOrBypassingRetryRateLimit() throws {
        let context = try makeContext(established: false)
        _ = try context.peer.initiateHandshake()
        let cookie = try context.vector.bytes("cookie_reply")
        XCTAssertEqual(try context.peer.receive(cookie), .cookieReceived)
        XCTAssertEqual(try context.peer.receive(cookie), .cookieReceived)
        context.inputs.time += 4.999
        assertError(.handshakeRateLimited) { _ = try context.peer.initiateHandshake() }
        context.inputs.time = 1_005
        let retry = try prepareFreshHandshake(context)
        XCTAssertEqual(try context.peer.initiateHandshake(), try retry.bytes("cookie_retry"))
    }

    func testCachedCookieExpiresAtTheRefreshBoundary() throws {
        for age: TimeInterval in [119.999, 120] {
            let context = try makeContext(established: false)
            _ = try context.peer.initiateHandshake()
            XCTAssertEqual(try context.peer.receive(context.vector.bytes("cookie_reply")), .cookieReceived)
            context.inputs.time += age
            let retry = try prepareFreshHandshake(context)
            let expected = age < 120 ? "cookie_retry" : "initiation"
            XCTAssertEqual(try context.peer.initiateHandshake(), try retry.bytes(expected), "cookie age \(age)")
        }
    }

    func testCookieChallengeIsBoundToTheLatestHandshakeIndexAndMac() throws {
        let context = try makeContext(established: false)
        _ = try context.peer.initiateHandshake()
        context.inputs.time += 5
        let retry = try prepareFreshHandshake(context)
        _ = try context.peer.initiateHandshake()
        let oldCookie = try context.vector.bytes("cookie_reply")
        assertError(.unexpectedMessage) { _ = try context.peer.receive(oldCookie) }
        var forged = oldCookie
        forged.replaceSubrange(4..<8, with: littleEndian(context.inputs.index))
        assertError(.authenticationFailed) { _ = try context.peer.receive(forged) }
        XCTAssertEqual(try context.peer.receive(retry.bytes("cookie_reply")), .cookieReceived)
        XCTAssertEqual(try context.peer.receive(retry.bytes("response")), .handshakeComplete)
    }

    func testMalformedCookieLengthIndexNonceAndTagPreservePendingHandshake() throws {
        let context = try makeContext(established: false)
        _ = try context.peer.initiateHandshake()
        let cookie = try context.vector.bytes("cookie_reply")
        for length in 0..<cookie.count {
            XCTAssertThrowsError(try context.peer.receive(Data(cookie.prefix(length))), "length \(length)")
        }
        assertError(.invalidMessage) { _ = try context.peer.receive(cookie + Data([0])) }
        for offset in [4, 8, 31, 32, 63] {
            var invalid = cookie
            invalid[offset] ^= 1
            XCTAssertThrowsError(try context.peer.receive(invalid), "offset \(offset)")
        }
        XCTAssertEqual(try context.peer.receive(context.vector.bytes("response")), .handshakeComplete)
    }

    func testCookieCannotReviveAnExpiredPendingHandshake() throws {
        let context = try makeContext(established: false)
        _ = try context.peer.initiateHandshake()
        context.inputs.time += 180
        assertError(.handshakeExpired) { _ = try context.peer.receive(context.vector.bytes("cookie_reply")) }
        XCTAssertFalse(context.peer.isEstablished)
    }

    func testTransportCounterReceiverAndTagTamperingDoNotConsumeAuthenticPacket() throws {
        let context = try makeContext()
        let incoming = try context.vector.bytes("received_transport")
        for offset in [4, 8, 16, incoming.count - 1] {
            var forged = incoming
            forged[offset] ^= 1
            XCTAssertThrowsError(try context.peer.receive(forged), "offset \(offset)")
        }
        XCTAssertEqual(try context.peer.receive(incoming), .packet(try context.vector.bytes("plaintext")))
        assertError(.replayedPacket) { _ = try context.peer.receive(incoming) }
    }

    func testFailedEncryptionDoesNotConsumeAnOutgoingNonce() throws {
        let context = try makeContext()
        assertError(.invalidPacket) { _ = try context.peer.encrypt(Data([0x45])) }
        XCTAssertEqual(try context.peer.encrypt(context.vector.bytes("plaintext")), try context.vector.bytes("sent_transport"))
    }

    func testOutgoingPacketsAreZeroPaddedWithoutChangingTheirIPLength() throws {
        let context = try makeContext()
        for length in [20, 31, 32, 33, 1_280] {
            let packet = ipv4Packet(length: length)
            let datagram = try context.peer.encrypt(packet)
            let paddedLength = (length + 15) / 16 * 16
            XCTAssertEqual(datagram.count, paddedLength + 32)
            let plaintext = try openTransport(datagram, key: context.vector.bytes("sending_key"))
            XCTAssertEqual(plaintext.prefix(length), packet)
            XCTAssertTrue(plaintext.dropFirst(length).allSatisfy { $0 == 0 })
        }
    }

    func testMaximumOutgoingPacketLeavesRoomForPaddingAndWireGuardOverhead() throws {
        let context = try makeContext()
        let maximum = try context.peer.encrypt(ipv4Packet(length: 65_472))
        XCTAssertLessThanOrEqual(maximum.count, 65_507)
        XCTAssertEqual(counter(in: maximum), 0)
        assertError(.invalidPacket) { _ = try context.peer.encrypt(self.ipv4Packet(length: 65_473)) }
        XCTAssertEqual(counter(in: try context.peer.keepalive()), 1)
    }

    func testIPv4OptionsAndTrailingZeroPayloadSurvivePaddingRemoval() throws {
        let context = try makeContext()
        var packet = ipv4Packet(length: 28)
        packet[0] = 0x46 // 24-byte header with four bytes of IP options.
        packet.replaceSubrange(24..<28, with: [0x12, 0x34, 0, 0])
        let padded = packet + Data(repeating: 0xab, count: 4)
        let incoming = try transport(context.vector, counter: 0, plaintext: padded)
        XCTAssertEqual(try context.peer.receive(incoming), .packet(packet))
    }

    func testIPv6EmptyPayloadAndInvalidDeclaredLengths() throws {
        let context = try makeContext()
        var packet = Data(repeating: 0, count: 40)
        packet[0] = 0x60
        packet[6] = 59
        packet[7] = 64
        XCTAssertEqual(try context.peer.receive(transport(context.vector, counter: 0, plaintext: packet)), .packet(packet))
        XCTAssertEqual(try context.peer.encrypt(packet).count, 80)
        // The padded plaintext is 48 bytes; declare a length beyond padding too.
        packet[5] = 9
        assertError(.invalidPacket) { _ = try context.peer.receive(self.transport(context.vector, counter: 1, plaintext: packet)) }
        assertError(.invalidPacket) { _ = try context.peer.encrypt(packet) }
    }

    func testAuthenticatedMalformedIPConsumesItsReplayCounter() throws {
        let context = try makeContext()
        let invalid = try transport(context.vector, counter: 7, plaintext: Data([0x70]))
        assertError(.invalidPacket) { _ = try context.peer.receive(invalid) }
        assertError(.replayedPacket) { _ = try context.peer.receive(invalid) }
    }

    func testAuthenticatedMalformedIPCannotBeDeliveredAsAnIPPacket() throws {
        let context = try makeContext()
        var badHeader = ipv4Packet(length: 20)
        badHeader[0] = 0x44
        var shortLength = ipv4Packet(length: 20)
        shortLength[3] = 19
        var oversized = ipv4Packet(length: 20)
        oversized[3] = 33
        let invalidPackets = [Data([0x45]), Data([0x70]), badHeader, shortLength, oversized, Data([0x60])]
        for (index, packet) in invalidPackets.enumerated() {
            assertError(.invalidPacket) {
                _ = try context.peer.receive(self.transport(context.vector, counter: UInt64(index), plaintext: packet))
            }
        }
        let valid = try context.vector.bytes("plaintext")
        XCTAssertEqual(try context.peer.receive(transport(context.vector, counter: 10, plaintext: valid)), .packet(valid))
    }

    func testOversizedDatagramIsRejectedBeforeReplayWindowChanges() throws {
        let context = try makeContext()
        var huge = try context.vector.bytes("received_transport")
        huge.append(Data(repeating: 0, count: 65_508 - huge.count))
        assertError(.invalidMessage) { _ = try context.peer.receive(huge) }
        XCTAssertEqual(try context.peer.receive(context.vector.bytes("received_transport")), .packet(try context.vector.bytes("plaintext")))
    }

    private final class Inputs {
        var time: TimeInterval = 1_000
        var index: UInt32
        var ephemeral: Data
        var timestamp: Data

        init(vector: Vector) throws {
            index = try vector.index()
            ephemeral = try vector.bytes("initiator_ephemeral")
            timestamp = try vector.bytes("timestamp")
        }
    }

    private struct Context {
        let peer: WireGuardPeer
        let inputs: Inputs
        let vector: Vector
    }

    private struct Vector {
        let fields: [String: Any]

        func bytes(_ field: String) throws -> Data {
            try WireGuardTestData.hexBytes(XCTUnwrap(fields[field] as? String))
        }

        func index() throws -> UInt32 {
            try XCTUnwrap(fields["initiator_index"] as? NSNumber).uint32Value
        }
    }

    private func makeContext(established: Bool = true, presharedKey: Data? = nil) throws -> Context {
        let fixtures = try WireGuardTestData.handshakeVectors()
        let vector = Vector(fields: try XCTUnwrap(fixtures.first))
        let inputs = try Inputs(vector: vector)
        let peer = try WireGuardPeer(
            privateKey: vector.bytes("initiator_private"), peerPublicKey: vector.bytes("responder_public"),
            presharedKey: presharedKey,
            ephemeralPrivateKey: { inputs.ephemeral }, senderIndex: { inputs.index },
            now: { inputs.time }, timestamp: { inputs.timestamp }
        )
        if established {
            _ = try peer.initiateHandshake()
            _ = try peer.receive(vector.bytes("response"))
        }
        return Context(peer: peer, inputs: inputs, vector: vector)
    }

    private func prepareFreshHandshake(_ context: Context) throws -> Vector {
        let retry = Vector(fields: try XCTUnwrap(context.vector.fields["rekey"] as? [String: Any]))
        context.inputs.index = try retry.index()
        context.inputs.ephemeral = try retry.bytes("initiator_ephemeral")
        context.inputs.timestamp = try retry.bytes("timestamp")
        return retry
    }

    private func authenticateResponse(_ response: inout Data, publicKey: Data) {
        // MAC1 is keyed with public information. An attacker can recompute it, so tests must reach AEAD verification.
        let key = WireGuardCrypto.hash(Data("mac1----".utf8) + publicKey)
        response.replaceSubrange(60..<76, with: WireGuardCrypto.mac(key: key, data: response.prefix(60)))
    }

    private func ipv4Packet(length: Int) -> Data {
        var packet = Data(repeating: 0xab, count: length)
        packet[0] = 0x45
        packet[2] = UInt8(truncatingIfNeeded: length >> 8)
        packet[3] = UInt8(truncatingIfNeeded: length)
        return packet
    }

    private func transport(_ vector: Vector, counter: UInt64, plaintext: Data) throws -> Data {
        let padded = plaintext + Data(repeating: 0, count: (16 - plaintext.count % 16) % 16)
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + littleEndian(counter))
        let sealed = try ChaChaPoly.seal(padded, using: SymmetricKey(data: vector.bytes("receiving_key")), nonce: nonce)
        return Data([4, 0, 0, 0]) + (try littleEndian(vector.index())) + littleEndian(counter) + sealed.ciphertext + sealed.tag
    }

    private func openTransport(_ datagram: Data, key: Data) throws -> Data {
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + datagram[8..<16])
        let sealed = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: datagram[16..<datagram.count - 16], tag: datagram.suffix(16))
        return try ChaChaPoly.open(sealed, using: SymmetricKey(data: key))
    }

    private func counter(in datagram: Data) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 | UInt64(datagram[8 + $1]) << ($1 * 8) }
    }

    private func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        Data((0..<MemoryLayout<T>.size).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    private func assertError(_ expected: WireGuardPeer.Error, file: StaticString = #filePath,
                             line: UInt = #line, _ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? WireGuardPeer.Error, expected, file: file, line: line)
        }
    }
}
