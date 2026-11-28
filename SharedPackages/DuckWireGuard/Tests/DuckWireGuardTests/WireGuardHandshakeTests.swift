//
//  WireGuardHandshakeTests.swift
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

final class WireGuardHandshakeTests: XCTestCase {
    func testInitiatorPayloadAndTransportKeysMatchIndependentVectorsWithAndWithoutPSK() throws {
        for vector in try WireGuardTestData.handshakeVectors() {
            let handshake = try makeHandshake(vector, isInitiator: true)
            XCTAssertEqual(handshake.publicKey, try bytes(vector, "initiator_public"))
            XCTAssertEqual(handshake.peerPublicKey, try bytes(vector, "responder_public"))
            let initiation = try initiate(vector, using: handshake)
            XCTAssertEqual(initiation.payload, try bytes(vector, "initiation")[8..<116])
            let keys = try complete(bytes(vector, "response"), transcript: initiation.transcript, using: handshake)
            try assertKeys(keys, match: vector, isInitiator: true)
        }
    }

    func testResponderTimestampPayloadAndTransportKeysMatchIndependentVectorsWithAndWithoutPSK() throws {
        for vector in try WireGuardTestData.handshakeVectors() {
            let handshake = try makeHandshake(vector, isInitiator: false)
            let incoming = try consume(bytes(vector, "initiation"), using: handshake)
            XCTAssertEqual(incoming.timestamp, try bytes(vector, "timestamp"))
            let response = try handshake.respond(to: incoming, ephemeralPrivateKey: bytes(vector, "responder_ephemeral"))
            XCTAssertEqual(response.payload, try bytes(vector, "response")[12..<60])
            try assertKeys(response.transportKeys(), match: vector, isInitiator: false)
        }
    }

