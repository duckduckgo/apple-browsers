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
/// This object persists across rekeys and owns protocol state, not sockets or routes. Send returned datagrams over UDP,
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
    public var publicKey: Data { handshakeEngine.publicKey }

    public var isEstablished: Bool {
        guard let currentKeypair else { return false }
        return currentKeypair.isWithinLifetime(at: now())
    }

    /// Increases when an initiator response is authenticated or a responder keypair is confirmed.
    /// Check around `receive` so confirming IP packets can still be delivered normally.
    public private(set) var handshakeGeneration: UInt64 = 0

    /// Fresh authenticated transport proves reachability even when its inner IP packet is rejected.
    /// Advances only after authentication and replay checks succeed.
    public private(set) var authenticatedTransportGeneration: UInt64 = 0

    /// A responder has derived keys but cannot use them to send before key confirmation.
    public var isAwaitingConfirmation: Bool {
        guard let nextKeypair else { return false }
        return nextKeypair.isWithinLifetime(at: now())
    }

    /// Receiving authenticated transport refreshes initiator keys near expiry (Go: 180 - 10 - 5 seconds).
    public var needsRekeyAfterReceiving: Bool {
        guard let currentKeypair, currentKeypair.isInitiator else { return false }
        return now() - currentKeypair.created > Self.rekeyAfterReceivingTime
    }

    /// Initiate another handshake when this becomes true. Expiry at 180 seconds is enforced separately.
    public var needsRekey: Bool {
        guard let currentKeypair else { return true }
        return now() - currentKeypair.created >= Self.rejectAfterTime
            || (currentKeypair.isInitiator && now() - currentKeypair.created >= Self.rekeyAfterTime) || currentKeypair.needsMessageRekey
    }

    // [WireGuard §6.1–6.2](https://www.wireguard.com/papers/wireguard.pdf#page=14): rekey before mandatory rejection.
    private static let rejectAfterTime: TimeInterval = 180
    private static let rekeyAfterTime: TimeInterval = 120
    private static let rekeyTimeout: TimeInterval = 5
    private static let keepaliveTimeout: TimeInterval = 10
    private static let rekeyAfterReceivingTime = rejectAfterTime - keepaliveTimeout - rekeyTimeout
    private static let rejectAfterMessages = UInt64.max - (1 << 13)
    private static let rekeyAfterMessages: UInt64 = 1 << 60

    // TAI64N encoding: [wireguard-go tai64n](https://github.com/WireGuard/wireguard-go/blob/1e2c3e5a3c14/tai64n/tai64n.go#L13-L25).
    private static let timestampLength = 12
    private static let tai64nBase: UInt64 = 0x4000_0000_0000_000a
    private static let nanosecondsPerSecond: Double = 1_000_000_000

    // Accepted-initiation spacing matches [wireguard-go](https://github.com/WireGuard/wireguard-go/blob/1e2c3e5a3c14/device/constants.go#L23).
    private static let minimumInitiationInterval: TimeInterval = 1.0 / 50.0
    private static let secondsPerTick: Double = {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(timebase.numer) / Double(timebase.denom) / nanosecondsPerSecond
    }()

    private let handshakeEngine: WireGuardHandshake
    private var handshakeAuthenticator: WireGuardHandshakeAuthenticator
    private let ephemeralPrivateKey: () -> Data
    private let senderIndex: () -> UInt32
    private let now: () -> TimeInterval
    private let timestamp: () -> Data
    // Seed fresh sessions so boundary tests never need to reset a live nonce counter.
    private let initialSendCounter: UInt64
    private var pending: Handshake?
    private var currentKeypair: TransportKeypair?
    private var previousKeypair: TransportKeypair?
    private var nextKeypair: TransportKeypair?
    private var nextResponseMac1: Data?
    private var lastReceivedTimestamp = Data(repeating: 0, count: WireGuardPeer.timestampLength)
    private var lastInitiationReceived: TimeInterval?
    private var handshakeAttemptBudget = HandshakeAttemptBudget()
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
            timestamp: Self.makeTimestamp,
            initialSendCounter: 0
        )
    }

    init(privateKey: Data,
         peerPublicKey: Data,
         presharedKey: Data? = nil,
         ephemeralPrivateKey: @escaping () -> Data,
         senderIndex: @escaping () -> UInt32,
         now: @escaping () -> TimeInterval,
         timestamp: @escaping () -> Data,
         initialSendCounter: UInt64 = 0) throws {
        handshakeEngine = try WireGuardHandshake(privateKey: privateKey, peerPublicKey: peerPublicKey, presharedKey: presharedKey)
        self.ephemeralPrivateKey = ephemeralPrivateKey
        self.senderIndex = senderIndex
        self.now = now
        self.timestamp = timestamp
        self.initialSendCounter = initialSendCounter
        handshakeAuthenticator = WireGuardHandshakeAuthenticator(publicKey: handshakeEngine.publicKey, peerPublicKey: handshakeEngine.peerPublicKey)
    }

    /// Start or retry a handshake. A retry uses a fresh ephemeral key and timestamp.
    /// Calls less than five seconds apart fail without disturbing an existing session.
    /// See [WireGuard §5.4.2](https://www.wireguard.com/papers/wireguard.pdf#page=10) for the Noise IKpsk2 transcript.
    public func initiateHandshake() throws -> Data {
        let currentTime = now()
        if let lastInitiation, currentTime - lastInitiation < Self.rekeyTimeout {
            throw Error.handshakeRateLimited
        }
        let index = senderIndex()
        guard index != currentKeypair?.localIndex, index != previousKeypair?.localIndex,
              index != pending?.localIndex, index != nextKeypair?.localIndex else {
            throw Error.indexCollision
        }
        let time = timestamp()
        guard time.count == Self.timestampLength else { throw Error.invalidTimestamp }
        let initiation = try handshakeEngine.initiate(ephemeralPrivateKey: ephemeralPrivateKey(), timestamp: time)
        let message = WireGuardMessage.initiationBody(senderIndex: index, payload: initiation.payload)
        let authenticated = handshakeAuthenticator.authenticate(message, at: currentTime)
        pending = Handshake(localIndex: index, transcript: initiation.transcript, mac1: authenticated.mac1, created: currentTime)
        lastInitiation = currentTime
        return authenticated.message
    }

    /// Consume one complete UDP datagram from the configured peer.
    /// Authentication failures never replace session keys or advance the replay window.
    public func receive(_ datagram: Data) throws -> ReceiveResult {
        switch try WireGuardMessage.decode(datagram) {
        case .initiation(let message): return try receiveInitiation(message)
        case .response(let message): return try receiveResponse(message)
        case .cookieReply(let message): return try receiveCookie(message)
        case .transport(let message): return try receiveTransport(message)
        }
    }

    /// An immutable packet with a reserved nonce. Encrypt on any worker, then submit once.
    /// Reserving consumes the nonce even if the caller later discards this work.
    public struct PreparedPacket: Sendable {
        public let packet: Data
        fileprivate let key: Data
        fileprivate let remoteIndex: UInt32
        fileprivate let counter: UInt64
        fileprivate let keypairID: UUID
        fileprivate let paddingLength: Int

        public func encrypt() throws -> Data {
            let ciphertext = try WireGuardCrypto.seal(
                key: key, counter: counter, plaintext: packet + Data(repeating: 0, count: paddingLength)
            )
            return WireGuardMessage.transportDatagram(receiverIndex: remoteIndex, counter: counter, ciphertext: ciphertext)
        }
    }

    /// Reserve a nonce on the peer's owner queue before encrypting on a background worker.
    /// The optional IP-packet limit also caps padding; it is bound into the immutable snapshot.
    /// [WireGuard §5.4.6](https://www.wireguard.com/papers/wireguard.pdf#page=12) bounds padding by the path MTU.
    public func prepare(_ packet: Data, maximumPacketLength: Int? = nil) throws -> PreparedPacket {
        let normalized = Data(packet)
        guard try IPPacket.length(of: normalized) == normalized.count else { throw Error.invalidPacket }
        // Keep padded content plus WireGuard overhead inside a maximum IPv4 UDP datagram.
        guard normalized.count <= WireGuardMessage.maximumPaddedPacketLength else { throw Error.invalidPacket }
        let limit = maximumPacketLength ?? WireGuardMessage.maximumPaddedPacketLength
        guard normalized.count <= limit else { throw Error.invalidPacket }
        let padding = min((WireGuardMessage.paddingMultiple - normalized.count % WireGuardMessage.paddingMultiple) % WireGuardMessage.paddingMultiple, limit - normalized.count)
        return try reservePayload(normalized, paddingLength: padding)
    }

    /// Recheck on the owner queue immediately before sending work completed asynchronously.
    public func canSend(_ packet: PreparedPacket) -> Bool {
        guard let currentKeypair, currentKeypair.owns(packet) else { return false }
        return currentKeypair.isWithinLifetime(at: now())
    }

    public func encrypt(_ packet: Data) throws -> Data {
        try prepare(packet).encrypt()
    }

    /// An authenticated empty transport packet, also used to confirm a completed handshake.
    public func keepalive() throws -> Data {
        try reservePayload(Data()).encrypt()
    }

    /// Discard the current handshake, transport keypairs and server cookie.
    /// Releases references; Swift `Data` and outstanding packet snapshots do not guarantee key-memory erasure.
    public func reset() {
        pending = nil
        currentKeypair = nil
        previousKeypair = nil
        nextKeypair = nil
        nextResponseMac1 = nil
        // Keep the authenticated peer's timestamp replay watermark across key resets,
        // as wireguard-go does when zeroing key material on an existing peer.
        // The independent pre-DH attempt budget also survives to prevent reset bypass.
        handshakeAuthenticator.reset()
        lastInitiation = nil
    }

    private func consumeInitiation(_ message: WireGuardMessage.Initiation) throws -> WireGuardHandshake.VerifiedInitiation {
        try handshakeAuthenticator.validateMAC1(message.mac1, for: message.mac1Input)
        let currentTime = now()
        try handshakeAttemptBudget.consume(at: currentTime)
        if let lastInitiationReceived, currentTime - lastInitiationReceived <= Self.minimumInitiationInterval { throw Error.handshakeRateLimited }
        let incoming = try handshakeEngine.consumeInitiation(
            ephemeral: message.ephemeral, encryptedStatic: message.encryptedStatic, encryptedTimestamp: message.encryptedTimestamp
        )
        guard incoming.timestamp.count == Self.timestampLength else { throw Error.invalidTimestamp }
        if !lastReceivedTimestamp.lexicographicallyPrecedes(incoming.timestamp) { throw Error.replayedHandshake }
        return incoming
    }

    private func receiveInitiation(_ message: WireGuardMessage.Initiation) throws -> ReceiveResult {
        let incoming: WireGuardHandshake.VerifiedInitiation
        do { incoming = try consumeInitiation(message) } catch let error as Error { throw error } catch {
            throw Error.authenticationFailed
        }
        let remoteIndex = message.senderIndex
        let index = senderIndex()
        guard index != currentKeypair?.localIndex, index != previousKeypair?.localIndex,
              index != pending?.localIndex, index != nextKeypair?.localIndex else { throw Error.indexCollision }
        let response = try handshakeEngine.respond(to: incoming, ephemeralPrivateKey: ephemeralPrivateKey())
        let body = WireGuardMessage.responseBody(senderIndex: index, receiverIndex: remoteIndex, payload: response.payload)
        let currentTime = now()
        let authenticated = handshakeAuthenticator.authenticate(body, at: currentTime)
        let keys = response.transportKeys()
        nextKeypair = TransportKeypair(localIndex: index, remoteIndex: remoteIndex,
                                      sendKey: keys.sendKey, receiveKey: keys.receiveKey, created: currentTime, isInitiator: false,
                                      initialSendCounter: initialSendCounter)
        nextResponseMac1 = authenticated.mac1
        previousKeypair = nil
        lastReceivedTimestamp = incoming.timestamp
        lastInitiationReceived = currentTime
        // A valid incoming initiation replaces the one pending initiator transcript,
        // as wireguard-go does. Responses to that superseded transcript are rejected.
        pending = nil
        lastInitiation = currentTime
        return .handshakeResponse(authenticated.message)
    }

    private func receiveResponse(_ message: WireGuardMessage.Response) throws -> ReceiveResult {
        guard let pending else { throw Error.handshakeRequired }
        guard message.receiverIndex == pending.localIndex else { throw Error.unexpectedMessage }
        guard now() - pending.created < Self.rejectAfterTime else { throw Error.handshakeExpired }
        try handshakeAuthenticator.validateMAC1(message.mac1, for: message.mac1Input)
        try handshakeAttemptBudget.consume(at: now())

        let keys = try handshakeEngine.complete(
            pending.transcript, ephemeral: message.ephemeral, encryptedEmpty: message.encryptedEmpty
        )
        previousKeypair = nextKeypair ?? currentKeypair
        nextKeypair = nil
        nextResponseMac1 = nil
        currentKeypair = TransportKeypair(
            localIndex: pending.localIndex, remoteIndex: message.senderIndex,
            sendKey: keys.sendKey, receiveKey: keys.receiveKey, created: now(), isInitiator: true,
            initialSendCounter: initialSendCounter
        )
        self.pending = nil
        handshakeGeneration &+= 1
        return .handshakeComplete
    }

    /// Delayed retries avoid amplifying load on a peer issuing cookies.
    /// See [WireGuard §6.6](https://www.wireguard.com/papers/wireguard.pdf#page=15).
    private func receiveCookie(_ message: WireGuardMessage.CookieReply) throws -> ReceiveResult {
        let receiver = message.receiverIndex
        let mac1: Data
        let created: TimeInterval
        if let pending, pending.localIndex == receiver {
            mac1 = pending.mac1
            created = pending.created
        } else if let nextKeypair, nextKeypair.localIndex == receiver, let nextResponseMac1 {
            mac1 = nextResponseMac1
            created = nextKeypair.created
        } else {
            throw pending == nil && nextKeypair == nil ? Error.handshakeRequired : Error.unexpectedMessage
        }
        guard now() - created < Self.rejectAfterTime else { throw Error.handshakeExpired }
        try handshakeAuthenticator.cacheCookie(message, authenticating: mac1, at: now())
        return .cookieReceived
    }

    private func reservePayload(_ plaintext: Data, paddingLength: Int = 0) throws -> PreparedPacket {
        guard var currentKeypair else { throw Error.handshakeRequired }
        let packet = try currentKeypair.reserve(plaintext, paddingLength: paddingLength, at: now())
        self.currentKeypair = currentKeypair
        return packet
    }

    /// Confirm responder keys only after authenticated transport proves the initiator holds them.
    /// See [WireGuard §6.3](https://www.wireguard.com/papers/wireguard.pdf#page=14).
    private func receiveTransport(_ message: WireGuardMessage.Transport) throws -> ReceiveResult {
        let receiver = message.receiverIndex
        let currentTime = now()
        if var nextKeypair, receiver == nextKeypair.localIndex {
            let plaintext = try decryptTransportPayload(message, keypair: &nextKeypair, now: currentTime)
            previousKeypair = currentKeypair
            currentKeypair = nextKeypair
            self.nextKeypair = nil
            nextResponseMac1 = nil
            handshakeGeneration &+= 1
            return try Self.decodeTransportPayload(plaintext)
        }
        if var currentKeypair, receiver == currentKeypair.localIndex {
            defer { self.currentKeypair = currentKeypair }
            return try decryptTransport(message, keypair: &currentKeypair, now: currentTime)
        }
        if var previousKeypair, receiver == previousKeypair.localIndex {
            defer { self.previousKeypair = previousKeypair }
            return try decryptTransport(message, keypair: &previousKeypair, now: currentTime)
        }
        throw Error.unexpectedMessage
    }

    private func decryptTransport(_ message: WireGuardMessage.Transport, keypair: inout TransportKeypair, now: TimeInterval) throws -> ReceiveResult {
        try Self.decodeTransportPayload(decryptTransportPayload(message, keypair: &keypair, now: now))
    }

    /// Authentication remains observable even when subsequent inner-IP decoding fails.
    private func decryptTransportPayload(_ message: WireGuardMessage.Transport, keypair: inout TransportKeypair, now: TimeInterval) throws -> Data {
        let plaintext = try keypair.decrypt(message, at: now)
        authenticatedTransportGeneration &+= 1
        return plaintext
    }

    private static func decodeTransportPayload(_ plaintext: Data) throws -> ReceiveResult {
        if plaintext.isEmpty { return .keepalive }
        let length = try IPPacket.length(of: plaintext)
        return .packet(Data(plaintext.prefix(length)))
    }

    private static func makeTimestamp() -> Data {
        let unixTime = Date().timeIntervalSince1970
        let seconds = UInt64(unixTime) + tai64nBase
        let nanoseconds = UInt32((unixTime - floor(unixTime)) * nanosecondsPerSecond)
        return withUnsafeBytes(of: seconds.bigEndian) { Data($0) }
            + withUnsafeBytes(of: nanoseconds.bigEndian) { Data($0) }
    }

    private struct Handshake {
        let localIndex: UInt32
        let transcript: WireGuardHandshake.InitiatorTranscript
        let mac1: Data
        let created: TimeInterval
    }

    /// Counters and replay history belong to one key generation, not the lifetime of the peer.
    struct TransportKeypair {
        private let id = UUID()
        let localIndex: UInt32
        let created: TimeInterval
        let isInitiator: Bool
        private let remoteIndex: UInt32
        private let sendKey: Data
        private let receiveKey: Data
        private var sendCounter: UInt64
        private var replayWindow = ReplayWindow()

        init(localIndex: UInt32, remoteIndex: UInt32, sendKey: Data, receiveKey: Data,
             created: TimeInterval, isInitiator: Bool, initialSendCounter: UInt64 = 0) {
            self.localIndex = localIndex
            self.remoteIndex = remoteIndex
            self.sendKey = sendKey
            self.receiveKey = receiveKey
            self.created = created
            self.isInitiator = isInitiator
            self.sendCounter = initialSendCounter
        }

        var needsMessageRekey: Bool { sendCounter >= WireGuardPeer.rekeyAfterMessages }

        func isWithinLifetime(at time: TimeInterval) -> Bool {
            time - created < WireGuardPeer.rejectAfterTime
        }

        func owns(_ packet: PreparedPacket) -> Bool {
            id == packet.keypairID
        }

        /// Reserving consumes the nonce before worker encryption, even when the caller discards the snapshot.
        mutating func reserve(_ plaintext: Data, paddingLength: Int, at time: TimeInterval) throws -> PreparedPacket {
            guard isWithinLifetime(at: time) else { throw Error.sessionExpired }
            guard sendCounter < WireGuardPeer.rejectAfterMessages else { throw Error.counterExhausted }
            let packet = PreparedPacket(
                packet: plaintext, key: sendKey, remoteIndex: remoteIndex,
                counter: sendCounter, keypairID: id, paddingLength: paddingLength
            )
            sendCounter += 1
            return packet
        }

        /// Forged counters must not advance the replay window and discard valid traffic.
        /// See [WireGuard §5.4.6](https://www.wireguard.com/papers/wireguard.pdf#page=13) for authentication ordering.
        mutating func decrypt(_ message: WireGuardMessage.Transport, at time: TimeInterval) throws -> Data {
            guard isWithinLifetime(at: time) else { throw Error.sessionExpired }
            let counter = message.counter
            guard counter < WireGuardPeer.rejectAfterMessages else { throw Error.counterExhausted }
            let plaintext: Data
            do {
                plaintext = try WireGuardCrypto.open(key: receiveKey, counter: counter, ciphertext: message.ciphertext)
            } catch {
                throw Error.authenticationFailed
            }
            guard replayWindow.accept(counter) else { throw Error.replayedPacket }
            return plaintext
        }
    }

    /// Matches wireguard-go's 128-word ring and inclusive 8128-counter reorder distance.
    /// One word of slack lets advancing traffic clear whole words without discarding live bits.
    /// Reference ownership avoids copying the bitmap with TransportKeypair's temporary copies.
    final class ReplayWindow {
        // Ring sizing is implementation policy, matching [wireguard-go](https://github.com/WireGuard/wireguard-go/blob/1e2c3e5a3c14/replay/replay.go#L10-L17).
        // The spare word follows [RFC 6479 §2](https://www.rfc-editor.org/rfc/rfc6479.html#section-2).
        private static let blockBitLog = 6
        private static let blockBits = 1 << blockBitLog
        private static let ringBlocks = 1 << 7
        private static let windowSize = UInt64((ringBlocks - 1) * blockBits)
        private static let blockMask = UInt64(ringBlocks - 1)
        private static let bitMask = UInt64(blockBits - 1)

        private var highest: UInt64 = 0
        private var words = [UInt64](repeating: 0, count: ReplayWindow.ringBlocks)

        func accept(_ counter: UInt64) -> Bool {
            let block = counter >> Self.blockBitLog
            if counter > highest {
                clearAdvancingBlocks(after: highest >> Self.blockBitLog, through: block)
                highest = counter
            } else if highest - counter > Self.windowSize {
                return false
            }
            let word = Int(block & Self.blockMask)
            let bit = UInt64(1) << (counter & Self.bitMask)
            guard words[word] & bit == 0 else { return false }
            words[word] |= bit
            return true
        }

        private func clearAdvancingBlocks(after previous: UInt64, through current: UInt64) {
            let distance = min(current - previous, UInt64(Self.ringBlocks))
            guard distance > 0 else { return }
            // Sequential traffic clears one word per 64 packets; large jumps clear at most 128.
            for offset in 1...distance { words[Int((previous + offset) & Self.blockMask)] = 0 }
        }
    }
}
