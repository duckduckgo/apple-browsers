//
//  PixelRetryQueueItemTests.swift
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

import XCTest
@testable import PixelKit

final class PixelRetryQueueItemTests: XCTestCase {

    func testWhenItemHasNilCharacterSet_ThenItRoundTripsThroughCoding() throws {
        let item = PixelRetryQueueItem(pixelName: "m_test",
                                       headers: ["H": "V"],
                                       parameters: ["p": "v"],
                                       allowedQueryReservedCharacters: nil,
                                       timestamp: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(PixelRetryQueueItem.self, from: data)

        XCTAssertEqual(item, decoded)
        XCTAssertNil(decoded.allowedQueryReservedCharacters)
    }

    func testWhenItemHasCharacterSet_ThenItRoundTripsThroughCoding() throws {
        let item = PixelRetryQueueItem(pixelName: "m_test",
                                       headers: [:],
                                       parameters: [:],
                                       allowedQueryReservedCharacters: CharacterSet(charactersIn: ",;+"),
                                       timestamp: Date(timeIntervalSince1970: 1_700_000_000))

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(PixelRetryQueueItem.self, from: data)

        XCTAssertEqual(item, decoded)
        XCTAssertEqual(decoded.allowedQueryReservedCharacters, CharacterSet(charactersIn: ",;+"))
    }
}
