//
//  XPCErrorSanitizerTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

final class XPCErrorSanitizerTests: XCTestCase {

    func testSanitizeSimpleError() {
        let safeError = NSError(domain: "TestError", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Test error"
        ])

        let sanitized = XPCErrorSanitizer.sanitize(safeError)

        XCTAssertEqual((sanitized as NSError).domain, "TestError")
        XCTAssertEqual((sanitized as NSError).code, 1)
        XCTAssertEqual((sanitized as NSError).localizedDescription, "Test error")
    }

    func testSanitizingTunnelErrorThatDoesNotNeedSanitizingDoesNotModifyIt() {
        let safeError = NSError(domain: "TestError", code: 1)
        let tunnelError = PacketTunnelProvider.TunnelError.vpnAccessRevoked(safeError)
        let sanitized = XPCErrorSanitizer.sanitize(tunnelError)

        XCTAssert(sanitized is PacketTunnelProvider.TunnelError)
        XCTAssertEqual((sanitized as NSError).domain, "VPN.PacketTunnelProvider.TunnelError")
        XCTAssertEqual((sanitized as NSError).code, 100)
        XCTAssertEqual((sanitized as NSError).localizedDescription, "VPN disconnected due to expired subscription")
    }

    func testVpnAccessRevokedWithUnsafeUnderlyingIsWrapped() {
        let unsafeUnderlying = NSError(domain: "SubscriptionDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Access revoked",
            "object": UnsafeTestClass()
        ])

        let tunnelError = PacketTunnelProvider.TunnelError.vpnAccessRevoked(unsafeUnderlying)
        let sanitized = tunnelError.sanitizedForXPC

        if case .vpnAccessRevoked(let sanitizedUnderlying) = sanitized {
            if case PacketTunnelProvider.TunnelError.xpcIncompatibleError(let original) = sanitizedUnderlying {
                let nsError = original as NSError
                XCTAssertEqual(nsError.domain, "SubscriptionDomain")
                XCTAssertEqual(nsError.code, 42)
            } else {
                XCTFail("Expected xpcIncompatibleError for underlying")
            }
        } else {
            XCTFail("Expected vpnAccessRevoked case")
        }
    }

    func testStartingTunnelWithoutAuthTokenWithUnsafeInternalErrorIsWrapped() {
        let internalError = NSError(domain: "TestError", code: 1, userInfo: [
            "unsafe": UnsafeTestClass()
        ])

        let tunnelError = PacketTunnelProvider.TunnelError.startingTunnelWithoutAuthToken(internalError: internalError)
        let sanitized = tunnelError.sanitizedForXPC

        if case .startingTunnelWithoutAuthToken(let maybeError) = sanitized {
            guard let error = maybeError else { return XCTFail("Expected internal error present") }
            if case PacketTunnelProvider.TunnelError.xpcIncompatibleError(let original) = error {
                let ns = original as NSError
                XCTAssertEqual(ns.domain, "TestError")
                XCTAssertEqual(ns.code, 1)
            } else {
                XCTFail("Expected xpcIncompatibleError for internal error")
            }
        } else {
            XCTFail("Expected startingTunnelWithoutAuthToken case")
        }
    }

    func testSanitizeTunnelErrorWithUnderlyingError() {
        let underlyingError = NSError(domain: "TestError", code: 1, userInfo: [
            "unsafe": UnsafeTestClass()
        ])

        let tunnelError = PacketTunnelProvider.TunnelError.couldNotGenerateTunnelConfiguration(
            internalError: underlyingError
        )

        let sanitizedTunnelError = tunnelError.sanitizedForXPC

        if case .couldNotGenerateTunnelConfiguration(let sanitizedInternal) = sanitizedTunnelError {
            if case PacketTunnelProvider.TunnelError.xpcIncompatibleError(let underlying) = sanitizedInternal {
                let underlyingNSError = underlying as NSError
                XCTAssertEqual(underlyingNSError.domain, "TestError")
                XCTAssertEqual(underlyingNSError.code, 1)
            } else {
                XCTFail("Expected xpcIncompatibleError wrapper for underlying")
            }
        } else {
            XCTFail("Expected couldNotGenerateTunnelConfiguration case")
        }
    }

    func testSanitizedTunnelErrorIsXPCSafe() {
        let internalError = NSError(domain: "TestError", code: 1, userInfo: [
            "unsafe": UnsafeTestClass()
        ])

        let error = PacketTunnelProvider.TunnelError.couldNotGenerateTunnelConfiguration(internalError: internalError)
        let sanitized = error.sanitizedForXPC as NSError
        XCTAssertNoThrow(try NSKeyedArchiver.archivedData(withRootObject: sanitized, requiringSecureCoding: true))
    }

    func testXpcIncompatibleErrorUserInfoIsMinimal() {
        let unsafeError = NSError(domain: "TestError", code: 1, userInfo: [
            "unsafe": UnsafeTestClass()
        ])

        let wrapped = PacketTunnelProvider.TunnelError.xpcIncompatibleError(underlyingError: unsafeError)
        let ns = wrapped as NSError
        let keys = Set(ns.userInfo.keys.map { String(describing: $0) })
        XCTAssertEqual(keys, ["OriginalErrorDomain", "OriginalErrorCode", "OriginalErrorDescription"])
    }

    func testNestedUnderlyingUnsafeCausesWrapper() {
        let bottom = NSError(domain: "BottomDomain", code: 3, userInfo: [
            "unsafe": UnsafeTestClass()
        ])

        let middle = NSError(domain: "MiddleDomain", code: 2, userInfo: [
            NSUnderlyingErrorKey: bottom
        ])

        let top = NSError(domain: "TopDomain", code: 1, userInfo: [
            NSUnderlyingErrorKey: middle
        ])

        let sanitized = XPCErrorSanitizer.sanitize(top)

        if case PacketTunnelProvider.TunnelError.xpcIncompatibleError(let underlying) = sanitized {
            let underlyingNSError = underlying as NSError
            XCTAssertEqual(underlyingNSError.domain, "TopDomain")
            XCTAssertEqual(underlyingNSError.code, 1)
            let ns = sanitized as NSError
            XCTAssertNoThrow(try NSKeyedArchiver.archivedData(withRootObject: ns, requiringSecureCoding: true))
        } else {
            XCTFail("Expected xpcIncompatibleError for nested underlying chain")
        }
    }

    func testErrorExtensionSanitizedForXPC() {
        let error = NSError(domain: "TestError", code: 1, userInfo: [
            "unsafeKey": UnsafeTestClass()
        ])

        let sanitized = error.sanitizedForXPC()
        let directSanitized = XPCErrorSanitizer.sanitize(error)

        XCTAssertEqual((sanitized as NSError).domain, (directSanitized as NSError).domain)
        XCTAssertEqual((sanitized as NSError).code, (directSanitized as NSError).code)
    }

    func testCouldNotGenerateTunnelConfigurationWithUnsafeInternalErrorIsArchivable() {
        let underlyingError = NSError(domain: "TestError", code: 1, userInfo: [
            "object": UnsafeTestClass()
        ])

        let tunnelError = PacketTunnelProvider.TunnelError.couldNotGenerateTunnelConfiguration(
            internalError: underlyingError
        )

        let error = tunnelError.sanitizedForXPC as NSError
        XCTAssertNoThrow(try NSKeyedArchiver.archivedData(withRootObject: error, requiringSecureCoding: true))
    }
}

private class UnsafeTestClass: NSObject {
    override var description: String {
        return "UnsafeTestClass instance"
    }
}
