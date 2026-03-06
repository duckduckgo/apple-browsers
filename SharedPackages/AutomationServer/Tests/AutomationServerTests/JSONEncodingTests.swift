//
//  JSONEncodingTests.swift
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

import XCTest
@testable import AutomationServer

final class JSONEncodingTests: XCTestCase {

    // MARK: - Nil Handling

    func testEncodeNil_ReturnsNull() {
        let result = encodeToJsonString(nil)
        XCTAssertEqual(result, "null")
    }

    // MARK: - Primitive Types

    func testEncodeString_ReturnsQuotedString() {
        let result = encodeToJsonString("hello")
        XCTAssertEqual(result, "\"hello\"")
    }

    func testEncodeInt_ReturnsStringRepresentation() {
        let result = encodeToJsonString(42)
        XCTAssertEqual(result, "42")
    }

    func testEncodeNegativeInt_ReturnsStringRepresentation() {
        let result = encodeToJsonString(-123)
        XCTAssertEqual(result, "-123")
    }

    func testEncodeDouble_ReturnsStringRepresentation() {
        let result = encodeToJsonString(3.14)
        XCTAssertEqual(result, "3.14")
    }

    func testEncodeBoolTrue_ReturnsTrue() {
        let result = encodeToJsonString(true)
        XCTAssertEqual(result, "true")
    }

    func testEncodeBoolFalse_ReturnsFalse() {
        let result = encodeToJsonString(false)
        XCTAssertEqual(result, "false")
    }

    // MARK: - NSNumber (JavaScript Boolean) Handling

    func testEncodeNSNumberBoolTrue_ReturnsTrueNotOne() {
        // NSNumber bridging from JavaScript booleans - must return "true", not "1"
        let nsNumber: NSNumber = true
        let result = encodeToJsonString(nsNumber as Any)
        XCTAssertEqual(result, "true", "JavaScript true (as NSNumber) should encode as 'true', not '1'")
    }

    func testEncodeNSNumberBoolFalse_ReturnsFalseNotZero() {
        // NSNumber bridging from JavaScript booleans - must return "false", not "0"
        let nsNumber: NSNumber = false
        let result = encodeToJsonString(nsNumber as Any)
        XCTAssertEqual(result, "false", "JavaScript false (as NSNumber) should encode as 'false', not '0'")
    }

    // MARK: - Complex Types

    func testEncodeDictionary_ReturnsValidJSON() {
        let dict: [String: Any] = ["key": "value", "number": 42]
        let result = encodeToJsonString(dict)

        // Parse the result to verify it's valid JSON
        guard let data = result.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Result is not valid JSON: \(result)")
            return
        }

        XCTAssertEqual(parsed["key"] as? String, "value")
        XCTAssertEqual(parsed["number"] as? Int, 42)
    }

    func testEncodeArray_ReturnsValidJSON() {
        let array: [Any] = ["a", "b", 1, 2]
        let result = encodeToJsonString(array)

        guard let data = result.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            XCTFail("Result is not valid JSON: \(result)")
            return
        }

        XCTAssertEqual(parsed.count, 4)
    }

    func testEncodeEmptyDictionary_ReturnsEmptyObject() {
        let result = encodeToJsonString([String: Any]())
        XCTAssertEqual(result, "{}")
    }

    func testEncodeEmptyArray_ReturnsEmptyArray() {
        let result = encodeToJsonString([Any]())
        XCTAssertEqual(result, "[]")
    }

    // MARK: - Edge Cases

    func testEncodeStringThatLooksLikeJSON_ReturnsQuotedString() {
        // Even JSON-like strings should be properly encoded as JSON string literals
        let jsonString = "{\"already\":\"json\"}"
        let result = encodeToJsonString(jsonString)
        // The string itself should be escaped and quoted
        XCTAssertEqual(result, "\"{\\\"already\\\":\\\"json\\\"}\"")
    }
}
