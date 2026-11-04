//
//  WireGuardHandshakeAuthenticatorTests.swift
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

final class WireGuardHandshakeAuthenticatorTests: XCTestCase {
    func testOutgoingInitiationAndResponseMatchIndependentVectors() throws {
        for vector in try WireGuardTestData.handshakeVectors() {
            for isInitiator in [true, false] {
                let authenticator = try makeAuthenticator(vector, isInitiator: isInitiator)
                let expected = try bytes(vector, isInitiator ? "initiation" : "response")
                let authenticated = authenticator.authenticate(Data(expected.dropLast(32)), at: 1_000)
                XCTAssertEqual(authenticated.message, expected)
                XCTAssertEqual(authenticated.mac1, expected.suffix(32).prefix(16))
            }
        }
    }

    func testIncomingMAC1UsesTheRecipientsPublicKeyForBothMessageTypes() throws {
        for vector in try WireGuardTestData.handshakeVectors() {
            for isInitiator in [true, false] {
                let authenticator = try makeAuthenticator(vector, isInitiator: isInitiator)
                let message = try bytes(vector, isInitiator ? "response" : "initiation")
                let body = Data(message.dropLast(32))
                let mac1 = Data(message.suffix(32).prefix(16))
                XCTAssertNoThrow(try authenticator.validateMAC1(mac1, for: body))
                let wrongRecipient = try makeAuthenticator(vector, isInitiator: !isInitiator)
                assertAuthenticationFailure { try wrongRecipient.validateMAC1(mac1, for: body) }
            }
        }
    }

