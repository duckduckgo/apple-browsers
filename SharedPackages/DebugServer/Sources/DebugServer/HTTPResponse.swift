//
//  HTTPResponse.swift
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

/// An HTTP response to send back to the client.
public struct HTTPResponse: Sendable {
    public let status: HTTPStatusCode
    public let headers: [String: String]
    public let body: Data?

    public init(
        status: HTTPStatusCode,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

// MARK: - Convenience Initializers

public extension HTTPResponse {

    /// Creates a response with a JSON body and appropriate Content-Type header.
    static func json(_ data: Data, status: HTTPStatusCode = .ok) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    /// Creates a response with an HTML body and appropriate Content-Type header.
    static func html(_ string: String, status: HTTPStatusCode = .ok) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: string.data(using: .utf8)
        )
    }

    /// Creates a plain text response.
    static func text(_ string: String, status: HTTPStatusCode = .ok) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: string.data(using: .utf8)
        )
    }

    /// Creates an empty response with a given status code.
    static func empty(status: HTTPStatusCode = .noContent) -> HTTPResponse {
        HTTPResponse(status: status)
    }
}
