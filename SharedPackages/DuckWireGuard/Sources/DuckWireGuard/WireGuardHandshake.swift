//
//  WireGuardHandshake.swift
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

/// Produces authenticated Noise candidates; the peer alone decides whether to install them.
/// Attempt transcripts stay separate from the peer's replay, admission and keypair lifecycle state.
struct WireGuardHandshake {
    private typealias Failure = WireGuardPeer.Error

    // Public domain-separation values, not keys: [WireGuard §5.4](https://www.wireguard.com/papers/wireguard.pdf#page=10).
    private static let noiseConstruction = Data("Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s".utf8)
    private static let wireGuardIdentifier = Data("WireGuard v1 zx2c4 Jason@zx2c4.com".utf8)
    // Zero means no additional shared secret, not an embedded credential: [WireGuard §5.2](https://www.wireguard.com/papers/wireguard.pdf#page=7).
    private static let noPresharedKey = Data(repeating: 0, count: WireGuardCrypto.keyLength)

    private let localPrivateKey: Curve25519.KeyAgreement.PrivateKey
    private let remotePublicKey: Curve25519.KeyAgreement.PublicKey
    private let presharedKey: Data

    var publicKey: Data { localPrivateKey.publicKey.rawRepresentation }
    var peerPublicKey: Data { remotePublicKey.rawRepresentation }

    init(privateKey: Data, peerPublicKey: Data, presharedKey: Data?) throws {
        guard privateKey.count == WireGuardCrypto.keyLength, peerPublicKey.count == WireGuardCrypto.keyLength,
              presharedKey == nil || presharedKey?.count == WireGuardCrypto.keyLength else {
            throw Failure.invalidKey
        }
        do {
            localPrivateKey = try .init(rawRepresentation: privateKey)
            remotePublicKey = try .init(rawRepresentation: peerPublicKey)
            // Reject low-order public keys before any state is created.
            _ = try Self.sharedSecret(localPrivateKey, remotePublicKey)
        } catch {
            throw Failure.invalidKey
        }
        self.presharedKey = presharedKey ?? Self.noPresharedKey
    }

    struct InitiatorTranscript {
        fileprivate let ephemeral: Curve25519.KeyAgreement.PrivateKey
        fileprivate let chainingKey: Data
        fileprivate let hash: Data
    }

    struct VerifiedInitiation {
        let timestamp: Data
        fileprivate let ephemeral: Curve25519.KeyAgreement.PublicKey
        fileprivate let chainingKey: Data
        fileprivate let hash: Data
    }

    struct TransportKeys {
        let sendKey: Data
        let receiveKey: Data
    }

    struct Response {
        let payload: Data
        fileprivate let chainingKey: Data

        /// Responder key direction is reversed: [WireGuard §5.4.5](https://www.wireguard.com/papers/wireguard.pdf#page=12).
        func transportKeys() -> TransportKeys {
            let keys = WireGuardCrypto.kdf(key: chainingKey, input: Data(), count: 2)
            return TransportKeys(sendKey: keys[1], receiveKey: keys[0])
        }
    }

