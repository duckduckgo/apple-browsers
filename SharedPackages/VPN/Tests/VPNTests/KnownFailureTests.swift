//
//  KnownFailureTests.swift
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
import Foundation
@testable import VPN

final class KnownFailureTests: XCTestCase {
    func testHardCodedErrorInitializer() {
        let error = NSError(domain: "SMAppServiceErrorDomain", code: 1)
        XCTAssertEqual(KnownFailure(error)!.error, KnownFailure.SilentError.operationNotPermitted.rawValue)
    }

    func testNonHardCodedErrorInitializer() {
        let internalError = NetworkProtectionClientError.failedToFetchRegisteredServers("404")
        let error = PacketTunnelProvider.TunnelError.couldNotGenerateTunnelConfiguration(internalError: internalError)
        XCTAssertEqual(KnownFailure(error)!.error, KnownFailure.SilentError.registeredServerFetchingFailed.rawValue)
    }
}

extension String: @retroactive Error {}
