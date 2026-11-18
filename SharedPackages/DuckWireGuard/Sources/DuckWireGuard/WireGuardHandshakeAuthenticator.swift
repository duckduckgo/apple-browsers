//
//  WireGuardHandshakeAuthenticator.swift
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

/// Keeps cookie authentication separate from Noise and handshake lifecycle decisions.
/// The peer must select a live handshake's MAC1 before accepting a cookie reply.
struct WireGuardHandshakeAuthenticator {
    private typealias Failure = WireGuardPeer.Error

    // Public domain-separation labels: [WireGuard §5.4](https://www.wireguard.com/papers/wireguard.pdf#page=10).
    private static let mac1Label = Data("mac1----".utf8)
    private static let cookieLabel = Data("cookie--".utf8)
    // Cookies follow the rotating two-minute secret: [WireGuard §5.4.7](https://www.wireguard.com/papers/wireguard.pdf#page=13).
    private static let cookieLifetime: TimeInterval = 120
    private static let cookieLength = 16

    private let inboundMac1Key: Data
    private let outboundMac1Key: Data
    private let cookieKey: Data
    private var cookie: (value: Data, received: TimeInterval)?

    init(publicKey: Data, peerPublicKey: Data) {
        inboundMac1Key = WireGuardCrypto.hash(Self.mac1Label + publicKey)
        outboundMac1Key = WireGuardCrypto.hash(Self.mac1Label + peerPublicKey)
        cookieKey = WireGuardCrypto.hash(Self.cookieLabel + peerPublicKey)
    }

    /// A cheap MAC1 check precedes expensive Noise processing: [WireGuard §5.3](https://www.wireguard.com/papers/wireguard.pdf#page=8).
    func validateMAC1(_ mac1: Data, for body: Data) throws {
        guard WireGuardCrypto.constantTimeEqual(WireGuardCrypto.mac(key: inboundMac1Key, data: body), mac1) else {
            throw Failure.authenticationFailed
        }
    }

    /// Only a fresh server cookie enables MAC2: [WireGuard §5.4.4](https://www.wireguard.com/papers/wireguard.pdf#page=12).
    func authenticate(_ body: Data, at time: TimeInterval) -> (message: Data, mac1: Data) {
        let mac1 = WireGuardCrypto.mac(key: outboundMac1Key, data: body)
        var message = body + mac1
        if let cookie, time - cookie.received < Self.cookieLifetime {
            message += WireGuardCrypto.mac(key: cookie.value, data: message)
        } else {
            message += Data(repeating: 0, count: WireGuardCrypto.macLength)
        }
        return (message, mac1)
    }

    /// Bind a reply to the selected handshake's MAC1 before replacing the cache (WireGuard §5.4.7).
    mutating func cacheCookie(_ message: WireGuardMessage.CookieReply, authenticating mac1: Data, at time: TimeInterval) throws {
        let value: Data
        do {
            value = try WireGuardCrypto.openCookie(
                key: cookieKey, nonce: message.nonce, ciphertext: message.ciphertext, authenticating: mac1
            )
        } catch {
            throw Failure.authenticationFailed
        }
        guard value.count == Self.cookieLength else { throw Failure.authenticationFailed }
        cookie = (value, time)
    }

    mutating func reset() {
        cookie = nil
    }
}
