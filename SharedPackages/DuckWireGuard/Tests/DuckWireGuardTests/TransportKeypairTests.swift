//
//  TransportKeypairTests.swift
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

final class TransportKeypairTests: XCTestCase {
    func testReservationEncryptsIndependentVectorsForBothKeyDirections() throws {
        for vector in try WireGuardTestData.handshakeVectors() {
            for isInitiator in [true, false] {
                var keypair = try makeKeypair(vector, isInitiator: isInitiator)
                let snapshot = try keypair.reserve(bytes(vector, "plaintext"), paddingLength: 12, at: 1000)
                XCTAssertEqual(try snapshot.encrypt(), try bytes(vector, isInitiator ? "sent_transport" : "received_transport"))
                XCTAssertTrue(keypair.owns(snapshot))
            }
        }
    }

    func testReservationBindsTheInputAndPaddingBeforeWorkerEncryption() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        var keypair = try makeKeypair(vector)
        var packet = try bytes(vector, "plaintext")
        let snapshot = try keypair.reserve(packet, paddingLength: 1, at: 1000)
        packet[0] ^= 1
        let expected = try bytes(vector, "plaintext") + Data([0])
        try assertSnapshot(snapshot, counter: 0, plaintext: expected, vector: vector)
        XCTAssertEqual(try snapshot.encrypt(), try snapshot.encrypt())
    }

    func testDiscardedReservationsAndEmptyMessagesConsumeDistinctNonces() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        var keypair = try makeKeypair(vector)
        let packet = try bytes(vector, "plaintext")
        let first = try keypair.reserve(packet, paddingLength: 12, at: 1000)
        _ = try keypair.reserve(packet, paddingLength: 12, at: 1000)
        let empty = try keypair.reserve(Data(), paddingLength: 0, at: 1000)
        let fourth = try keypair.reserve(packet, paddingLength: 12, at: 1000)
        let padded = packet + Data(repeating: 0, count: 12)
        try assertSnapshot(first, counter: 0, plaintext: padded, vector: vector)
        try assertSnapshot(empty, counter: 2, plaintext: Data(), vector: vector)
        try assertSnapshot(fourth, counter: 3, plaintext: padded, vector: vector)
    }

    func testMessageRekeyThresholdAppliesAtTheSpecBoundaryForBothRoles() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        let threshold: UInt64 = 1 << 60
        for isInitiator in [true, false] {
            var keypair = try makeKeypair(vector, isInitiator: isInitiator, initialSendCounter: threshold - 1)
            XCTAssertFalse(keypair.needsMessageRekey)
            let before = try keypair.reserve(Data(), paddingLength: 0, at: 1000)
            XCTAssertTrue(keypair.needsMessageRekey)
            let after = try keypair.reserve(Data(), paddingLength: 0, at: 1000)
            try assertSnapshot(before, counter: threshold - 1, plaintext: Data(), vector: vector, isInitiator: isInitiator)
            try assertSnapshot(after, counter: threshold, plaintext: Data(), vector: vector, isInitiator: isInitiator)
        }
    }

    func testExhaustionPreservesTheLastReservedSnapshotAndDoesNotRecycleDiscardedNonces() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        let rejectAfterMessages = UInt64.max - 8192
        var keypair = try makeKeypair(vector, initialSendCounter: rejectAfterMessages - 2)
        _ = try keypair.reserve(Data(), paddingLength: 0, at: 1000)
        let last = try keypair.reserve(Data(), paddingLength: 0, at: 1000)
        for _ in 0..<3 {
            assertError(.counterExhausted) { _ = try keypair.reserve(Data(), paddingLength: 0, at: 1000) }
        }
        XCTAssertTrue(keypair.owns(last) && keypair.isWithinLifetime(at: 1000))
        try assertSnapshot(last, counter: rejectAfterMessages - 1, plaintext: Data(), vector: vector)
    }

    func testRejectedMessageCountsAndMaximumCounterRefuseWithoutOverflow() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        for isInitiator in [true, false] {
            for counter in [UInt64.max - 8192, UInt64.max] {
                var keypair = try makeKeypair(vector, isInitiator: isInitiator, initialSendCounter: counter)
                let datagram = try authenticatedDatagram(vector, counter: counter, plaintext: Data(), isInitiator: isInitiator)
                let incoming = try transport(datagram)
                var forged = datagram
                forged[forged.count - 1] ^= 1
                for _ in 0..<3 {
                    assertError(.counterExhausted) { _ = try keypair.reserve(Data(), paddingLength: 0, at: 1000) }
                    assertError(.counterExhausted) { _ = try keypair.decrypt(incoming, at: 1000) }
                    assertError(.counterExhausted) { _ = try keypair.decrypt(transport(forged), at: 1000) }
                }
            }
            var keypair = try makeKeypair(vector, isInitiator: isInitiator)
            let lastLegal = UInt64.max - 8193
            let incoming = try transport(authenticatedDatagram(vector, counter: lastLegal, plaintext: Data([0x42]), isInitiator: isInitiator))
            XCTAssertEqual(try keypair.decrypt(incoming, at: 1000), Data([0x42]))
        }
    }

    func testSnapshotOwnershipAndAgeRemainIndependentOfCounterExhaustion() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        var keypair = try makeKeypair(vector, initialSendCounter: UInt64.max - 8193)
        let otherKeypair = try makeKeypair(vector)
        let snapshot = try keypair.reserve(Data(), paddingLength: 0, at: 1179.999)
        XCTAssertTrue(keypair.owns(snapshot))
        XCTAssertFalse(otherKeypair.owns(snapshot))
        XCTAssertTrue(keypair.isWithinLifetime(at: 1179.999))
        XCTAssertFalse(keypair.isWithinLifetime(at: 1180))
        assertError(.counterExhausted) { _ = try keypair.reserve(Data(), paddingLength: 0, at: 1179.999) }
        assertError(.sessionExpired) { _ = try keypair.reserve(Data(), paddingLength: 0, at: 1180) }
        let incoming = try transport(authenticatedDatagram(vector, counter: UInt64.max, plaintext: Data()))
        assertError(.sessionExpired) { _ = try keypair.decrypt(incoming, at: 1180) }
    }

    func testAuthenticatedFixturePayloadsAndReplayChecksWorkForBothKeyDirections() throws {
        for vector in try WireGuardTestData.handshakeVectors() {
            for isInitiator in [true, false] {
                var keypair = try makeKeypair(vector, isInitiator: isInitiator)
                let incoming = try transport(bytes(vector, isInitiator ? "received_transport" : "sent_transport"))
                let padded = try bytes(vector, "plaintext") + Data(repeating: 0, count: 12)
                XCTAssertEqual(try keypair.decrypt(incoming, at: 1179.999), padded)
                assertError(.replayedPacket) { _ = try keypair.decrypt(incoming, at: 1179.999) }
                assertError(.sessionExpired) { _ = try keypair.decrypt(incoming, at: 1180) }
            }
        }
    }

    func testAuthenticationPrecedesReplayAndForgedHighCountersCannotAdvanceTheWindow() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        var keypair = try makeKeypair(vector)
        let valid = try bytes(vector, "received_transport")
        let padded = try bytes(vector, "plaintext") + Data(repeating: 0, count: 12)
        XCTAssertEqual(try keypair.decrypt(transport(valid), at: 1000), padded)
        var badTag = valid
        badTag[badTag.count - 1] ^= 1
        assertError(.authenticationFailed) { _ = try keypair.decrypt(transport(badTag), at: 1000) }
        var highCounter = try bytes(vector, "received_transport_next")
        var forgedCounter = (UInt64(1) << 32).littleEndian
        highCounter.replaceSubrange(8..<16, with: withUnsafeBytes(of: &forgedCounter) { Data($0) })
        assertError(.authenticationFailed) { _ = try keypair.decrypt(transport(highCounter), at: 1000) }
        let next = try transport(bytes(vector, "received_transport_next"))
        XCTAssertEqual(try keypair.decrypt(next, at: 1000), padded)
        assertError(.replayedPacket) { _ = try keypair.decrypt(transport(valid), at: 1000) }
    }

    func testFreshKeypairsMaintainIndependentReplayHistoryEvenWithIdenticalKeys() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        var first = try makeKeypair(vector)
        var second = try makeKeypair(vector)
        let incoming = try transport(bytes(vector, "received_transport"))
        let expected = try bytes(vector, "plaintext") + Data(repeating: 0, count: 12)
        XCTAssertEqual(try first.decrypt(incoming, at: 1000), expected)
        XCTAssertEqual(try second.decrypt(incoming, at: 1000), expected)
        assertError(.replayedPacket) { _ = try first.decrypt(incoming, at: 1000) }
        assertError(.replayedPacket) { _ = try second.decrypt(incoming, at: 1000) }
    }

    func testAuthenticatedReorderingAcceptsTheInclusiveReplayBoundary() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        var keypair = try makeKeypair(vector)
        let payload = Data([0x42])
        let highest = try transport(authenticatedDatagram(vector, counter: 10_000, plaintext: payload))
        XCTAssertEqual(try keypair.decrypt(highest, at: 1000), payload)
        let oldest = try transport(authenticatedDatagram(vector, counter: 1872, plaintext: payload))
        XCTAssertEqual(try keypair.decrypt(oldest, at: 1000), payload)
        let outside = try transport(authenticatedDatagram(vector, counter: 1871, plaintext: payload))
        assertError(.replayedPacket) { _ = try keypair.decrypt(outside, at: 1000) }
        assertError(.replayedPacket) { _ = try keypair.decrypt(oldest, at: 1000) }
    }

    func testAuthenticatedMalformedIPAndEmptyPayloadsAreReturnedWithoutIPPolicy() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        var keypair = try makeKeypair(vector)
        let malformedIP = Data([0x10])
        let incoming = try transport(authenticatedDatagram(vector, counter: 0, plaintext: malformedIP))
        XCTAssertEqual(try keypair.decrypt(incoming, at: 1000), malformedIP)
        assertError(.replayedPacket) { _ = try keypair.decrypt(incoming, at: 1000) }
        let empty = try transport(authenticatedDatagram(vector, counter: 1, plaintext: Data()))
        XCTAssertEqual(try keypair.decrypt(empty, at: 1000), Data())
    }

    private func makeKeypair(_ vector: [String: Any], isInitiator: Bool = true, initialSendCounter: UInt64 = 0) throws -> WireGuardPeer.TransportKeypair {
        try WireGuardPeer.TransportKeypair(
            localIndex: index(vector, isInitiator ? "initiator_index" : "responder_index"),
            remoteIndex: index(vector, isInitiator ? "responder_index" : "initiator_index"),
            sendKey: bytes(vector, isInitiator ? "sending_key" : "receiving_key"),
            receiveKey: bytes(vector, isInitiator ? "receiving_key" : "sending_key"),
            created: 1000, isInitiator: isInitiator, initialSendCounter: initialSendCounter
        )
    }

    private func assertSnapshot(_ snapshot: WireGuardPeer.PreparedPacket, counter: UInt64, plaintext: Data, vector: [String: Any],
                                isInitiator: Bool = true, file: StaticString = #filePath, line: UInt = #line) throws {
        let datagram = try snapshot.encrypt()
        let reference = try bytes(vector, isInitiator ? "sent_transport" : "received_transport")
        XCTAssertEqual(datagram.prefix(8), reference.prefix(8), file: file, line: line)
        let counterBytes = withUnsafeBytes(of: counter.littleEndian) { Data($0) }
        XCTAssertEqual(datagram[8..<16], counterBytes, file: file, line: line)
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + counterBytes)
        let box = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: datagram[16..<(datagram.count - 16)], tag: datagram.suffix(16))
        let key = try bytes(vector, isInitiator ? "sending_key" : "receiving_key")
        XCTAssertEqual(try ChaChaPoly.open(box, using: SymmetricKey(data: key)), plaintext, file: file, line: line)
    }

    private func authenticatedDatagram(_ vector: [String: Any], counter: UInt64, plaintext: Data, isInitiator: Bool = true) throws -> Data {
        let receiver = try index(vector, isInitiator ? "initiator_index" : "responder_index")
        let receiverBytes = withUnsafeBytes(of: receiver.littleEndian) { Data($0) }
        let counterBytes = withUnsafeBytes(of: counter.littleEndian) { Data($0) }
        let nonce = try ChaChaPoly.Nonce(data: Data(repeating: 0, count: 4) + counterBytes)
        let key = SymmetricKey(data: try bytes(vector, isInitiator ? "receiving_key" : "sending_key"))
        let sealed = try ChaChaPoly.seal(plaintext, using: key, nonce: nonce)
        return Data([4, 0, 0, 0]) + receiverBytes + counterBytes + sealed.ciphertext + sealed.tag
    }

    private func transport(_ datagram: Data) throws -> WireGuardMessage.Transport {
        guard case .transport(let message) = try WireGuardMessage.decode(datagram) else {
            return try XCTUnwrap(nil, "Expected transport framing")
        }
        return message
    }

    private func bytes(_ vector: [String: Any], _ key: String) throws -> Data {
        try WireGuardTestData.hexBytes(XCTUnwrap(vector[key] as? String))
    }

    private func index(_ vector: [String: Any], _ key: String) throws -> UInt32 {
        try XCTUnwrap(vector[key] as? UInt32)
    }

    private func assertError(_ expected: WireGuardPeer.Error, file: StaticString = #filePath, line: UInt = #line,
                             _ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, expected, file: file, line: line)
        }
    }
}
