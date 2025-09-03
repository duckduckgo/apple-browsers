//
//  OAuthCodesGenerator.swift
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
import CommonCrypto
import Common

/// Helper that generates codes used in the OAuth2 authentication process
struct OAuthCodesGenerator {

    public enum OAuthCodesGeneratorError: DDGError {
        case failedToLoadRandomBytes(Int32)

        public var description: String {
            switch self {
            case .failedToLoadRandomBytes(let errorCode):
                return "Failed to load random bytes \(errorCode)"
            }
        }

        public var errorDomain: String { "com.duckduckgo.networking.OAuthCodesGenerator" }

        public var errorCode: Int {
            switch self {
            case .failedToLoadRandomBytes:
                return 11100
            }
        }
    }

    /// https://auth0.com/docs/get-started/authentication-and-authorization-flow/authorization-code-flow-with-pkce/add-login-using-the-authorization-code-flow-with-pkce#create-code-verifier
    static func generateCodeVerifier() throws -> String {
        var buffer = [UInt8](repeating: 0, count: 128)
        let status = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)

        guard status == errSecSuccess else {
            throw OAuthCodesGeneratorError.failedToLoadRandomBytes(status)
        }
        return Data(buffer).base64EncodedString().replacingInvalidCharacters()
    }

    /// https://auth0.com/docs/get-started/authentication-and-authorization-flow/authorization-code-flow-with-pkce/add-login-using-the-authorization-code-flow-with-pkce#create-code-challenge
    static func codeChallenge(codeVerifier: String) -> String? {

        guard let data = codeVerifier.data(using: .utf8) else {
            assertionFailure("Failed to generate OAuth2 code challenge")
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes {
            CC_SHA256($0.baseAddress, CC_LONG(data.count), &buffer)
        }
        let hash = Data(buffer)
        return hash.base64EncodedString().replacingInvalidCharacters()
    }
}

fileprivate extension String {

    func replacingInvalidCharacters() -> String {
        self.replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
