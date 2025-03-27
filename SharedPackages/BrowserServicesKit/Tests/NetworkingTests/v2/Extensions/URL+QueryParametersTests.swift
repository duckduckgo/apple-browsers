//
//  URL+QueryParametersTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

class URLExtensionTests: XCTestCase {

    func testQueryParametersWithValidURL() {
        // Given
        let url = URL(string: "https://example.com?param1=value1&param2=value2")!

        // When
        let parameters = url.queryParameters()

        // Then
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?["param1"], "value1")
        XCTAssertEqual(parameters?["param2"], "value2")
    }

    func testQueryParametersWithEmptyQuery() {
        // Given
        let url = URL(string: "https://example.com")!

        // When
        let parameters = url.queryParameters()

        // Then
        XCTAssertNil(parameters)
    }

    func testQueryParametersWithNoValue() {
        // Given
        let url = URL(string: "https://example.com?param1=&param2=value2")!

        // When
        let parameters = url.queryParameters()

        // Then
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?["param1"], "")
        XCTAssertEqual(parameters?["param2"], "value2")
    }

    func testQueryParametersWithSpecialCharacters() {
        // Given
        let url = URL(string: "https://example.com?param1=value%201&param2=value%202")!

        // When
        let parameters = url.queryParameters()

        // Then
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?["param1"], "value 1")
        XCTAssertEqual(parameters?["param2"], "value 2")
    }

    func testQueryParametersWithMultipleSameKeys() {
        // Given
        let url = URL(string: "https://example.com?param=value1&param=value2")!

        // When
        let parameters = url.queryParameters()

        // Then
        XCTAssertNotNil(parameters)
        XCTAssertEqual(parameters?["param"], "value2") // Last value should overwrite the first
    }

    func testQueryParametersWithInvalidURL() {
        // Given
        let url = URL(string: "invalid-url")!

        // When
        let parameters = url.queryParameters()

        // Then
        XCTAssertNil(parameters)
    }
}
