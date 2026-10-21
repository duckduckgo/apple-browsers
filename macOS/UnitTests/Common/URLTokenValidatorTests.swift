//
//  URLTokenValidatorTests.swift
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
import Testing
@testable import DuckDuckGo_Privacy_Browser

final class URLTokenValidatorTests {
    @available(iOS 16, macOS 13, *)
    @Test("Token generation produces valid token with expected format", .timeLimit(.minutes(1)))
    func testGenerateToken() {
        let validator = URLTokenValidator.shared
        let url = URL(string: "https://example.com/")!
        let token = validator.generateToken(for: url)

        #expect(token.contains(":"), "Token should contain a colon separating the signature and timestamp")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Generated token is valid for the original URL", .timeLimit(.minutes(1)))
    func testValidateToken() {
        let validator = URLTokenValidator.shared
        let url = URL(string: "https://example.com/")!
        let token = validator.generateToken(for: url)

        let isValid = validator.validateToken(token, for: url)
        #expect(isValid, "Token should be valid for the given URL")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Token is not valid for a different URL", .timeLimit(.minutes(1)))
    func testValidateTokenWithInvalidURL() {
        let validator = URLTokenValidator.shared
        let url = URL(string: "https://example.com/some-page")!
        let token = validator.generateToken(for: url)

        let invalidURL = URL(string: "https://example.com/other-page")!
        let isValid = validator.validateToken(token, for: invalidURL)
        #expect(!isValid, "Token should not be valid for a different URL")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Garbage token data is not valid", .timeLimit(.minutes(1)))
    func testValidateTokenWithGarbageData() {
        let validator = URLTokenValidator.shared
        let url = URL(string: "https://example.com/special-page")!
        let garbageToken = "Dxa0cx+a51qfucPFMxqIbAiuQHFJx/2TYseu73ww"

        let isValid = validator.validateToken(garbageToken, for: url)
        #expect(!isValid, "Token should not be valid for the given URL when the token is garbage data")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Token with expired timestamp is not valid", .timeLimit(.minutes(1)))
    func testValidateTokenWithExpiredTimestamp() throws {
        let validator = URLTokenValidator.shared
        let url = URL(string: "https://example.com/")!
        let token = validator.generateToken(for: url)

        // Simulate an expired token by manipulating the timestamp
        let components = token.split(separator: ":")
        #expect(components.count == 2, "Token format is invalid")
        let timestampString = try #require(components[safe: 1], "Token format is invalid")

        let expiredTimestamp = String(Int(timestampString)! - Int(validator.timeWindow) - 1)
        let expiredToken = "\(components.first!):\(expiredTimestamp)"

        let isValid = validator.validateToken(expiredToken, for: url)
        #expect(!isValid, "Token should not be valid if the timestamp is expired")
    }
}
