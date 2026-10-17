//
//  DictionaryURLQueryItemsTests.swift
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
@testable import Networking

final class DictionaryURLQueryItemsTests: XCTestCase {

    func queryParam(withName name: String, from queryItems: [URLQueryItem]) -> URLQueryItem {
        return queryItems.compactMap({ queryItem in
            if queryItem.name == name {
                return queryItem
            } else {
                return nil
            }
        }).last!
    }

    func testBasicKeyValuePairsConversion() {
        let queryParamCollection: QueryItems = [
            (key: "key1", value: "value1"),
            (key: "key2", value: "value2")
        ]
        let queryItems = queryParamCollection.toURLQueryItems()

        XCTAssertEqual(queryItems.count, 2)
        let q0 = queryParam(withName: "key1", from: queryItems)
        XCTAssertEqual(q0.name, "key1")
        XCTAssertEqual(q0.value, "value1")

        let q1 = queryParam(withName: "key2", from: queryItems)
        XCTAssertEqual(q1.name, "key2")
        XCTAssertEqual(q1.value, "value2")
    }

    func testReservedCharactersAreEncoded() {
        let dict: QueryItems = [
            (key: "query", value: "value with spaces"),
            (key: "special", value: "value/with/slash")
        ]
        let queryItems = dict.toURLQueryItems()

        XCTAssertEqual(queryItems.count, 2)
        let q1 = queryParam(withName: "query", from: queryItems)
        XCTAssertEqual(q1.name, "query")
        XCTAssertEqual(q1.value, "value with spaces")

        let q2 = queryParam(withName: "special", from: queryItems)
        XCTAssertEqual(q2.name, "special")
        XCTAssertEqual(q2.value, "value/with/slash")
    }

    func testReservedCharactersNotEncodedWhenAllowedCharacterSetProvided() {
        let dict: QueryItems = [(key: "specialKey", value: "value/with/slash")]
        let allowedCharacters = CharacterSet.urlPathAllowed
        let queryItems = dict.toURLQueryItems(allowedReservedCharacters: allowedCharacters)

        XCTAssertEqual(queryItems.count, 1)
        XCTAssertEqual(queryItems[0].name, "specialKey")
        XCTAssertEqual(queryItems[0].value, "value/with/slash")  // '/' should be preserved
    }

    func testEmptyDictionaryReturnsEmptyQueryItems() {
        let dict: QueryItems = []
        let queryItems = dict.toURLQueryItems()

        XCTAssertEqual(queryItems.count, 0)
    }

    func testPercentEncodingWithCustomCharacterSet() {
        let dict: QueryItems = [(key: "key", value: "value with spaces & symbols!")]
        let allowedCharacters = CharacterSet.punctuationCharacters.union(.whitespaces)
        let queryItems = dict.toURLQueryItems(allowedReservedCharacters: allowedCharacters)

        XCTAssertEqual(queryItems.count, 1)
        XCTAssertEqual(queryItems[0].name, "key")
        XCTAssertEqual(queryItems[0].value, "value with spaces & symbols!")
    }

    func testMultipleItemsWithReservedCharacters() {
        let dict: QueryItems = [
            (key: "path", value: "part/with/slashes"),
            (key: "query", value: "value with spaces"),
            (key: "fragment", value: "with#fragment")
        ]
        let allowedCharacters = CharacterSet.urlPathAllowed.union(.whitespaces).union(.punctuationCharacters)
        let queryItems = dict.toURLQueryItems(allowedReservedCharacters: allowedCharacters)

        XCTAssertEqual(queryItems.count, 3)
        let q0 = queryParam(withName: "path", from: queryItems)
        XCTAssertEqual(q0.name, "path")
        XCTAssertEqual(q0.value, "part/with/slashes")

        let q1 = queryParam(withName: "query", from: queryItems)
        XCTAssertEqual(q1.name, "query")
        XCTAssertEqual(q1.value, "value with spaces")

        let q2 = queryParam(withName: "fragment", from: queryItems)
        XCTAssertEqual(q2.name, "fragment")
        XCTAssertEqual(q2.value, "with#fragment")
    }
}
