//
//  HTTPRequest.swift
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

/// Represents a parsed HTTP request.
public protocol HTTPRequestProtocol: Sendable {
    var method: HTTPMethod { get }
    var path: String { get }
    var queryParameters: [String: String] { get }
    var headers: [String: String] { get }
    var body: Data? { get }
}

/// Concrete HTTP request parsed from raw data.
public struct HTTPRequest: HTTPRequestProtocol {
    public let method: HTTPMethod
    public let path: String
    public let queryParameters: [String: String]
    public let headers: [String: String]
    public let body: Data?

    public init(
        method: HTTPMethod,
        path: String,
        queryParameters: [String: String] = [:],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.queryParameters = queryParameters
        self.headers = headers
        self.body = body
    }
}
