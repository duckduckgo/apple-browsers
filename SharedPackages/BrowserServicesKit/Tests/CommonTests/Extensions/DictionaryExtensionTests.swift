//
//  DictionaryExtensionTests.swift
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
import XCTest

@testable import Common

final class DictionaryExtensionTests: XCTestCase {

    func testWhenAllValuesAreNonNilThenAllEntriesAreIncluded() {
        let result = Dictionary(compacting: [
            ("key1", "value1"),
            ("key2", "value2"),
            ("key3", "value3"),
        ])

        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result["key1"], "value1")
        XCTAssertEqual(result["key2"], "value2")
        XCTAssertEqual(result["key3"], "value3")
    }

    func testWhenSomeValuesAreNilThenOnlyNonNilEntriesAreIncluded() {
        let optionalValue: String? = nil

        let result = Dictionary(compacting: [
            ("key1", "value1"),
            ("key2", optionalValue),
            ("key3", "value3"),
        ])

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result["key1"], "value1")
        XCTAssertNil(result["key2"])
        XCTAssertEqual(result["key3"], "value3")
    }

    func testWhenAllValuesAreNilThenDictionaryIsEmpty() {
        let nilValue: String? = nil

        let result = Dictionary(compacting: [
            ("key1", nilValue),
            ("key2", nilValue),
            ("key3", nilValue),
        ])

        XCTAssertTrue(result.isEmpty)
    }

    func testWhenEntriesArrayIsEmptyThenDictionaryIsEmpty() {
        let result = Dictionary(compacting: [])

        XCTAssertTrue(result.isEmpty)
    }

    func testWhenUsingOptionalMapThenTransformedValuesAreIncluded() {
        let intValue: Int? = 42
        let nilInt: Int? = nil

        let result = Dictionary(compacting: [
            ("present", intValue.map { String($0) }),
            ("absent", nilInt.map { String($0) }),
        ])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["present"], "42")
        XCTAssertNil(result["absent"])
    }

    func testWhenUsingRawRepresentableThenRawValuesAreIncluded() {
        enum Status: String {
            case active
            case inactive
        }

        let activeStatus: Status? = .active
        let nilStatus: Status? = nil

        let result = Dictionary(compacting: [
            ("status1", activeStatus?.rawValue),
            ("status2", nilStatus?.rawValue),
        ])

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["status1"], "active")
        XCTAssertNil(result["status2"])
    }

}
