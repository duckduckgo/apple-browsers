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
        let sanitized = tunnelError.sanitizedForXPC()

        if let sanitizedError = sanitized as? SanitizedError {
            let wrappedNSError = sanitizedError.wrappedError as NSError
            XCTAssertEqual(wrappedNSError.domain, "VPN.PacketTunnelProvider.TunnelError")
            XCTAssertEqual(wrappedNSError.code, 100)

            let errorUserInfo = sanitizedError.errorUserInfo
            XCTAssertEqual(errorUserInfo["OriginalErrorDomain"] as? String, "VPN.PacketTunnelProvider.TunnelError")
            XCTAssertEqual(errorUserInfo["OriginalErrorCode"] as? Int, 100)
            XCTAssertEqual(errorUserInfo["OriginalErrorDescription"] as? String, "VPN disconnected due to expired subscription")
        } else {
            XCTFail("Expected SanitizedError, but got \(type(of: sanitized))")
        }
    }

    func testStartingTunnelWithoutAuthTokenWithUnsafeInternalErrorIsWrapped() {
        let internalError = NSError(domain: "TestError", code: 1, userInfo: [
            "unsafe": UnsafeTestClass()
        ])

        let tunnelError = PacketTunnelProvider.TunnelError.startingTunnelWithoutAuthToken(internalError: internalError)
        let sanitized = tunnelError.sanitizedForXPC()

        if let sanitizedError = sanitized as? SanitizedError {
            let wrappedNSError = sanitizedError.wrappedError as NSError
            XCTAssertEqual(wrappedNSError.domain, "VPN.PacketTunnelProvider.TunnelError")
            XCTAssertEqual(wrappedNSError.code, 0)

            let errorUserInfo = sanitizedError.errorUserInfo
            XCTAssertEqual(errorUserInfo["OriginalErrorDomain"] as? String, "VPN.PacketTunnelProvider.TunnelError")
            XCTAssertEqual(errorUserInfo["OriginalErrorCode"] as? Int, 0)
            XCTAssertTrue((errorUserInfo["OriginalErrorDescription"] as? String)?.contains("Missing auth token at startup") == true)
        } else {
            XCTFail("Expected SanitizedError, but got \(type(of: sanitized))")
        }
    }

    func testSanitizeTunnelErrorWithUnderlyingError() {
        let underlyingError = NSError(domain: "TestError", code: 1, userInfo: [
            "unsafe": UnsafeTestClass()
        ])

        let tunnelError = PacketTunnelProvider.TunnelError.couldNotGenerateTunnelConfiguration(
            internalError: underlyingError
        )

        let sanitizedTunnelError = tunnelError.sanitizedForXPC()

        if let sanitizedError = sanitizedTunnelError as? SanitizedError {
            let wrappedNSError = sanitizedError.wrappedError as NSError
            XCTAssertEqual(wrappedNSError.domain, "VPN.PacketTunnelProvider.TunnelError")
            XCTAssertEqual(wrappedNSError.code, 1)

            let errorUserInfo = sanitizedError.errorUserInfo
            XCTAssertEqual(errorUserInfo["OriginalErrorDomain"] as? String, "VPN.PacketTunnelProvider.TunnelError")
            XCTAssertEqual(errorUserInfo["OriginalErrorCode"] as? Int, 1)
            XCTAssertTrue((errorUserInfo["OriginalErrorDescription"] as? String)?.contains("Failed to generate a tunnel configuration") == true)
        } else {
            XCTFail("Expected SanitizedError, but got \(type(of: sanitizedTunnelError))")
        }
    }

    func testSanitizedTunnelErrorIsXPCSafe() {
        let internalError = NSError(domain: "TestError", code: 1, userInfo: [
            "unsafe": UnsafeTestClass()
        ])

        let error = PacketTunnelProvider.TunnelError.couldNotGenerateTunnelConfiguration(internalError: internalError)
        let sanitized = error.sanitizedForXPC() as NSError
        XCTAssertNoThrow(try NSKeyedArchiver.archivedData(withRootObject: sanitized, requiringSecureCoding: true))
    }

    func testSanitizedErrorUserInfoIsMinimal() {
        let unsafeError = NSError(domain: "TestError", code: 1, userInfo: [
            "unsafe": UnsafeTestClass()
        ])

        let sanitized = XPCErrorSanitizer.sanitize(unsafeError)
        let ns = sanitized as NSError
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

        if let sanitizedError = sanitized as? SanitizedError {
            let wrappedNSError = sanitizedError.wrappedError as NSError
            XCTAssertEqual(wrappedNSError.domain, "TopDomain")
            XCTAssertEqual(wrappedNSError.code, 1)
            let ns = sanitized as NSError
            XCTAssertNoThrow(try NSKeyedArchiver.archivedData(withRootObject: ns, requiringSecureCoding: true))
        } else {
            XCTFail("Expected SanitizedError for nested underlying chain")
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

        let error = tunnelError.sanitizedForXPC() as NSError
        XCTAssertNoThrow(try NSKeyedArchiver.archivedData(withRootObject: error, requiringSecureCoding: true))
    }

    func testTunnelErrorWithDepth3NestedUnsafeUnderlyingErrors() {
        let tunnelError = PacketTunnelProvider.TunnelError.couldNotGenerateTunnelConfiguration(
            internalError: createNestedUnsafeError()
        )

        let sanitized = tunnelError.sanitizedForXPC()

        if let sanitizedError = sanitized as? SanitizedError {
            let wrappedNSError = sanitizedError.wrappedError as NSError
            XCTAssertEqual(wrappedNSError.domain, "VPN.PacketTunnelProvider.TunnelError")
            XCTAssertEqual(wrappedNSError.code, 1)

            let ns = sanitized as NSError
            XCTAssertNoThrow(try NSKeyedArchiver.archivedData(withRootObject: ns, requiringSecureCoding: true))

            let errorUserInfo = sanitizedError.errorUserInfo
            XCTAssertEqual(errorUserInfo["OriginalErrorDomain"] as? String, "VPN.PacketTunnelProvider.TunnelError")
            XCTAssertEqual(errorUserInfo["OriginalErrorCode"] as? Int, 1)
            XCTAssertTrue((errorUserInfo["OriginalErrorDescription"] as? String)?.contains("Failed to generate a tunnel configuration") == true)
        } else {
            XCTFail("Expected SanitizedError, but got \(type(of: sanitized))")
        }
    }

    func testTunnelErrorWithDepth3NestedUnsafeUnderlyingErrorsForVpnAccessRevoked() {
        let tunnelError = PacketTunnelProvider.TunnelError.vpnAccessRevoked(createNestedUnsafeError())
        let sanitized = tunnelError.sanitizedForXPC()

        if let sanitizedError = sanitized as? SanitizedError {
            let wrappedNSError = sanitizedError.wrappedError as NSError
            XCTAssertEqual(wrappedNSError.domain, "VPN.PacketTunnelProvider.TunnelError")
            XCTAssertEqual(wrappedNSError.code, 100)

            let ns = sanitized as NSError
            XCTAssertNoThrow(try NSKeyedArchiver.archivedData(withRootObject: ns, requiringSecureCoding: true))

            let errorUserInfo = sanitizedError.errorUserInfo
            XCTAssertEqual(errorUserInfo["OriginalErrorDomain"] as? String, "VPN.PacketTunnelProvider.TunnelError")
            XCTAssertEqual(errorUserInfo["OriginalErrorCode"] as? Int, 100)
            XCTAssertEqual(errorUserInfo["OriginalErrorDescription"] as? String, "VPN disconnected due to expired subscription")
        } else {
            XCTFail("Expected SanitizedError, but got \(type(of: sanitized))")
        }
    }

    func testTunnelErrorWithDepth3NestedUnsafeUnderlyingErrorsForStartingTunnelWithoutAuthToken() {
        let tunnelError = PacketTunnelProvider.TunnelError.startingTunnelWithoutAuthToken(
            internalError: createNestedUnsafeError()
        )

        let sanitized = tunnelError.sanitizedForXPC()

        if let sanitizedError = sanitized as? SanitizedError {
            let wrappedNSError = sanitizedError.wrappedError as NSError
            XCTAssertEqual(wrappedNSError.domain, "VPN.PacketTunnelProvider.TunnelError")
            XCTAssertEqual(wrappedNSError.code, 0)

            let ns = sanitized as NSError
            XCTAssertNoThrow(try NSKeyedArchiver.archivedData(withRootObject: ns, requiringSecureCoding: true))

            let errorUserInfo = sanitizedError.errorUserInfo
            XCTAssertEqual(errorUserInfo["OriginalErrorDomain"] as? String, "VPN.PacketTunnelProvider.TunnelError")
            XCTAssertEqual(errorUserInfo["OriginalErrorCode"] as? Int, 0)
            XCTAssertTrue((errorUserInfo["OriginalErrorDescription"] as? String)?.contains("Missing auth token at startup") == true)
        } else {
            XCTFail("Expected SanitizedError, but got \(type(of: sanitized))")
        }
    }

    private func createNestedUnsafeError() -> Error {
        let bottomError = NSError(domain: "BottomDomain", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Bottom level error"
        ])

        let middleError = NSError(domain: "MiddleDomain", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Middle level error",
            NSUnderlyingErrorKey: bottomError
        ])

        let topError = NSError(domain: "TopDomain", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Top level error",
            "unsafeTopObject": UnsafeTestClass(),
            NSUnderlyingErrorKey: middleError
        ])

        return topError
    }
}

private class UnsafeTestClass: NSObject {
    override var description: String {
        return "UnsafeTestClass instance"
    }
}