    func testModifiedBodyAndInvalidMAC1AreRejected() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        let authenticator = try makeAuthenticator(vector, isInitiator: false)
        let message = try bytes(vector, "initiation")
        let body = Data(message.dropLast(32))
        let mac1 = Data(message.suffix(32).prefix(16))
        var forgedBody = body
        forgedBody[0] ^= 1
        assertAuthenticationFailure { try authenticator.validateMAC1(mac1, for: forgedBody) }
        for offset in mac1.indices {
            var forgedMAC = mac1
            forgedMAC[offset] ^= 1
            assertAuthenticationFailure { try authenticator.validateMAC1(forgedMAC, for: body) }
        }
        for invalidMAC in [Data(), Data(mac1.prefix(15)), mac1 + Data([0])] {
            assertAuthenticationFailure { try authenticator.validateMAC1(invalidMAC, for: body) }
        }
        XCTAssertNoThrow(try authenticator.validateMAC1(mac1, for: body))
    }

    func testAuthenticatedCookieEnablesMAC2AgainstIndependentVectors() throws {
        for vector in try WireGuardTestData.handshakeVectors() {
            var authenticator = try makeAuthenticator(vector)
            let initiation = try bytes(vector, "initiation")
            let authenticated = authenticator.authenticate(Data(initiation.dropLast(32)), at: 1_000)
            let reply = try cookieReply(bytes(vector, "cookie_reply"))
            try authenticator.cacheCookie(reply, authenticating: authenticated.mac1, at: 1_000)
            let retry = authenticator.authenticate(Data(initiation.dropLast(32)), at: 1_005)
            XCTAssertEqual(retry.message, try bytes(vector, "cookie_retry"))
            XCTAssertEqual(retry.mac1, authenticated.mac1)
        }
    }

    func testCachedCookieExpiresAtTheRefreshBoundary() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        var authenticator = try makeAuthenticator(vector)
        let initiation = try bytes(vector, "initiation")
        let body = Data(initiation.dropLast(32))
        let mac1 = authenticator.authenticate(body, at: 1_000).mac1
        try authenticator.cacheCookie(cookieReply(bytes(vector, "cookie_reply")), authenticating: mac1, at: 1_000)
        for age: TimeInterval in [0, 119.999, 120, 120.001] {
            let expected = try bytes(vector, age < 120 ? "cookie_retry" : "initiation")
            XCTAssertEqual(authenticator.authenticate(body, at: 1_000 + age).message, expected, "cookie age \(age)")
        }
    }

    func testCookieIsBoundToTheRemoteIdentityAndHandshakeMAC1() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        var authenticator = try makeAuthenticator(vector)
        let initiation = try bytes(vector, "initiation")
        let body = Data(initiation.dropLast(32))
        let mac1 = authenticator.authenticate(body, at: 1_000).mac1
        let reply = try cookieReply(bytes(vector, "cookie_reply"))
        var wrongMAC1 = mac1
        wrongMAC1[0] ^= 1
        assertAuthenticationFailure { try authenticator.cacheCookie(reply, authenticating: wrongMAC1, at: 1_000) }
        XCTAssertEqual(authenticator.authenticate(body, at: 1_005).message, initiation)

        var wrongPeer = try makeAuthenticator(vector, isInitiator: false)
        assertAuthenticationFailure { try wrongPeer.cacheCookie(reply, authenticating: mac1, at: 1_000) }
        try authenticator.cacheCookie(reply, authenticating: mac1, at: 1_000)
        XCTAssertEqual(authenticator.authenticate(body, at: 1_005).message, try bytes(vector, "cookie_retry"))
    }

    func testInvalidCookieDoesNotReplaceTheCacheOrRefreshItsAge() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        let initiation = try bytes(vector, "initiation")
        let body = Data(initiation.dropLast(32))
        let cookie = try bytes(vector, "cookie_reply")
        let expectedRetry = try bytes(vector, "cookie_retry")
        for offset in [8, 31, 32, 63] {
            var authenticator = try makeAuthenticator(vector)
            let mac1 = authenticator.authenticate(body, at: 1_000).mac1
            try authenticator.cacheCookie(cookieReply(cookie), authenticating: mac1, at: 1_000)
            var forged = cookie
            forged[offset] ^= 1
            let invalidReply = try cookieReply(forged)
            assertAuthenticationFailure { try authenticator.cacheCookie(invalidReply, authenticating: mac1, at: 1_119) }
            XCTAssertEqual(authenticator.authenticate(body, at: 1_119.999).message, expectedRetry)
            XCTAssertEqual(authenticator.authenticate(body, at: 1_120).message, initiation)
        }
    }

    func testAuthenticatedCookieRefreshesItsLifetime() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        var authenticator = try makeAuthenticator(vector)
        let initiation = try bytes(vector, "initiation")
        let body = Data(initiation.dropLast(32))
        let mac1 = authenticator.authenticate(body, at: 1_000).mac1
        let reply = try cookieReply(bytes(vector, "cookie_reply"))
        try authenticator.cacheCookie(reply, authenticating: mac1, at: 1_000)
        try authenticator.cacheCookie(reply, authenticating: mac1, at: 1_119)
        XCTAssertEqual(authenticator.authenticate(body, at: 1_238.999).message, try bytes(vector, "cookie_retry"))
        XCTAssertEqual(authenticator.authenticate(body, at: 1_239).message, initiation)
    }

    func testResetClearsTheCookieAndKeepsIdentityKeys() throws {
        let vector = try XCTUnwrap(WireGuardTestData.handshakeVectors().first)
        var authenticator = try makeAuthenticator(vector)
        let initiation = try bytes(vector, "initiation")
        let body = Data(initiation.dropLast(32))
        let mac1 = authenticator.authenticate(body, at: 1_000).mac1
        let reply = try cookieReply(bytes(vector, "cookie_reply"))
        try authenticator.cacheCookie(reply, authenticating: mac1, at: 1_000)
        authenticator.reset()
        XCTAssertEqual(authenticator.authenticate(body, at: 1_005).message, initiation)
        let response = try bytes(vector, "response")
        XCTAssertNoThrow(try authenticator.validateMAC1(Data(response.suffix(32).prefix(16)), for: Data(response.dropLast(32))))
        try authenticator.cacheCookie(reply, authenticating: mac1, at: 1_005)
        XCTAssertEqual(authenticator.authenticate(body, at: 1_005).message, try bytes(vector, "cookie_retry"))
    }

    private func makeAuthenticator(_ vector: [String: Any], isInitiator: Bool = true) throws -> WireGuardHandshakeAuthenticator {
        WireGuardHandshakeAuthenticator(
            publicKey: try bytes(vector, isInitiator ? "initiator_public" : "responder_public"),
            peerPublicKey: try bytes(vector, isInitiator ? "responder_public" : "initiator_public")
        )
    }

    private func cookieReply(_ datagram: Data) throws -> WireGuardMessage.CookieReply {
        guard case .cookieReply(let message) = try WireGuardMessage.decode(datagram) else { throw WireGuardPeer.Error.invalidMessage }
        return message
    }

    private func bytes(_ vector: [String: Any], _ key: String) throws -> Data {
        try WireGuardTestData.hexBytes(XCTUnwrap(vector[key] as? String))
    }

    private func assertAuthenticationFailure(file: StaticString = #filePath, line: UInt = #line, _ operation: () throws -> Void) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? WireGuardPeer.Error, .authenticationFailed, file: file, line: line)
        }
    }
}
