//
//  SearchTokenRequest.swift
//  DuckDuckGo
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
import Networking

/// Makes the network request for a search token. Abstracted behind a protocol so `SearchTokenFetcher`
/// can be tested against a mock.
protocol SearchTokenRequesting {
    /// Requests a fresh search token, bound by the backend to the given `User-Agent` (and the caller's IP).
    /// Returns the token's `envelope`. Throws on transport error, non-2xx status, or a body that isn't the
    /// expected `{ "envelope": "<token>" }` JSON.
    func requestToken(userAgent: String) async throws -> String
}

/// Concrete `SearchTokenRequesting`: `GET`s the token endpoint (with a short timeout, since a warm that
/// takes long isn't useful), validates a 2xx status, and decodes the `envelope` from the JSON response.
struct SearchTokenRequest: SearchTokenRequesting {

    enum RequestError: Error {
        case malformedURL
        case unexpectedStatusCode(Int)
    }

    private struct Response: Decodable {
        let envelope: String
    }

    private let tokenURL: URL
    private let apiService: APIService

    init(tokenURL: URL, apiService: APIService = DefaultAPIService()) {
        self.tokenURL = tokenURL
        self.apiService = apiService
    }

    func requestToken(userAgent: String) async throws -> String {
        guard let request = APIRequestV2(
            url: tokenURL,
            headers: APIRequestV2.HeadersV2(userAgent: userAgent),
            timeoutInterval: 10 // best-effort warm — fail fast so a stalled request can't block refresh.
        ) else {
            throw RequestError.malformedURL
        }

        let response = try await apiService.fetch(request: request)
        guard (200..<300).contains(response.httpResponse.statusCode) else {
            throw RequestError.unexpectedStatusCode(response.httpResponse.statusCode)
        }

        let decoded: Response = try response.decodeBody()
        return decoded.envelope
    }
}
