//
//  WireGuardMessageTests.swift
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

final class WireGuardMessageTests: XCTestCase {
    func testInitiationFieldsAndMAC1InputMatchIndependentVectors() throws {
        for vector in try vectors() {
            let datagram = try bytes(vector, "initiation")
            guard case .initiation(let message) = try WireGuardMessage.decode(datagram) else { return XCTFail("Expected initiation") }
            XCTAssertEqual(message.senderIndex, try index(vector, "initiator_index"))
            XCTAssertEqual(message.ephemeral, datagram[8..<40])
            XCTAssertEqual(message.encryptedStatic, datagram[40..<88])
            XCTAssertEqual(message.encryptedTimestamp, datagram[88..<116])
            XCTAssertEqual(message.mac1Input, datagram.prefix(116))
            XCTAssertEqual(message.mac1, datagram[116..<132])
        }
    }

    func testResponseFieldsAndMAC1InputMatchIndependentVectors() throws {
        for vector in try vectors() {
            let datagram = try bytes(vector, "response")
            guard case .response(let message) = try WireGuardMessage.decode(datagram) else { return XCTFail("Expected response") }
            XCTAssertEqual(message.senderIndex, try index(vector, "responder_index"))
            XCTAssertEqual(message.receiverIndex, try index(vector, "initiator_index"))
            XCTAssertEqual(message.ephemeral, datagram[12..<44])
            XCTAssertEqual(message.encryptedEmpty, datagram[44..<60])
            XCTAssertEqual(message.mac1Input, datagram.prefix(60))
            XCTAssertEqual(message.mac1, datagram[60..<76])
        }
    }

    func testCookieReplyFieldsMatchIndependentVectors() throws {
        for vector in try vectors() {
            let datagram = try bytes(vector, "cookie_reply")
            guard case .cookieReply(let message) = try WireGuardMessage.decode(datagram) else { return XCTFail("Expected cookie reply") }
            XCTAssertEqual(message.receiverIndex, try index(vector, "initiator_index"))
            XCTAssertEqual(message.nonce, Data(repeating: 0x88, count: 24))
            XCTAssertEqual(message.ciphertext, datagram[32..<64])
        }
    }

    func testTransportFieldsMatchIndependentVectorsInBothDirections() throws {
        for vector in try vectors() {
            for key in ["sent_transport", "received_transport", "received_transport_next"] {
                let datagram = try bytes(vector, key)
                guard case .transport(let message) = try WireGuardMessage.decode(datagram) else { return XCTFail("Expected transport") }
                XCTAssertEqual(message.receiverIndex, try index(vector, key == "sent_transport" ? "responder_index" : "initiator_index"))
                XCTAssertEqual(message.counter, key == "received_transport_next" ? 1 : 0)
                XCTAssertEqual(message.ciphertext, datagram.dropFirst(16))
            }
        }
    }

    func testHandshakeBodyEncodersMatchIndependentVectorsIncludingSlicedPayloads() throws {
        for vector in try vectors() {
            let initiation = try bytes(vector, "initiation")
            let response = try bytes(vector, "response")
            XCTAssertEqual(
                WireGuardMessage.initiationBody(senderIndex: try index(vector, "initiator_index"), payload: initiation[8..<116]),
                initiation.prefix(116)
            )
            XCTAssertEqual(
                WireGuardMessage.responseBody(senderIndex: try index(vector, "responder_index"), receiverIndex: try index(vector, "initiator_index"), payload: response[12..<60]),
                response.prefix(60)
            )
        }
    }

    func testTransportEncoderMatchesIndependentVectors() throws {
        for vector in try vectors() {
            for key in ["sent_transport", "received_transport", "received_transport_next"] {
                let datagram = try bytes(vector, key)
                let encoded = WireGuardMessage.transportDatagram(
                    receiverIndex: try index(vector, key == "sent_transport" ? "responder_index" : "initiator_index"),
                    counter: key == "received_transport_next" ? 1 : 0,
                    ciphertext: datagram.dropFirst(16)
                )
                XCTAssertEqual(encoded, datagram)
            }
        }
    }

    func testTransportUsesLittleEndianAndPreservesTheFullCounterWithoutApplyingKeyLimits() throws {
        let header = try WireGuardTestData.hexBytes("04000000d4c3b2a1")
        let ciphertext = Data(repeating: 0xaa, count: 16)
        let cases: [(UInt64, String)] = [(0x0102030405060708, "0807060504030201"), (UInt64.max, "ffffffffffffffff")]
        for (counter, counterHex) in cases {
            let expected = header + (try WireGuardTestData.hexBytes(counterHex)) + ciphertext
            XCTAssertEqual(WireGuardMessage.transportDatagram(receiverIndex: 0xa1b2c3d4, counter: counter, ciphertext: ciphertext), expected)
            guard case .transport(let message) = try WireGuardMessage.decode(expected) else { return XCTFail("Expected transport") }
            XCTAssertEqual(message.receiverIndex, 0xa1b2c3d4)
            XCTAssertEqual(message.counter, counter)
            XCTAssertEqual(message.ciphertext, ciphertext)
        }
    }

