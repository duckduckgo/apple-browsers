//
//  HTTPMethod.swift
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

/// HTTP request methods as defined in RFC 7231.
public enum HTTPMethod: String, Sendable, Hashable, CaseIterable {
    case GET
    case POST
    case PUT
    case DELETE
    case PATCH
    case HEAD
    case OPTIONS

    public init?(rawValue: String) {
        switch rawValue.uppercased() {
        case "GET": self = .GET
        case "POST": self = .POST
        case "PUT": self = .PUT
        case "DELETE": self = .DELETE
        case "PATCH": self = .PATCH
        case "HEAD": self = .HEAD
        case "OPTIONS": self = .OPTIONS
        default: return nil
        }
    }
}
