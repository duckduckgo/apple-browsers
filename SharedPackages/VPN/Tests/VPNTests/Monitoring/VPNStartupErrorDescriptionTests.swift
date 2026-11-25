//
//  VPNStartupErrorDescriptionTests.swift
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

import XCTest
@testable import VPN

final class VPNStartupErrorDescriptionTests: XCTestCase {
    func testTokenRefreshFailureDisplaysOAuthDomainAndCode() {
        let tokenError = NSError(domain: "com.duckduckgo.networking.OAuthClientError", code: 11003, userInfo: [
            NSLocalizedDescriptionKey: "Invalid token request",
            NSUnderlyingErrorKey: NSError(domain: "com.duckduckgo.networking.TokenStatus", code: 0)
        ])
        let providerError = PacketTunnelProvider.TunnelError.otherTunnelStartError(internalError: tokenError) as NSError
        let error = VPNStartupMonitor.StartupError.startTunnelDisconnectedSilently(underlyingError: providerError)

        let expected = NSError(domain: "com.duckduckgo.networking.OAuthClientError", code: 11003)
        XCTAssertEqual(error.disconnectReasonDescription, expected.localizedDescription)
    }

    func testSystemDisconnectDisplaysSystemDomainAndCode() {
        let systemError = NSError(domain: "NEVPNConnectionErrorDomain", code: 14,
                                  userInfo: [NSLocalizedDescriptionKey: "The VPN app is not installed."])
        let error = VPNStartupMonitor.StartupError.startTunnelDisconnectedSilently(underlyingError: systemError)

        let expected = NSError(domain: "NEVPNConnectionErrorDomain", code: 14)
        XCTAssertEqual(error.disconnectReasonDescription, expected.localizedDescription)
    }

    func testDisconnectWithoutUnderlyingErrorHasNoReasonDescription() {
        let error = VPNStartupMonitor.StartupError.startTunnelDisconnectedSilently(underlyingError: nil)
        XCTAssertNil(error.disconnectReasonDescription)
    }

    func testSanitizedTunnelAndCauseDisplayOriginalDomainAndCode() {
        let cause = NSError(domain: "TestService", code: 19)
        let provider = PacketTunnelProvider.TunnelError.otherTunnelStartError(internalError: cause)
        let sanitized = SanitizedError(wrappedError: provider, underlyingError: SanitizedError(wrappedError: cause, underlyingError: nil))
        let error = VPNStartupMonitor.StartupError.startTunnelDisconnectedSilently(underlyingError: sanitized)

        XCTAssertEqual(error.disconnectReasonDescription, cause.localizedDescription)
    }

    func testTimeoutHasNoDisconnectReasonDescription() {
        XCTAssertNil(VPNStartupMonitor.StartupError.startTunnelTimedOut.disconnectReasonDescription)
    }
}
