//
//  NetworkProtectionErrorTests.swift
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

import Foundation
import XCTest
@testable import NetworkProtection

final class NetworkProtectionErrorTests: XCTestCase {

    /// Tests that `TunnelError`implements `CustomNSError`.
    ///
    func testThatNetworkProtectionErrorImplementsCustomNSError() {
        let genericError: Error = NetworkProtectionError.noServerRegistrationInfo

        XCTAssertNotNil(genericError as? CustomNSError)
    }

    /// Test that some `NetworkProtectionError` have no underlying errors.
    ///
    func testThatSomeErrorsHaveNoUnderlyingError() {
        let errorsWithoutUnderlyingError: [NetworkProtectionError] = [
            .noServerRegistrationInfo,
            .couldNotSelectClosestServer,
            .couldNotGetPeerPublicKey,
            .couldNotGetPeerHostName,
            .couldNotGetInterfaceAddressRange,
            .failedToEncodeRegisterKeyRequest,
            .invalidAuthToken,
            .serverListInconsistency,
            .wireGuardCannotLocateTunnelFileDescriptor,
            .wireGuardDnsResolution,
            .noAuthTokenFound,
            .vpnAccessRevoked,
            .failedToCastKeychainValueToData(field: "test"),
            .keychainReadError(field: "test", status: 1),
            .keychainWriteError(field: "test", status: 1),
            .keychainUpdateError(field: "test", status: 1),
            .keychainDeleteError(status: 1),
            .wireGuardInvalidState(reason: "test"),
        ]

        for error in errorsWithoutUnderlyingError {
            let nsError = error as NSError
            XCTAssertEqual(nsError.userInfo[NSUnderlyingErrorKey] as? NSError, nil)
        }
    }

    func testThatSomeErrorsHaveUnderlyingErrors() {
        let underlyingError = NSError(domain: "test", code: 1)

        let errorsWithUnderlyingError: [NetworkProtectionError] = [
            .failedToFetchServerList(underlyingError),
            .failedToParseServerListResponse(underlyingError),
            .failedToFetchLocationList(underlyingError),
            .failedToParseLocationListResponse(underlyingError),
            .failedToFetchRegisteredServers(underlyingError),
            .failedToParseRegisteredServersResponse(underlyingError),
            .wireGuardSetNetworkSettings(underlyingError),
            .startWireGuardBackend(underlyingError),
            .unhandledError(function: #function, line: #line, error: underlyingError),
        ]

        for error in errorsWithUnderlyingError {
            let nsError = error as NSError
            XCTAssertEqual(nsError.userInfo[NSUnderlyingErrorKey] as? NSError, underlyingError)
        }
    }
}
