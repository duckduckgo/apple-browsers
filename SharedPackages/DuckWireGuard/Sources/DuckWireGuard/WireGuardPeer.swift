//
//  WireGuardPeer.swift
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
import Darwin
import Foundation

/// A single configured WireGuard peer supporting initiator and responder handshakes.
///
/// This object owns protocol state, not sockets or routes. Send returned datagrams over UDP,
/// feed received datagrams to `receive`, and serialize all access to this object.
/// The caller schedules handshakes, retransmissions and keepalives; this PoC has no automatic timers.
public final class WireGuardPeer {
    public enum Error: Swift.Error, Equatable {
        case invalidKey
        case invalidTimestamp
        case invalidMessage
        case unexpectedMessage
        case authenticationFailed
        case handshakeRequired
        case handshakeRateLimited
        case handshakeExpired
        case sessionExpired
        case replayedPacket
        case replayedHandshake
        case invalidPacket
        case counterExhausted
        case indexCollision
    }

    public enum ReceiveResult: Equatable, Sendable {
        /// Submit this response promptly. Sending with its keys waits for initiator confirmation.
        case handshakeResponse(Data)
        /// Send a keepalive or an IP packet promptly to confirm the new session to the responder.
        case handshakeComplete
        /// A valid cookie was cached. Wait for the existing handshake retry timer before initiating again.
        case cookieReceived
        /// A decrypted IPv4 or IPv6 packet, with WireGuard padding removed.
        case packet(Data)
        case keepalive
    }

    /// This peer's public key, for registration with the remote server.
    public var publicKey: Data { localPrivateKey.publicKey.rawRepresentation }

    public var isEstablished: Bool {
        guard let session else { return false }
        return now() - session.created < Self.rejectAfterTime
    }

    /// Increases when an initiator response is authenticated or a responder keypair is confirmed.
    /// Check around `receive` so confirming IP packets can still be delivered normally.
    public private(set) var handshakeGeneration: UInt64 = 0

    public var currentSessionIsInitiator: Bool { session?.isInitiator ?? false }

    /// A responder has derived keys but cannot use them to send before key confirmation.
    public var isAwaitingConfirmation: Bool {
        guard let nextSession else { return false }
        return now() - nextSession.created < Self.rejectAfterTime
    }

    /// Receiving authenticated transport refreshes initiator keys near expiry (Go: 180 - 10 - 5 seconds).
    public var needsRekeyAfterReceiving: Bool {
        guard let session, session.isInitiator else { return false }
        return now() - session.created > 165
    }

    /// Initiate another handshake when this becomes true. Expiry at 180 seconds is enforced separately.
    public var needsRekey: Bool {
        guard let session else { return true }
        return now() - session.created >= Self.rejectAfterTime
            || (session.isInitiator && now() - session.created >= 120) || session.sendCounter >= Self.rekeyAfterMessages
    }

