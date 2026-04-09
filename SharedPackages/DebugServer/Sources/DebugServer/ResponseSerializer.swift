//
//  ResponseSerializer.swift
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

/// Serializes an `HTTPResponse` into raw HTTP response data.
public struct ResponseSerializer: Sendable {

    public init() {}

    /// Converts an `HTTPResponse` into raw bytes suitable for writing to a TCP connection.
    ///
    /// - Parameter response: The response to serialize.
    /// - Returns: The raw HTTP response data.
    public func serialize(_ response: HTTPResponse) -> Data {
        var result = "HTTP/1.1 \(response.status.rawValue) \(response.status.reasonPhrase)\r\n"

        var headers = response.headers
        let bodyData = response.body ?? Data()

        if headers["Content-Length"] == nil {
            headers["Content-Length"] = "\(bodyData.count)"
        }
        if headers["Connection"] == nil {
            headers["Connection"] = "close"
        }

        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            result += "\(key): \(value)\r\n"
        }

        result += "\r\n"

        var data = result.data(using: .utf8) ?? Data()
        data.append(bodyData)
        return data
    }
}
