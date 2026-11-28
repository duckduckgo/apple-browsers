//
//  WireGuardMessage.swift
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

/// Validates framing only; authentication and protocol state remain the peer's responsibility.
/// Views retain one normalized datagram so parsing does not eagerly copy payload fields.
enum WireGuardMessage {
    case initiation(Initiation)
    case response(Response)
    case cookieReply(CookieReply)
    case transport(Transport)

    private typealias Failure = WireGuardPeer.Error

    // Type includes the three reserved zero bytes: [WireGuard §5.4.2–5.4.7](https://www.wireguard.com/papers/wireguard.pdf#page=10).
    private static let messageTypeLength = 4
    private static let initiationMessageType: UInt32 = 1
    private static let responseMessageType: UInt32 = 2
    private static let cookieMessageType: UInt32 = 3
    private static let transportMessageType: UInt32 = 4

    // Initiation layout: [WireGuard §5.4.2](https://www.wireguard.com/papers/wireguard.pdf#page=10).
    private static let initiationMessageLength = 148
    private static let initiationSenderIndexOffset = 4
    private static let initiationEphemeralRange = 8..<40
    private static let initiationStaticRange = 40..<88
    private static let initiationTimestampRange = 88..<116
    private static let initiationMac1Range = 116..<132

    // Response layout: [WireGuard §5.4.3](https://www.wireguard.com/papers/wireguard.pdf#page=11).
    private static let responseMessageLength = 92
    private static let responseSenderIndexOffset = 4
    private static let responseReceiverIndexOffset = 8
    private static let responseEphemeralRange = 12..<44
    private static let responseEmptyRange = 44..<60
    private static let responseMac1Range = 60..<76

    // Cookie-reply layout: [WireGuard §5.4.7](https://www.wireguard.com/papers/wireguard.pdf#page=13).
    private static let cookieMessageLength = 64
    private static let cookieReceiverIndexOffset = 4
    private static let cookieNonceRange = 8..<32
    private static let cookieCiphertextRange = 32..<64

    // Transport layout and padding: [WireGuard §5.4.6](https://www.wireguard.com/papers/wireguard.pdf#page=13).
    private static let transportHeaderLength = 16
    private static let transportReceiverIndexOffset = 4
    private static let transportCounterOffset = 8
    static let paddingMultiple = 16
    private static let minimumTransportMessageLength = transportHeaderLength + WireGuardCrypto.authenticationTagLength

    // IPv4 total length minus its minimum header ([RFC 791 §3.1](https://www.rfc-editor.org/rfc/rfc791.html#section-3.1)) and UDP ([RFC 768](https://www.rfc-editor.org/rfc/rfc768.html)).
    private static let ipv4MinimumHeaderLength = 20
    private static let udpHeaderLength = 8
    private static let maximumDatagramLength = Int(UInt16.max) - ipv4MinimumHeaderLength - udpHeaderLength
    // Leave room for the transport header, tag and complete padding blocks.
    static let maximumPaddedPacketLength = (maximumDatagramLength - minimumTransportMessageLength) / paddingMultiple * paddingMultiple

    struct Initiation {
        fileprivate let bytes: Data

        var senderIndex: UInt32 { WireGuardMessage.readUInt32(bytes, at: WireGuardMessage.initiationSenderIndexOffset) }
        var ephemeral: Data { bytes[WireGuardMessage.initiationEphemeralRange] }
        var encryptedStatic: Data { bytes[WireGuardMessage.initiationStaticRange] }
        var encryptedTimestamp: Data { bytes[WireGuardMessage.initiationTimestampRange] }
        var mac1: Data { bytes[WireGuardMessage.initiationMac1Range] }
        // Authenticate the original prefix, not a re-encoded approximation of the message.
        var mac1Input: Data { bytes.prefix(WireGuardMessage.initiationMac1Range.lowerBound) }
    }

    struct Response {
        fileprivate let bytes: Data

        var senderIndex: UInt32 { WireGuardMessage.readUInt32(bytes, at: WireGuardMessage.responseSenderIndexOffset) }
        var receiverIndex: UInt32 { WireGuardMessage.readUInt32(bytes, at: WireGuardMessage.responseReceiverIndexOffset) }
        var ephemeral: Data { bytes[WireGuardMessage.responseEphemeralRange] }
        var encryptedEmpty: Data { bytes[WireGuardMessage.responseEmptyRange] }
        var mac1: Data { bytes[WireGuardMessage.responseMac1Range] }
        var mac1Input: Data { bytes.prefix(WireGuardMessage.responseMac1Range.lowerBound) }
    }

    struct CookieReply {
        fileprivate let bytes: Data

        var receiverIndex: UInt32 { WireGuardMessage.readUInt32(bytes, at: WireGuardMessage.cookieReceiverIndexOffset) }
        var nonce: Data { bytes[WireGuardMessage.cookieNonceRange] }
        var ciphertext: Data { bytes[WireGuardMessage.cookieCiphertextRange] }
    }

    struct Transport {
        fileprivate let bytes: Data

        var receiverIndex: UInt32 { WireGuardMessage.readUInt32(bytes, at: WireGuardMessage.transportReceiverIndexOffset) }
        var counter: UInt64 { WireGuardMessage.readUInt64(bytes, at: WireGuardMessage.transportCounterOffset) }
        var ciphertext: Data { bytes.dropFirst(WireGuardMessage.transportHeaderLength) }
    }

    static func decode(_ datagram: Data) throws -> Self {
        let bytes = Data(datagram)
        guard bytes.count >= messageTypeLength else { throw Failure.invalidMessage }
        switch readUInt32(bytes, at: 0) {
        case initiationMessageType:
            guard bytes.count == initiationMessageLength else { throw Failure.invalidMessage }
            return .initiation(Initiation(bytes: bytes))
        case responseMessageType:
            guard bytes.count == responseMessageLength else { throw Failure.invalidMessage }
            return .response(Response(bytes: bytes))
        case cookieMessageType:
            guard bytes.count == cookieMessageLength else { throw Failure.invalidMessage }
            return .cookieReply(CookieReply(bytes: bytes))
        case transportMessageType:
            guard bytes.count >= minimumTransportMessageLength, bytes.count <= maximumDatagramLength else { throw Failure.invalidMessage }
            return .transport(Transport(bytes: bytes))
        default:
            throw Failure.unexpectedMessage
        }
    }

    static func initiationBody(senderIndex: UInt32, payload: Data) -> Data {
        littleEndian(initiationMessageType) + littleEndian(senderIndex) + payload
    }

    static func responseBody(senderIndex: UInt32, receiverIndex: UInt32, payload: Data) -> Data {
        littleEndian(responseMessageType) + littleEndian(senderIndex) + littleEndian(receiverIndex) + payload
    }

    static func transportDatagram(receiverIndex: UInt32, counter: UInt64, ciphertext: Data) -> Data {
        littleEndian(transportMessageType) + littleEndian(receiverIndex) + littleEndian(counter) + ciphertext
    }

    private static func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 | UInt64(data[offset + $1]) << ($1 * 8) }
    }
}
