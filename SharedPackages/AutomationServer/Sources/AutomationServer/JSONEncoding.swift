//
//  JSONEncoding.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import os.log

/// Encode any value to a JSON string, handling primitive types and JSONSerialization-compatible types
/// Note: Swift's `as? Encodable` doesn't work from `Any`, so we handle primitives explicitly
public func encodeToJsonString(_ value: Any?) -> String {
    do {
        guard let value else {
            return "null"
        }

        // Handle primitive types explicitly (as? Encodable doesn't work from Any)
        if let stringValue = value as? String {
            // Properly encode the string as JSON to ensure it's quoted
            let jsonData = try JSONEncoder().encode(stringValue)
            return String(data: jsonData, encoding: .utf8) ?? "\"\(stringValue.replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        // Check Bool before Int/Double - NSNumber (from JavaScript) bridges to all three,
        // and JavaScript booleans must be encoded as "true"/"false", not 1/0
        if let boolValue = value as? Bool {
            return boolValue ? "true" : "false"
        }
        if let intValue = value as? Int {
            return String(intValue)
        }
        if let doubleValue = value as? Double {
            return String(doubleValue)
        }

        // Handle arrays and dictionaries via JSONSerialization
        if JSONSerialization.isValidJSONObject(value) {
            let jsonData = try JSONSerialization.data(withJSONObject: value, options: [])
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        }

        // Fallback: try to describe the value
        Logger.automationServer.error("Have value that can't be encoded: \(String(describing: value)) type: \(type(of: value))")
        return "{\"error\": \"Value is not a valid JSON object\"}"
    } catch {
        Logger.automationServer.error("Failed to encode: \(String(describing: value))")
        return "{\"error\": \"JSON encoding failed: \(error)\"}"
    }
}
