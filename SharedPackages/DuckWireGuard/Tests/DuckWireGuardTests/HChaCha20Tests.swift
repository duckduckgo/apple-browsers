//
//  HChaCha20Tests.swift
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

final class HChaCha20Tests: XCTestCase {
    func testDraftSubkeyVector() throws {
        // https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha-03#section-2.2.1
        let key = Data((0..<32).map(UInt8.init))
        let nonce = try bytes("000000090000004a0000000031415927")
        XCTAssertEqual(try HChaCha20.deriveSubkey(key: key, nonce: nonce),
                       try bytes("82413b4227b27bfed30e42508a877d73a0f9e4d58a74a853c12ec41326d3ecdc"))
    }

    func testInvalidKeyLengthsAreRejected() {
        let nonce = Data(repeating: 0, count: 16)
        for length in [0, 31, 33] {
            XCTAssertThrowsError(try HChaCha20.deriveSubkey(key: Data(repeating: 1, count: length), nonce: nonce)) { error in
                guard case .invalidKeyLength? = error as? HChaCha20.Failure else {
                    return XCTFail("Expected invalidKeyLength for length \(length), got \(error)")
                }
            }
        }
    }

    func testInvalidNonceLengthsAreRejectedWithAValidKey() {
        let key = Data(repeating: 1, count: 32)
        for length in [0, 15, 17] {
            XCTAssertThrowsError(try HChaCha20.deriveSubkey(key: key, nonce: Data(repeating: 0, count: length))) { error in
                guard case .invalidNonceLength? = error as? HChaCha20.Failure else {
                    return XCTFail("Expected invalidNonceLength for length \(length), got \(error)")
                }
            }
        }
    }

    func testKeyValidationPrecedesNonceValidation() {
        XCTAssertThrowsError(try HChaCha20.deriveSubkey(key: Data(), nonce: Data())) { error in
            guard case .invalidKeyLength? = error as? HChaCha20.Failure else {
                return XCTFail("Expected invalidKeyLength before nonce validation, got \(error)")
            }
        }
    }

    private func bytes(_ hex: String) throws -> Data {
        try WireGuardTestData.hexBytes(hex)
    }
}