    private static let rejectAfterTime: TimeInterval = 180
    private static let rejectAfterMessages = UInt64.max - 8192
    private static let rekeyAfterMessages: UInt64 = 1 << 60
    private static let cookieLifetime: TimeInterval = 120
    private static let secondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }()

    private let localPrivateKey: Curve25519.KeyAgreement.PrivateKey
    private let remotePublicKey: Curve25519.KeyAgreement.PublicKey
    private let presharedKey: Data
    private let inboundMac1Key: Data
    private let ephemeralPrivateKey: () -> Data
    private let senderIndex: () -> UInt32
    private let now: () -> TimeInterval
    private let timestamp: () -> Data
    private var pending: Handshake?
    private var session: Session?
    private var previousSession: Session?
    private var nextSession: Session?
    private var nextResponseMac1: Data?
    private var lastReceivedTimestamp = Data(repeating: 0, count: 12)
    private var lastInitiationReceived: TimeInterval?
    // Independent of authenticated replay/rate watermarks: valid public MAC1 is cheap
    // to forge, so failed authentication must also consume the expensive-DH budget.
    private var initiationAttemptTokens: Double = 8
    private var initiationAttemptBudgetUpdated: TimeInterval?
    private var cookie: (value: Data, received: TimeInterval)?
    private var lastInitiation: TimeInterval?

    public static func generatePrivateKey() -> Data {
        Curve25519.KeyAgreement.PrivateKey().rawRepresentation
    }

    public convenience init(privateKey: Data, peerPublicKey: Data, presharedKey: Data? = nil) throws {
        try self.init(
            privateKey: privateKey,
            peerPublicKey: peerPublicKey,
            presharedKey: presharedKey,
            ephemeralPrivateKey: Self.generatePrivateKey,
            senderIndex: { UInt32.random(in: 1...UInt32.max) },
            now: { Double(mach_continuous_time()) * Self.secondsPerTick },
            timestamp: Self.makeTimestamp
        )
    }

    init(privateKey: Data,
         peerPublicKey: Data,
         presharedKey: Data? = nil,
         ephemeralPrivateKey: @escaping () -> Data,
         senderIndex: @escaping () -> UInt32,
         now: @escaping () -> TimeInterval,
         timestamp: @escaping () -> Data) throws {
        guard privateKey.count == 32, peerPublicKey.count == 32,
              presharedKey == nil || presharedKey?.count == 32 else {
            throw Error.invalidKey
        }
        do {
            self.localPrivateKey = try .init(rawRepresentation: privateKey)
            self.remotePublicKey = try .init(rawRepresentation: peerPublicKey)
            // Reject low-order public keys before any state is created.
            _ = try Self.sharedSecret(self.localPrivateKey, self.remotePublicKey)
        } catch {
            throw Error.invalidKey
        }
        self.presharedKey = presharedKey ?? Data(repeating: 0, count: 32)
        self.ephemeralPrivateKey = ephemeralPrivateKey
        self.senderIndex = senderIndex
        self.now = now
        self.timestamp = timestamp
        inboundMac1Key = WireGuardCrypto.hash(Data("mac1----".utf8) + localPrivateKey.publicKey.rawRepresentation)
    }

    /// Start or retry a handshake. A retry uses a fresh ephemeral key and timestamp.
    /// Calls less than five seconds apart fail without disturbing an existing session.
    public func initiateHandshake() throws -> Data {
        let currentTime = now()
        if let lastInitiation, currentTime - lastInitiation < 5 {
            throw Error.handshakeRateLimited
        }
        let index = senderIndex()
        guard index != session?.localIndex, index != previousSession?.localIndex,
              index != pending?.localIndex, index != nextSession?.localIndex else {
            throw Error.indexCollision
        }
        let time = timestamp()
        guard time.count == 12 else { throw Error.invalidTimestamp }
        let ephemeral: Curve25519.KeyAgreement.PrivateKey
        do {
            ephemeral = try .init(rawRepresentation: ephemeralPrivateKey())
        } catch {
            throw Error.invalidKey
        }

        var chainingKey = WireGuardCrypto.hash(Data("Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s".utf8))
        var hash = WireGuardCrypto.hash(
            WireGuardCrypto.hash(chainingKey + Data("WireGuard v1 zx2c4 Jason@zx2c4.com".utf8))
            + remotePublicKey.rawRepresentation
        )
        let ephemeralPublicKey = ephemeral.publicKey.rawRepresentation
        hash = WireGuardCrypto.hash(hash + ephemeralPublicKey)
        chainingKey = WireGuardCrypto.kdf(key: chainingKey, input: ephemeralPublicKey, count: 1)[0]
        var derived = WireGuardCrypto.kdf(
            key: chainingKey, input: try Self.sharedSecret(ephemeral, remotePublicKey), count: 2
        )
        chainingKey = derived[0]
        let encryptedStatic = try WireGuardCrypto.seal(
            key: derived[1], counter: 0, plaintext: publicKey, authenticating: hash
        )
        hash = WireGuardCrypto.hash(hash + encryptedStatic)
        derived = WireGuardCrypto.kdf(
            key: chainingKey, input: try Self.sharedSecret(localPrivateKey, remotePublicKey), count: 2
        )
        chainingKey = derived[0]
        let encryptedTimestamp = try WireGuardCrypto.seal(
            key: derived[1], counter: 0, plaintext: time, authenticating: hash
        )
        hash = WireGuardCrypto.hash(hash + encryptedTimestamp)

        var message = Self.littleEndian(UInt32(1)) + Self.littleEndian(index)
        message += ephemeralPublicKey + encryptedStatic + encryptedTimestamp
        let authenticated = authenticateHandshake(message, at: currentTime)
        pending = Handshake(
            localIndex: index, ephemeral: ephemeral, chainingKey: chainingKey, hash: hash,
            mac1: authenticated.mac1, created: currentTime
        )
        lastInitiation = currentTime
        return authenticated.message
    }

    /// Consume one complete UDP datagram from the configured peer.
    /// Authentication failures never replace session keys or advance the replay window.
    public func receive(_ datagram: Data) throws -> ReceiveResult {
        let message = Data(datagram)
        guard message.count >= 4 else { throw Error.invalidMessage }
        switch Self.readUInt32(message, at: 0) {
        case 1: return try receiveInitiation(message)
        case 2: return try receiveResponse(message)
        case 3: return try receiveCookie(message)
        case 4: return try receiveTransport(message)
        default: throw Error.unexpectedMessage
        }
    }

    /// An immutable packet with a reserved nonce. Encrypt on any worker, then submit once.
    /// Reserving consumes the nonce even if the caller later discards this work.
    public struct PreparedPacket: Sendable {
        public let packet: Data
        fileprivate let key: Data
        fileprivate let remoteIndex: UInt32
        fileprivate let counter: UInt64
        fileprivate let sessionID: UUID
        fileprivate let paddingLength: Int

        public func encrypt() throws -> Data {
            let ciphertext = try WireGuardCrypto.seal(
                key: key, counter: counter, plaintext: packet + Data(repeating: 0, count: paddingLength)
            )
            let header = WireGuardPeer.littleEndian(UInt32(4)) + WireGuardPeer.littleEndian(remoteIndex)
                + WireGuardPeer.littleEndian(counter)
            return header + ciphertext
        }
    }

    /// Reserve a nonce on the peer's owner queue before encrypting on a background worker.
    /// The optional IP-packet limit also caps padding; it is bound into the immutable snapshot.
    public func prepare(_ packet: Data, maximumPacketLength: Int? = nil) throws -> PreparedPacket {
        let normalized = Data(packet)
        guard try Self.packetLength(normalized) == normalized.count else { throw Error.invalidPacket }
        // Keep padded content plus WireGuard overhead inside a maximum IPv4 UDP datagram.
        guard normalized.count <= 65_472 else { throw Error.invalidPacket }
        let limit = maximumPacketLength ?? 65_472
        guard normalized.count <= limit else { throw Error.invalidPacket }
        let padding = min((16 - normalized.count % 16) % 16, limit - normalized.count)
        return try reservePayload(normalized, paddingLength: padding)
    }

    /// Recheck on the owner queue immediately before sending work completed asynchronously.
    public func canSend(_ packet: PreparedPacket) -> Bool {
        guard let session, session.id == packet.sessionID else { return false }
        return now() - session.created < Self.rejectAfterTime
    }

    public func encrypt(_ packet: Data) throws -> Data {
        try prepare(packet).encrypt()
    }

    /// An authenticated empty transport packet, also used to confirm a completed handshake.
    public func keepalive() throws -> Data {
        try reservePayload(Data()).encrypt()
    }

    /// Discard the current handshake, sessions and server cookie.
    public func reset() {
        pending = nil
        session = nil
        previousSession = nil
        nextSession = nil
        nextResponseMac1 = nil
        // Keep the authenticated peer's timestamp replay watermark across key resets,
        // as wireguard-go does when zeroing key material on an existing peer.
        // The independent pre-DH attempt budget also survives to prevent reset bypass.
        cookie = nil
        lastInitiation = nil
    }

    private struct IncomingInitiation {
        let chainingKey: Data
        let hash: Data
        let ephemeral: Curve25519.KeyAgreement.PublicKey
        let remoteIndex: UInt32
        let timestamp: Data
    }

    private func consumeInitiationAttemptBudget(at currentTime: TimeInterval) throws {
        if let updated = initiationAttemptBudgetUpdated {
            let elapsed = min(max(currentTime - updated, 0), 8.0 / 50.0)
            initiationAttemptTokens = min(8, initiationAttemptTokens + elapsed * 50)
            initiationAttemptBudgetUpdated = max(updated, currentTime)
        } else {
            initiationAttemptBudgetUpdated = currentTime
        }
        guard initiationAttemptTokens >= 1 else { throw Error.handshakeRateLimited }
        initiationAttemptTokens -= 1
    }

    private func consumeInitiation(_ message: Data) throws -> IncomingInitiation {
        guard message.count == 148 else { throw Error.invalidMessage }
        guard Self.constantTimeEqual(
            WireGuardCrypto.mac(key: inboundMac1Key, data: message.prefix(116)), Data(message[116..<132])
        ) else { throw Error.authenticationFailed }
        let currentTime = now()
        try consumeInitiationAttemptBudget(at: currentTime)
        if let lastInitiationReceived, currentTime - lastInitiationReceived <= 0.02 { throw Error.handshakeRateLimited }
        let ephemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: message[8..<40])
        var chainingKey = WireGuardCrypto.hash(Data("Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s".utf8))
        var hash = WireGuardCrypto.hash(
            WireGuardCrypto.hash(chainingKey + Data("WireGuard v1 zx2c4 Jason@zx2c4.com".utf8)) + publicKey
        )
        hash = WireGuardCrypto.hash(hash + ephemeral.rawRepresentation)
        chainingKey = WireGuardCrypto.kdf(key: chainingKey, input: ephemeral.rawRepresentation, count: 1)[0]
        var derived = WireGuardCrypto.kdf(key: chainingKey, input: try Self.sharedSecret(localPrivateKey, ephemeral), count: 2)
        chainingKey = derived[0]
        let remoteStatic = try WireGuardCrypto.open(key: derived[1], counter: 0, ciphertext: message[40..<88], authenticating: hash)
        guard Self.constantTimeEqual(remoteStatic, remotePublicKey.rawRepresentation) else { throw Error.authenticationFailed }
        hash = WireGuardCrypto.hash(hash + message[40..<88])
        derived = WireGuardCrypto.kdf(key: chainingKey, input: try Self.sharedSecret(localPrivateKey, remotePublicKey), count: 2)
        chainingKey = derived[0]
        let timestamp = try WireGuardCrypto.open(key: derived[1], counter: 0, ciphertext: message[88..<116], authenticating: hash)
        guard timestamp.count == 12 else { throw Error.invalidTimestamp }
        if !lastReceivedTimestamp.lexicographicallyPrecedes(timestamp) { throw Error.replayedHandshake }
        hash = WireGuardCrypto.hash(hash + message[88..<116])
        return IncomingInitiation(chainingKey: chainingKey, hash: hash, ephemeral: ephemeral,
                                  remoteIndex: Self.readUInt32(message, at: 4), timestamp: timestamp)
    }

    private func receiveInitiation(_ message: Data) throws -> ReceiveResult {
        let incoming: IncomingInitiation
        do { incoming = try consumeInitiation(message) } catch let error as Error { throw error } catch {
            throw Error.authenticationFailed
        }
        let index = senderIndex()
        guard index != session?.localIndex, index != previousSession?.localIndex,
              index != pending?.localIndex, index != nextSession?.localIndex else { throw Error.indexCollision }
        let ephemeral = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: ephemeralPrivateKey())
        let ephemeralPublic = ephemeral.publicKey.rawRepresentation
        var hash = WireGuardCrypto.hash(incoming.hash + ephemeralPublic)
        var chainingKey = WireGuardCrypto.kdf(key: incoming.chainingKey, input: ephemeralPublic, count: 1)[0]
        chainingKey = WireGuardCrypto.kdf(key: chainingKey, input: try Self.sharedSecret(ephemeral, incoming.ephemeral), count: 1)[0]
        chainingKey = WireGuardCrypto.kdf(key: chainingKey, input: try Self.sharedSecret(ephemeral, remotePublicKey), count: 1)[0]
        let derived = WireGuardCrypto.kdf(key: chainingKey, input: presharedKey, count: 3)
        chainingKey = derived[0]
        hash = WireGuardCrypto.hash(hash + derived[1])
        let empty = try WireGuardCrypto.seal(key: derived[2], counter: 0, plaintext: Data(), authenticating: hash)
        var response = Self.littleEndian(UInt32(2)) + Self.littleEndian(index) + Self.littleEndian(incoming.remoteIndex)
        response += ephemeralPublic + empty
        let currentTime = now()
        let authenticated = authenticateHandshake(response, at: currentTime)
        let keys = WireGuardCrypto.kdf(key: chainingKey, input: Data(), count: 2)
        nextSession = Session(localIndex: index, remoteIndex: incoming.remoteIndex,
                              sendKey: keys[1], receiveKey: keys[0], created: currentTime, isInitiator: false)
        nextResponseMac1 = authenticated.mac1
        previousSession = nil
        lastReceivedTimestamp = incoming.timestamp
        lastInitiationReceived = currentTime
        // A valid incoming initiation replaces the one pending initiator transcript,
        // as wireguard-go does. Responses to that superseded transcript are rejected.
        pending = nil
        lastInitiation = currentTime
        return .handshakeResponse(authenticated.message)
    }

    private func authenticateHandshake(_ body: Data, at currentTime: TimeInterval) -> (message: Data, mac1: Data) {
        let macKey = WireGuardCrypto.hash(Data("mac1----".utf8) + remotePublicKey.rawRepresentation)
        let mac1 = WireGuardCrypto.mac(key: macKey, data: body)
        var message = body + mac1
        if let cookie, currentTime - cookie.received < Self.cookieLifetime {
            message += WireGuardCrypto.mac(key: cookie.value, data: message)
        } else {
            message += Data(repeating: 0, count: 16)
        }
        return (message, mac1)
    }

    private func receiveResponse(_ message: Data) throws -> ReceiveResult {
        guard message.count == 92 else { throw Error.invalidMessage }
        guard let pending else { throw Error.handshakeRequired }
        guard Self.readUInt32(message, at: 8) == pending.localIndex else { throw Error.unexpectedMessage }
        guard now() - pending.created < Self.rejectAfterTime else { throw Error.handshakeExpired }
        let macKey = WireGuardCrypto.hash(Data("mac1----".utf8) + publicKey)
        guard Self.constantTimeEqual(
            WireGuardCrypto.mac(key: macKey, data: message.prefix(60)), Data(message[60..<76])
        ) else { throw Error.authenticationFailed }

        let remoteEphemeral: Curve25519.KeyAgreement.PublicKey
        do {
            remoteEphemeral = try .init(rawRepresentation: message[12..<44])
        } catch {
            throw Error.invalidKey
        }
        var hash = WireGuardCrypto.hash(pending.hash + remoteEphemeral.rawRepresentation)
        var chainingKey = WireGuardCrypto.kdf(
            key: pending.chainingKey, input: remoteEphemeral.rawRepresentation, count: 1
        )[0]
        chainingKey = WireGuardCrypto.kdf(
            key: chainingKey, input: try Self.sharedSecret(pending.ephemeral, remoteEphemeral), count: 1
        )[0]
        chainingKey = WireGuardCrypto.kdf(
            key: chainingKey, input: try Self.sharedSecret(localPrivateKey, remoteEphemeral), count: 1
        )[0]
        let derived = WireGuardCrypto.kdf(key: chainingKey, input: presharedKey, count: 3)
        chainingKey = derived[0]
        hash = WireGuardCrypto.hash(hash + derived[1])
        do {
            let empty = try WireGuardCrypto.open(
                key: derived[2], counter: 0, ciphertext: message[44..<60], authenticating: hash
            )
            guard empty.isEmpty else { throw Error.authenticationFailed }
        } catch {
            throw Error.authenticationFailed
        }
        let keys = WireGuardCrypto.kdf(key: chainingKey, input: Data(), count: 2)
        previousSession = nextSession ?? session
        nextSession = nil
        nextResponseMac1 = nil
        session = Session(
            localIndex: pending.localIndex, remoteIndex: Self.readUInt32(message, at: 4),
            sendKey: keys[0], receiveKey: keys[1], created: now(), isInitiator: true
        )
        self.pending = nil
        handshakeGeneration &+= 1
        return .handshakeComplete
    }

    private func receiveCookie(_ message: Data) throws -> ReceiveResult {
        guard message.count == 64 else { throw Error.invalidMessage }
        let receiver = Self.readUInt32(message, at: 4)
        let mac1: Data
        let created: TimeInterval
        if let pending, pending.localIndex == receiver {
            mac1 = pending.mac1
            created = pending.created
        } else if let nextSession, nextSession.localIndex == receiver, let nextResponseMac1 {
            mac1 = nextResponseMac1
            created = nextSession.created
        } else {
            throw pending == nil && nextSession == nil ? Error.handshakeRequired : Error.unexpectedMessage
        }
        guard now() - created < Self.rejectAfterTime else { throw Error.handshakeExpired }
        let key = WireGuardCrypto.hash(Data("cookie--".utf8) + remotePublicKey.rawRepresentation)
        let value: Data
        do {
            value = try WireGuardCrypto.openCookie(
                key: key, nonce: message[8..<32], ciphertext: message[32..<64], authenticating: mac1
            )
        } catch {
            throw Error.authenticationFailed
        }
        guard value.count == 16 else { throw Error.authenticationFailed }
        cookie = (value, now())
        return .cookieReceived
    }

    private func reservePayload(_ plaintext: Data, paddingLength: Int = 0) throws -> PreparedPacket {
        guard var session else { throw Error.handshakeRequired }
        guard now() - session.created < Self.rejectAfterTime else { throw Error.sessionExpired }
        guard session.sendCounter < Self.rejectAfterMessages else { throw Error.counterExhausted }
        let packet = PreparedPacket(
            packet: plaintext, key: session.sendKey, remoteIndex: session.remoteIndex,
            counter: session.sendCounter, sessionID: session.id, paddingLength: paddingLength
        )
        session.sendCounter += 1
        self.session = session
        return packet
    }

    private func receiveTransport(_ message: Data) throws -> ReceiveResult {
        guard message.count >= 32, message.count <= 65_507 else { throw Error.invalidMessage }
        let receiver = Self.readUInt32(message, at: 4)
        let currentTime = now()
        if var nextSession, receiver == nextSession.localIndex {
            let plaintext = try Self.decryptTransportPayload(message, session: &nextSession, now: currentTime)
            previousSession = session
            session = nextSession
            self.nextSession = nil
            nextResponseMac1 = nil
            handshakeGeneration &+= 1
            return try Self.decodeTransportPayload(plaintext)
        }
        if var session, receiver == session.localIndex {
            defer { self.session = session }
            return try Self.decryptTransport(message, session: &session, now: currentTime)
        }
        if var previousSession, receiver == previousSession.localIndex {
            defer { self.previousSession = previousSession }
            return try Self.decryptTransport(message, session: &previousSession, now: currentTime)
        }
        throw Error.unexpectedMessage
    }

    private static func decryptTransport(_ message: Data, session: inout Session, now: TimeInterval) throws -> ReceiveResult {
        try decodeTransportPayload(decryptTransportPayload(message, session: &session, now: now))
    }

    private static func decryptTransportPayload(_ message: Data, session: inout Session, now: TimeInterval) throws -> Data {
        guard now - session.created < rejectAfterTime else { throw Error.sessionExpired }
        let counter = readUInt64(message, at: 8)
        guard counter < rejectAfterMessages else { throw Error.counterExhausted }
        let plaintext: Data
        do {
            plaintext = try WireGuardCrypto.open(key: session.receiveKey, counter: counter, ciphertext: message.dropFirst(16))
        } catch {
            throw Error.authenticationFailed
        }
        guard session.replayWindow.accept(counter) else { throw Error.replayedPacket }
        return plaintext
    }

    private static func decodeTransportPayload(_ plaintext: Data) throws -> ReceiveResult {
        if plaintext.isEmpty { return .keepalive }
        let length = try packetLength(plaintext)
        return .packet(Data(plaintext.prefix(length)))
    }

    private static func packetLength(_ packet: Data) throws -> Int {
        guard let first = packet.first else { throw Error.invalidPacket }
        switch first >> 4 {
        case 4:
            guard packet.count >= 20 else { throw Error.invalidPacket }
            let headerLength = Int(first & 0x0f) * 4
            let length = Int(packet[2]) << 8 | Int(packet[3])
            guard headerLength >= 20, length >= headerLength, length <= packet.count else { throw Error.invalidPacket }
            return length
        case 6:
            guard packet.count >= 40 else { throw Error.invalidPacket }
            let length = 40 + (Int(packet[4]) << 8 | Int(packet[5]))
            guard length <= packet.count else { throw Error.invalidPacket }
            return length
        default:
            throw Error.invalidPacket
        }
    }

    private static func sharedSecret(_ privateKey: Curve25519.KeyAgreement.PrivateKey,
                                     _ publicKey: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        let data = secret.withUnsafeBytes { Data($0) }
        guard data.contains(where: { $0 != 0 }) else { throw Error.invalidKey }
        return data
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { difference |= left ^ right }
        return difference == 0
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

    private static func makeTimestamp() -> Data {
        let unixTime = Date().timeIntervalSince1970
        let seconds = UInt64(unixTime) + 0x400000000000000a
        let nanoseconds = UInt32((unixTime - floor(unixTime)) * 1_000_000_000)
        return withUnsafeBytes(of: seconds.bigEndian) { Data($0) }
            + withUnsafeBytes(of: nanoseconds.bigEndian) { Data($0) }
    }

    private struct Handshake {
        let localIndex: UInt32
        let ephemeral: Curve25519.KeyAgreement.PrivateKey
        let chainingKey: Data
        let hash: Data
        let mac1: Data
        let created: TimeInterval
    }

    private struct Session {
        let id = UUID()
        let localIndex: UInt32
        let remoteIndex: UInt32
        let sendKey: Data
        let receiveKey: Data
        let created: TimeInterval
        let isInitiator: Bool
        var sendCounter: UInt64 = 0
        var replayWindow = ReplayWindow()
    }

    /// Matches wireguard-go's 128-word ring and inclusive 8128-counter reorder distance.
    /// One word of slack lets advancing traffic clear whole words without discarding live bits.
    /// Reference ownership avoids copying the bitmap with Session's temporary copies.
    private final class ReplayWindow {
        private var highest: UInt64 = 0
        private var words = [UInt64](repeating: 0, count: 128)

        func accept(_ counter: UInt64) -> Bool {
            let block = counter >> 6
            if counter > highest {
                clearAdvancingBlocks(after: highest >> 6, through: block)
                highest = counter
            } else if highest - counter > 8128 {
                return false
            }
            let word = Int(block & 127)
            let bit = UInt64(1) << (counter & 63)
            guard words[word] & bit == 0 else { return false }
            words[word] |= bit
            return true
        }

        private func clearAdvancingBlocks(after previous: UInt64, through current: UInt64) {
            let distance = min(current - previous, 128)
            guard distance > 0 else { return }
            // Sequential traffic clears one word per 64 packets; large jumps clear at most 128.
            for offset in 1...distance { words[Int((previous + offset) & 127)] = 0 }
        }
    }
}