    func testAbsentAndExplicitZeroPSKMatchIndependentResponseAndKeys() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first { $0["name"] as? String == "no-psk" })
        let presharedKeys: [Data?] = [nil, try bytes(vector, "preshared_key")]
        for presharedKey in presharedKeys {
            let initiator = try makeHandshake(vector, isInitiator: true, presharedKey: presharedKey)
            let responder = try makeHandshake(vector, isInitiator: false, presharedKey: presharedKey)
            let initiation = try initiate(vector, using: initiator)
            let incoming = try consume(bytes(vector, "initiation"), using: responder)
            let response = try responder.respond(to: incoming, ephemeralPrivateKey: bytes(vector, "responder_ephemeral"))
            XCTAssertEqual(response.payload, try bytes(vector, "response")[12..<60])
            try assertKeys(response.transportKeys(), match: vector, isInitiator: false)
            try assertKeys(complete(bytes(vector, "response"), transcript: initiation.transcript, using: initiator), match: vector, isInitiator: true)
        }
    }

    func testInitiationMustAuthenticateTheConfiguredInitiatorIdentity() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        let responder = try WireGuardHandshake(
            privateKey: bytes(vector, "responder_private"), peerPublicKey: bytes(vector, "responder_public"), presharedKey: nil
        )
        XCTAssertThrowsError(try consume(bytes(vector, "initiation"), using: responder)) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, .authenticationFailed)
        }
    }

    func testResponseMustAuthenticateTheConfiguredResponderIdentity() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        let initiator = try WireGuardHandshake(
            privateKey: bytes(vector, "initiator_private"), peerPublicKey: bytes(vector, "initiator_public"), presharedKey: nil
        )
        let initiation = try initiate(vector, using: initiator)
        XCTAssertThrowsError(try complete(bytes(vector, "response"), transcript: initiation.transcript, using: initiator)) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, .authenticationFailed)
        }
    }

    func testWrongInitiatorPSKPreservesFirstMessageButCannotAuthenticateResponse() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first { $0["name"] as? String == "with-psk" })
        let initiator = try makeHandshake(vector, isInitiator: true, presharedKey: Data(repeating: 0x66, count: 32))
        let initiation = try initiate(vector, using: initiator)
        // IKpsk2 mixes the PSK in the response, not the initial message.
        XCTAssertEqual(initiation.payload, try bytes(vector, "initiation")[8..<116])
        XCTAssertThrowsError(try complete(bytes(vector, "response"), transcript: initiation.transcript, using: initiator)) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, .authenticationFailed)
        }
    }

    func testWrongResponderPSKAllowsInitiationAuthenticationButItsResponseIsRejected() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first { $0["name"] as? String == "with-psk" })
        let responder = try makeHandshake(vector, isInitiator: false, presharedKey: Data(repeating: 0x66, count: 32))
        let incoming = try consume(bytes(vector, "initiation"), using: responder)
        XCTAssertEqual(incoming.timestamp, try bytes(vector, "timestamp"))
        let response = try responder.respond(to: incoming, ephemeralPrivateKey: bytes(vector, "responder_ephemeral"))
        XCTAssertNotEqual(response.payload, try bytes(vector, "response")[12..<60])
        XCTAssertNotEqual(response.transportKeys().sendKey, try bytes(vector, "receiving_key"))
        XCTAssertNotEqual(response.transportKeys().receiveKey, try bytes(vector, "sending_key"))
        let initiator = try makeHandshake(vector, isInitiator: true)
        let initiation = try initiate(vector, using: initiator)
        XCTAssertThrowsError(try initiator.complete(
            initiation.transcript, ephemeral: response.payload[0..<32], encryptedEmpty: response.payload[32..<48]
        )) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, .authenticationFailed)
        }
    }

    func testAlteredInitiatorEphemeralStaticAndTimestampCannotAuthenticate() throws {
        for vector in try WireGuardTestData.handshakeVectors() {
            let responder = try makeHandshake(vector, isInitiator: false)
            let initiation = try bytes(vector, "initiation")
            for offset in [8, 39, 40, 87, 88, 115] {
                var altered = initiation
                altered[offset] ^= 1
                XCTAssertThrowsError(try consume(altered, using: responder), "offset \(offset)")
            }
            XCTAssertEqual(try consume(initiation, using: responder).timestamp, try bytes(vector, "timestamp"))
        }
    }

    func testAlteredResponseCannotConsumeTheTranscriptOrPreventValidCompletion() throws {
        for vector in try WireGuardTestData.handshakeVectors() {
            let initiator = try makeHandshake(vector, isInitiator: true)
            let initiation = try initiate(vector, using: initiator)
            let response = try bytes(vector, "response")
            for offset in [12, 43] + Array(44..<60) {
                var altered = response
                altered[offset] ^= 1
                XCTAssertThrowsError(try complete(altered, transcript: initiation.transcript, using: initiator), "offset \(offset)")
                try assertKeys(complete(response, transcript: initiation.transcript, using: initiator), match: vector, isInitiator: true)
            }
        }
    }

    func testIndependentAttemptsCannotAuthenticateEachOthersResponses() throws {
        for vector in try WireGuardTestData.handshakeVectors() {
            let rekey = try XCTUnwrap(vector["rekey"] as? [String: Any])
            let initiator = try makeHandshake(vector, isInitiator: true)
            let original = try initiate(vector, using: initiator)
            let next = try initiate(rekey, using: initiator)
            XCTAssertThrowsError(try complete(bytes(rekey, "response"), transcript: original.transcript, using: initiator))
            XCTAssertThrowsError(try complete(bytes(vector, "response"), transcript: next.transcript, using: initiator))
            try assertKeys(complete(bytes(vector, "response"), transcript: original.transcript, using: initiator), match: vector, isInitiator: true)
            try assertKeys(complete(bytes(rekey, "response"), transcript: next.transcript, using: initiator), match: rekey, isInitiator: true)
        }
    }

    func testInvalidStaticKeyLengthsPSKLengthsAndLowOrderPeerKeysAreRejected() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        let privateKey = try bytes(vector, "initiator_private")
        let publicKey = try bytes(vector, "responder_public")
        for length in [0, 31, 33] {
            let invalid = Data(repeating: 0x42, count: length)
            let inputs: [(Data, Data, Data?)] = [(invalid, publicKey, nil), (privateKey, invalid, nil), (privateKey, publicKey, invalid)]
            for (local, remote, psk) in inputs {
                XCTAssertThrowsError(try WireGuardHandshake(privateKey: local, peerPublicKey: remote, presharedKey: psk)) {
                    XCTAssertEqual($0 as? WireGuardPeer.Error, .invalidKey)
                }
            }
        }
        for lowOrder in [Data(repeating: 0, count: 32), Data([1]) + Data(repeating: 0, count: 31)] {
            XCTAssertThrowsError(try WireGuardHandshake(privateKey: privateKey, peerPublicKey: lowOrder, presharedKey: nil)) {
                XCTAssertEqual($0 as? WireGuardPeer.Error, .invalidKey)
            }
        }
    }

    func testInvalidEphemeralKeysCannotYieldHandshakeCandidatesOrTransportKeys() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        let initiator = try makeHandshake(vector, isInitiator: true)
        let responder = try makeHandshake(vector, isInitiator: false)
        let initiation = try initiate(vector, using: initiator)
        let message = try bytes(vector, "initiation")
        let response = try bytes(vector, "response")
        let incoming = try consume(message, using: responder)
        let invalidLengths = [0, 31, 33].map { Data(repeating: 0x42, count: $0) }
        for invalid in invalidLengths {
            XCTAssertThrowsError(try initiator.initiate(ephemeralPrivateKey: invalid, timestamp: bytes(vector, "timestamp"))) {
                XCTAssertEqual($0 as? WireGuardPeer.Error, .invalidKey)
            }
            XCTAssertThrowsError(try responder.respond(to: incoming, ephemeralPrivateKey: invalid))
        }
        let lowOrder = [Data(repeating: 0, count: 32), Data([1]) + Data(repeating: 0, count: 31)]
        for invalid in invalidLengths + lowOrder {
            XCTAssertThrowsError(try responder.consumeInitiation(ephemeral: invalid, encryptedStatic: message[40..<88], encryptedTimestamp: message[88..<116]))
            XCTAssertThrowsError(try initiator.complete(initiation.transcript, ephemeral: invalid, encryptedEmpty: response[44..<60]))
        }
        try assertKeys(complete(response, transcript: initiation.transcript, using: initiator), match: vector, isInitiator: true)
        let recovered = try responder.respond(to: incoming, ephemeralPrivateKey: bytes(vector, "responder_ephemeral"))
        XCTAssertEqual(recovered.payload, response[12..<60])
    }

    private func makeHandshake(_ vector: [String: Any], isInitiator: Bool, presharedKey: Data? = nil) throws -> WireGuardHandshake {
        let fixturePSK = vector["name"] as? String == "no-psk" ? nil : try bytes(vector, "preshared_key")
        return try WireGuardHandshake(
            privateKey: bytes(vector, isInitiator ? "initiator_private" : "responder_private"),
            peerPublicKey: bytes(vector, isInitiator ? "responder_public" : "initiator_public"),
            presharedKey: presharedKey ?? fixturePSK
        )
    }

    private func initiate(_ vector: [String: Any], using handshake: WireGuardHandshake) throws -> (payload: Data, transcript: WireGuardHandshake.InitiatorTranscript) {
        try handshake.initiate(ephemeralPrivateKey: bytes(vector, "initiator_ephemeral"), timestamp: bytes(vector, "timestamp"))
    }

    private func consume(_ message: Data, using handshake: WireGuardHandshake) throws -> WireGuardHandshake.VerifiedInitiation {
        try handshake.consumeInitiation(ephemeral: message[8..<40], encryptedStatic: message[40..<88], encryptedTimestamp: message[88..<116])
    }

    private func complete(_ response: Data, transcript: WireGuardHandshake.InitiatorTranscript, using handshake: WireGuardHandshake) throws -> WireGuardHandshake.TransportKeys {
        try handshake.complete(transcript, ephemeral: response[12..<44], encryptedEmpty: response[44..<60])
    }

    private func assertKeys(_ keys: WireGuardHandshake.TransportKeys, match vector: [String: Any], isInitiator: Bool,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(keys.sendKey, try bytes(vector, isInitiator ? "sending_key" : "receiving_key"), file: file, line: line)
        XCTAssertEqual(keys.receiveKey, try bytes(vector, isInitiator ? "receiving_key" : "sending_key"), file: file, line: line)
    }

    private func bytes(_ vector: [String: Any], _ key: String) throws -> Data {
        try WireGuardTestData.hexBytes(XCTUnwrap(vector[key] as? String))
    }
}
