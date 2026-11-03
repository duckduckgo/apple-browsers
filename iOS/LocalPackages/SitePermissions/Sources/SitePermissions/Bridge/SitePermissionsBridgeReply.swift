//
//  SitePermissionsBridgeReply.swift
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

/// Encodes a JSON-compatible dictionary as a content-scope reply.
///
/// The site permission bridges build their replies as dictionaries so that each reply keeps the shape
/// the content-scope features read. Values must be JSON types: `String`, `Bool`, numbers, `NSNull`,
/// and arrays or dictionaries of those.
struct SitePermissionsBridgeReply: Encodable {

    let payload: [String: Any]

    init(_ payload: [String: Any]) {
        self.payload = payload
    }

    func encode(to encoder: Encoder) throws {
        try JSONValue(payload).encode(to: encoder)
    }
}

private struct JSONValue: Encodable {

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        switch value {
        case let dictionary as [String: Any]:
            var container = encoder.container(keyedBy: Key.self)
            for (key, value) in dictionary {
                try container.encode(JSONValue(value), forKey: Key(stringValue: key))
            }
        case let array as [Any]:
            var container = encoder.unkeyedContainer()
            for value in array {
                try container.encode(JSONValue(value))
            }
        default:
            var container = encoder.singleValueContainer()
            switch value {
            case let bool as Bool:
                try container.encode(bool)
            case let int as Int:
                try container.encode(int)
            case let double as Double:
                try container.encode(double)
            case let string as String:
                try container.encode(string)
            case is NSNull:
                try container.encodeNil()
            default:
                throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath,
                                                              debugDescription: "Not a JSON value"))
            }
        }
    }
}