    /// The initiator transcript in [WireGuard §5.4.2](https://www.wireguard.com/papers/wireguard.pdf#page=10).
    func initiate(ephemeralPrivateKey: Data, timestamp: Data) throws -> (payload: Data, transcript: InitiatorTranscript) {
        let ephemeral: Curve25519.KeyAgreement.PrivateKey
        do {
            ephemeral = try .init(rawRepresentation: ephemeralPrivateKey)
        } catch {
            throw Failure.invalidKey
        }

        var (chainingKey, hash) = Self.initialTranscript(responderPublicKey: peerPublicKey)
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
            key: derived[1], counter: 0, plaintext: timestamp, authenticating: hash
        )
        hash = WireGuardCrypto.hash(hash + encryptedTimestamp)
        return (
            ephemeralPublicKey + encryptedStatic + encryptedTimestamp,
            InitiatorTranscript(ephemeral: ephemeral, chainingKey: chainingKey, hash: hash)
        )
    }

    /// Authenticate the initiator before the peer checks its timestamp watermark (WireGuard §5.4.2).
    func consumeInitiation(ephemeral: Data, encryptedStatic: Data, encryptedTimestamp: Data) throws -> VerifiedInitiation {
        let ephemeral = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeral)
        var (chainingKey, hash) = Self.initialTranscript(responderPublicKey: publicKey)
        hash = WireGuardCrypto.hash(hash + ephemeral.rawRepresentation)
        chainingKey = WireGuardCrypto.kdf(key: chainingKey, input: ephemeral.rawRepresentation, count: 1)[0]
        var derived = WireGuardCrypto.kdf(key: chainingKey, input: try Self.sharedSecret(localPrivateKey, ephemeral), count: 2)
        chainingKey = derived[0]
        let remoteStatic = try WireGuardCrypto.open(key: derived[1], counter: 0, ciphertext: encryptedStatic, authenticating: hash)
        guard WireGuardCrypto.constantTimeEqual(remoteStatic, peerPublicKey) else { throw Failure.authenticationFailed }
        hash = WireGuardCrypto.hash(hash + encryptedStatic)
        derived = WireGuardCrypto.kdf(key: chainingKey, input: try Self.sharedSecret(localPrivateKey, remotePublicKey), count: 2)
        chainingKey = derived[0]
        let timestamp = try WireGuardCrypto.open(key: derived[1], counter: 0, ciphertext: encryptedTimestamp, authenticating: hash)
        hash = WireGuardCrypto.hash(hash + encryptedTimestamp)
        return VerifiedInitiation(timestamp: timestamp, ephemeral: ephemeral, chainingKey: chainingKey, hash: hash)
    }

    /// The peer admits the timestamp before generating responder work: [WireGuard §5.4.3](https://www.wireguard.com/papers/wireguard.pdf#page=11).
    func respond(to incoming: VerifiedInitiation, ephemeralPrivateKey: Data) throws -> Response {
        let ephemeral = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: ephemeralPrivateKey)
        let ephemeralPublic = ephemeral.publicKey.rawRepresentation
        var hash = WireGuardCrypto.hash(incoming.hash + ephemeralPublic)
        var chainingKey = WireGuardCrypto.kdf(key: incoming.chainingKey, input: ephemeralPublic, count: 1)[0]
        chainingKey = WireGuardCrypto.kdf(key: chainingKey, input: try Self.sharedSecret(ephemeral, incoming.ephemeral), count: 1)[0]
        chainingKey = WireGuardCrypto.kdf(key: chainingKey, input: try Self.sharedSecret(ephemeral, remotePublicKey), count: 1)[0]
        let derived = WireGuardCrypto.kdf(key: chainingKey, input: presharedKey, count: 3)
        chainingKey = derived[0]
        hash = WireGuardCrypto.hash(hash + derived[1])
        let empty = try WireGuardCrypto.seal(key: derived[2], counter: 0, plaintext: Data(), authenticating: hash)
        return Response(payload: ephemeralPublic + empty, chainingKey: chainingKey)
    }

    /// Only successful response authentication yields transport keys (WireGuard §5.4.3–5.4.5).
    func complete(_ transcript: InitiatorTranscript, ephemeral: Data, encryptedEmpty: Data) throws -> TransportKeys {
        let remoteEphemeral: Curve25519.KeyAgreement.PublicKey
        do {
            remoteEphemeral = try .init(rawRepresentation: ephemeral)
        } catch {
            throw Failure.invalidKey
        }
        var hash = WireGuardCrypto.hash(transcript.hash + remoteEphemeral.rawRepresentation)
        var chainingKey = WireGuardCrypto.kdf(
            key: transcript.chainingKey, input: remoteEphemeral.rawRepresentation, count: 1
        )[0]
        chainingKey = WireGuardCrypto.kdf(
            key: chainingKey, input: try Self.sharedSecret(transcript.ephemeral, remoteEphemeral), count: 1
        )[0]
        chainingKey = WireGuardCrypto.kdf(
            key: chainingKey, input: try Self.sharedSecret(localPrivateKey, remoteEphemeral), count: 1
        )[0]
        let derived = WireGuardCrypto.kdf(key: chainingKey, input: presharedKey, count: 3)
        chainingKey = derived[0]
        hash = WireGuardCrypto.hash(hash + derived[1])
        do {
            let empty = try WireGuardCrypto.open(key: derived[2], counter: 0, ciphertext: encryptedEmpty, authenticating: hash)
            guard empty.isEmpty else { throw Failure.authenticationFailed }
        } catch {
            throw Failure.authenticationFailed
        }
        let keys = WireGuardCrypto.kdf(key: chainingKey, input: Data(), count: 2)
        return TransportKeys(sendKey: keys[0], receiveKey: keys[1])
    }

    /// Both roles bind the transcript to the responder's identity: [WireGuard §5.4.2](https://www.wireguard.com/papers/wireguard.pdf#page=10).
    private static func initialTranscript(responderPublicKey: Data) -> (chainingKey: Data, hash: Data) {
        let chainingKey = WireGuardCrypto.hash(noiseConstruction)
        let hash = WireGuardCrypto.hash(WireGuardCrypto.hash(chainingKey + wireGuardIdentifier) + responderPublicKey)
        return (chainingKey, hash)
    }

    private static func sharedSecret(_ privateKey: Curve25519.KeyAgreement.PrivateKey,
                                     _ publicKey: Curve25519.KeyAgreement.PublicKey) throws -> Data {
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
        let data = secret.withUnsafeBytes { Data($0) }
        guard data.contains(where: { $0 != 0 }) else { throw Failure.invalidKey }
        return data
    }
}