    func testIncompleteTypeWordIsInvalidMessage() {
        for length in 0..<4 {
            let bytes = Data([1, 0, 0, 0].prefix(length))
            assertDecodingError(.invalidMessage, for: bytes)
        }
    }

    func testUnknownTypesAndNonzeroReservedBytesAreUnexpectedBeforeLengthValidation() throws {
        let vector = try XCTUnwrap(vectors().first)
        for key in ["initiation", "response", "cookie_reply", "sent_transport"] {
            let datagram = try bytes(vector, key)
            for offset in 1...3 {
                var altered = datagram
                altered[offset] = 1
                assertDecodingError(.unexpectedMessage, for: altered)
                assertDecodingError(.unexpectedMessage, for: Data(altered.prefix(4)))
            }
        }
        for unknown in [UInt8(0), 5, 255] {
            assertDecodingError(.unexpectedMessage, for: Data([unknown, 0, 0, 0]))
        }
    }

    func testFixedSizeMessagesRejectEveryTruncationAndTrailingBytes() throws {
        let vector = try XCTUnwrap(vectors().first)
        for key in ["initiation", "response", "cookie_reply"] {
            let datagram = try bytes(vector, key)
            for length in 0..<datagram.count {
                assertDecodingError(.invalidMessage, for: Data(datagram.prefix(length)))
            }
            assertDecodingError(.invalidMessage, for: datagram + Data([0]))
            XCTAssertNoThrow(try WireGuardMessage.decode(datagram))
        }
    }

    func testTransportLengthBoundsIncludeAnEmptyAuthenticatedPayloadAndMaximumUDPDatagram() throws {
        for length in [32, 65_507] {
            let datagram = Data([4, 0, 0, 0]) + Data(repeating: 0, count: length - 4)
            guard case .transport(let message) = try WireGuardMessage.decode(datagram) else { return XCTFail("Expected transport") }
            XCTAssertEqual(message.ciphertext.count, length - 16)
        }
        for length in [4, 16, 31, 65_508] {
            let datagram = Data([4, 0, 0, 0]) + Data(repeating: 0, count: length - 4)
            assertDecodingError(.invalidMessage, for: datagram)
        }
    }

    func testEveryMessageKindAcceptsNonzeroDataStartIndices() throws {
        let vector = try XCTUnwrap(vectors().first)
        for key in ["initiation", "response", "cookie_reply", "received_transport_next"] {
            let original = try bytes(vector, key)
            let sliced = (Data([0xaa, 0xbb, 0xcc]) + original).dropFirst(3)
            XCTAssertEqual(sliced.startIndex, 3)
            switch try WireGuardMessage.decode(sliced) {
            case .initiation(let message):
                XCTAssertEqual(message.senderIndex, try index(vector, "initiator_index"))
                XCTAssertEqual(message.ephemeral, original[8..<40])
                XCTAssertEqual(message.mac1Input, original.prefix(116))
                XCTAssertEqual(message.mac1, original[116..<132])
            case .response(let message):
                XCTAssertEqual(message.senderIndex, try index(vector, "responder_index"))
                XCTAssertEqual(message.receiverIndex, try index(vector, "initiator_index"))
                XCTAssertEqual(message.encryptedEmpty, original[44..<60])
                XCTAssertEqual(message.mac1Input, original.prefix(60))
            case .cookieReply(let message):
                XCTAssertEqual(message.receiverIndex, try index(vector, "initiator_index"))
                XCTAssertEqual(message.nonce, Data(repeating: 0x88, count: 24))
                XCTAssertEqual(message.ciphertext, original[32..<64])
            case .transport(let message):
                XCTAssertEqual(message.receiverIndex, try index(vector, "initiator_index"))
                XCTAssertEqual(message.counter, 1)
                XCTAssertEqual(message.ciphertext, original.dropFirst(16))
            }
        }
    }

    func testFramingDoesNotAuthenticatePayloadsOrRequireNonzeroPeerIndices() {
        for (type, length) in [(UInt8(1), 148), (2, 92), (3, 64), (4, 32)] {
            let datagram = Data([type, 0, 0, 0]) + Data(repeating: 0, count: length - 4)
            XCTAssertNoThrow(try WireGuardMessage.decode(datagram))
        }
    }

    private func vectors() throws -> [[String: Any]] {
        try WireGuardTestData.handshakeVectors().flatMap { vector in
            [vector, try XCTUnwrap(vector["rekey"] as? [String: Any])]
        }
    }

    private func bytes(_ vector: [String: Any], _ key: String) throws -> Data {
        try WireGuardTestData.hexBytes(XCTUnwrap(vector[key] as? String))
    }

    private func index(_ vector: [String: Any], _ key: String) throws -> UInt32 {
        try XCTUnwrap(vector[key] as? UInt32)
    }

    private func assertDecodingError(_ expected: WireGuardPeer.Error, for data: Data, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try WireGuardMessage.decode(data), file: file, line: line) {
            XCTAssertEqual($0 as? WireGuardPeer.Error, expected, file: file, line: line)
        }
    }
}
