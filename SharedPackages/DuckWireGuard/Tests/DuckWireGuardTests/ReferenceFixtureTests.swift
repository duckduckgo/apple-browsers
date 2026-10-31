//
//  ReferenceFixtureTests.swift
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

final class ReferenceFixtureTests: XCTestCase {
    func testMatchesIndependentHandshakeAndTransportFixtures() throws {
        for fixture in try fixtures() {
            let peer = try makePeer(fixture)
            XCTAssertEqual(peer.publicKey, try bytes(fixture.initiatorPublic), fixture.name)
            XCTAssertEqual(try peer.initiateHandshake(), try bytes(fixture.initiation), fixture.name)
            XCTAssertEqual(try peer.receive(bytes(fixture.response)), .handshakeComplete, fixture.name)
            XCTAssertTrue(peer.isEstablished, fixture.name)
            XCTAssertEqual(try peer.encrypt(bytes(fixture.plaintext)), try bytes(fixture.sentTransport), fixture.name)
            let incoming = try bytes(fixture.receivedTransport)
            XCTAssertEqual(try peer.receive(incoming), .packet(try bytes(fixture.plaintext)), fixture.name)
            XCTAssertThrowsError(try peer.receive(incoming), fixture.name)
        }
    }

    func testUnauthenticatedHighCounterDoesNotAdvanceReplayWindow() throws {
        for fixture in try fixtures() {
            let peer = try makePeer(fixture)
            _ = try peer.initiateHandshake()
            _ = try peer.receive(bytes(fixture.response))
            let incoming = try bytes(fixture.receivedTransport)
            var forged = incoming
            // Counter bytes are not authenticated as AD, but changing them changes the AEAD nonce.
            forged.replaceSubrange(8..<16, with: repeatElement(UInt8(0x7f), count: 8))
            XCTAssertThrowsError(try peer.receive(forged), fixture.name)
            XCTAssertEqual(try peer.receive(incoming), .packet(try bytes(fixture.plaintext)), fixture.name)
        }
    }

    func testTamperedResponsePreservesPendingHandshake() throws {
        for fixture in try fixtures() {
            let peer = try makePeer(fixture)
            _ = try peer.initiateHandshake()
            let response = try bytes(fixture.response)
            var tampered = response
            tampered[44] ^= 1
            XCTAssertThrowsError(try peer.receive(tampered), fixture.name)
            XCTAssertFalse(peer.isEstablished, fixture.name)
            XCTAssertEqual(try peer.receive(response), .handshakeComplete, fixture.name)
        }
    }

    func testRejectsWrongPresharedKey() throws {
        let fixture = try XCTUnwrap(fixtures().first { $0.name == "with-psk" })
        let peer = try makePeer(fixture, presharedKey: Data(repeating: 0x66, count: 32))
        XCTAssertEqual(try peer.initiateHandshake(), try bytes(fixture.initiation))
        XCTAssertThrowsError(try peer.receive(bytes(fixture.response)))
        XCTAssertFalse(peer.isEstablished)
    }

    func testTruncatedResponsesAreRejectedWithoutTrapping() throws {
        let fixture = try XCTUnwrap(fixtures().first)
        let peer = try makePeer(fixture)
        _ = try peer.initiateHandshake()
        let response = try bytes(fixture.response)
        for length in 0..<response.count {
            XCTAssertThrowsError(try peer.receive(Data(response.prefix(length))), "length \(length)")
        }
        XCTAssertEqual(try peer.receive(response), .handshakeComplete)
    }

    func testAcceptsDatagramsWithNonzeroDataStartIndex() throws {
        let fixture = try XCTUnwrap(fixtures().first)
        let peer = try makePeer(fixture)
        _ = try peer.initiateHandshake()
        let response = try bytes(fixture.response)
        let wrapped = Data([0xaa, 0xbb, 0xcc]) + response
        XCTAssertEqual(try peer.receive(wrapped.dropFirst(3)), .handshakeComplete)
        let transport = Data([0xaa, 0xbb]) + (try bytes(fixture.receivedTransport))
        XCTAssertEqual(try peer.receive(transport.dropFirst(2)), .packet(try bytes(fixture.plaintext)))
    }

    private func makePeer(_ fixture: Fixture, presharedKey: Data? = nil) throws -> WireGuardPeer {
        let ephemeral = try bytes(fixture.initiatorEphemeral)
        let timestamp = try bytes(fixture.timestamp)
        return try WireGuardPeer(
            privateKey: bytes(fixture.initiatorPrivate),
            peerPublicKey: bytes(fixture.responderPublic),
            presharedKey: presharedKey ?? (fixture.name == "no-psk" ? nil : bytes(fixture.presharedKey)),
            ephemeralPrivateKey: { ephemeral },
            senderIndex: { fixture.initiatorIndex },
            now: { 1_000 },
            timestamp: { timestamp }
        )
    }

    private func fixtures() throws -> [Fixture] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([Fixture].self, from: WireGuardTestData.handshakeJSON())
    }

    private func bytes(_ hex: String) throws -> Data {
        try WireGuardTestData.hexBytes(hex)
    }

    private struct Fixture: Decodable {
        let name: String
        let initiatorPrivate: String
        let initiatorPublic: String
        let responderPublic: String
        let initiatorEphemeral: String
        let initiatorIndex: UInt32
        let timestamp: String
        let presharedKey: String
        let initiation: String
        let response: String
        let plaintext: String
        let sentTransport: String
        let receivedTransport: String
    }
}
