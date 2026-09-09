//
//  JSONValue.swift
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

/// A concrete JSON value, used where the MCP wire carries free-form JSON: tool input/output
/// schemas, tool arguments, and structured tool results.
///
/// Tools declare their schemas with Swift literals rather than parsing JSON strings, so a
/// malformed schema is a compile error instead of a runtime surprise:
///
/// ```swift
/// static let inputSchema: JSONValue = [
///     "type": "object",
///     "properties": ["limit": ["type": "integer", "minimum": 1, "maximum": 50]]
/// ]
/// ```
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Reading

public extension JSONValue {

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    /// Integers only — a JSON `1.5` is not silently truncated, so a tool can reject it as an
    /// invalid argument rather than acting on a rounded value.
    var intValue: Int? {
        guard case .int(let value) = self else { return nil }
        return value
    }

    subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }
}

// MARK: - Literals

// Deliberately not `ExpressibleByNilLiteral`: it would make `nil` mean JSON null, so an
// ordinary `optionalValue ?? nil` would quietly produce `.null` instead of staying absent.
// Write `.null` where a JSON null is actually intended.

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}

// MARK: - Bridging

public extension JSONValue {

    /// Builds a value from the `[String: Any]` the user-script bridge hands to a message handler.
    /// Returns `nil` for anything JSON cannot represent.
    init?(bridgeValue: Any) {
        switch bridgeValue {
        case is NSNull:
            self = .null
        case let value as String:
            self = .string(value)
        case let number as NSNumber:
            // Bool, Int and Double all bridge to NSNumber, and only the CFTypeID separates a
            // boolean from a numeric 0/1. JS has no integer type, so a whole double becomes an
            // Int here — that is what lets a tool validate `limit: 50` as an integer argument.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if let int = Int(exactly: number.doubleValue) {
                self = .int(int)
            } else {
                self = .double(number.doubleValue)
            }
        case let value as [Any]:
            self = .array(value.compactMap { JSONValue(bridgeValue: $0) })
        case let value as [String: Any]:
            self = .object(value.compactMapValues { JSONValue(bridgeValue: $0) })
        default:
            return nil
        }
    }

    /// Parses a JSON document. Used by tests and golden-JSON comparisons; tools use literals.
    init(jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Not UTF-8"))
        }
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }
}
