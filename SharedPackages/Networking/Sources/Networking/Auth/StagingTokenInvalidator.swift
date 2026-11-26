//
//  StagingTokenInvalidator.swift
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

import DDGError
import Foundation

/// Invalidates a refresh token on the staging Auth API, for debug tools that need a dead token.
public struct StagingTokenInvalidator {

    public enum Error: DDGError {
        /// The refresh token is empty or the request can't be built.
        case invalidRequest
        /// The Auth API answered with a status code outside 200–299.
        case unexpectedStatusCode(Int)

        public static var errorDomain: String { "com.duckduckgo.networking.StagingTokenInvalidator" }

        public var errorCode: Int {
            switch self {
            case .invalidRequest:
                return 1
            case .unexpectedStatusCode:
                return 2
            }
        }

        public var underlyingError: (any Swift.Error)? { nil }

        public var description: String {
            switch self {
            case .invalidRequest:
                return "Invalid invalidate request"
            case .unexpectedStatusCode(let statusCode):
                return "Unexpected status code \(statusCode)"
            }
        }
    }

    private let apiService: APIService

    /// - Returns: nil unless `environment` is staging.
    public init?(environment: OAuthEnvironment, apiService: APIService) {
        guard environment == .staging else { return nil }
        self.apiService = apiService
    }

    /// Calls `POST /api/auth/v2/invalidate` for `refreshToken`.
    /// - Throws: `Error.unexpectedStatusCode` for a response outside 200–299, or the request error.
    public func invalidate(refreshToken: String) async throws {
        guard !refreshToken.isEmpty,
              let request = APIRequestV2(url: OAuthEnvironment.staging.url.appendingPathComponent("/api/auth/v2/invalidate"),
                                         method: .post,
                                         queryItems: [(key: "refresh_token", value: refreshToken)]) else {
            throw Error.invalidRequest
        }
        let response = try await apiService.fetch(request: request)
        let statusCode = response.httpResponse.statusCode
        guard (200..<300).contains(statusCode) else {
            throw Error.unexpectedStatusCode(statusCode)
        }
    }
}
