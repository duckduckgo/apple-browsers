//
//  APIResultTests.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
@testable import Suggestions

final class APIResultTests: XCTestCase {

    func testWhenInitializedFromEmpty_ThenNoItemsAreInTheResult() {
        let json = """
        []
        """
        let data = json.data(using: .utf8)!

        guard let suggestionsAPIResult = try? JSONDecoder().decode(APIResult.self, from: data) else {
            XCTFail("Decoding of SuggestionsAPIResult failed")
            return
        }

        XCTAssertEqual(suggestionsAPIResult.items.count, 0)
    }

    func testWhenJSONHasValidFormat_ThenItemsAreInTheResult() {
        let value1 = "value1"
        let value2 = "value2"
        let value3 = "value3"

        let json = """
        [
            { "phrase": "\(value1)" },
            { "phrase": "\(value2)", "isNav": false },
            { "phrase": "\(value3)", "isNav": true },
            { "random": "nonesense" },
        ]
        """
        let data = json.data(using: .utf8)!

        guard let suggestionsAPIResult = try? JSONDecoder().decode(APIResult.self, from: data) else {
            XCTFail("Decoding of SuggestionsAPIResult failed")
            return
        }

        XCTAssertEqual(suggestionsAPIResult.items.count, 4)
        XCTAssertEqual(suggestionsAPIResult.items[0].phrase, value1)
        XCTAssertNil(suggestionsAPIResult.items[0].isNav)

        XCTAssertEqual(suggestionsAPIResult.items[1].phrase, value2)
        XCTAssertEqual(suggestionsAPIResult.items[1].isNav, false)

        XCTAssertEqual(suggestionsAPIResult.items[2].phrase, value3)
        XCTAssertEqual(suggestionsAPIResult.items[2].isNav, true)

        XCTAssertNil(suggestionsAPIResult.items[3].phrase)
        XCTAssertNil(suggestionsAPIResult.items[3].isNav)
    }

    func testWhenJSONHasInvalidFormat_ThenDecodingFails() {
        let json = """
        { "phrase": "value1" }, { "phrase": "value2" }
        """
        let data = json.data(using: .utf8)!

        let suggestionsAPIResult = try? JSONDecoder().decode(APIResult.self, from: data)
        if suggestionsAPIResult != nil {
            XCTFail("Decoding should fail")
            return
        }

        XCTAssert(true)
    }

}
