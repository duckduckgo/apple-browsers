//
//  RangeStringMatchingAttributeTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
@testable import RemoteMessaging

class RangeStringMatchingAttributeTests: XCTestCase {

    func testWhenTextThenMatchesShouldFail() throws {
        let matcher = RangeStringNumericMatchingAttribute(min: "0", max: "0")
        XCTAssertEqual(matcher.matches(value: "textstring"), .fail)
    }

    func testWhenVersionBetweenMinMaxShouldMatch() throws {
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "4.1", max: "14").matches(value: "13.4.1"), .match)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "0", max: "2").matches(value: "0.22"), .match)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "0.0", max: "2").matches(value: "0.1"), .match)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "0.0", max: "2").matches(value: "0.44"), .match)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "0", max: "2").matches(value: "1.0"), .match)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "0", max: "2").matches(value: "1.44"), .match)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "0", max: "2").matches(value: "1.88"), .match)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "0", max: "2").matches(value: "1.44.88"), .match)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "1.44.88", max: "2").matches(value: "1.44.88.0"), .match)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "1.44.88", max: "2").matches(value: "1.44.88.1"), .match)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "1.44.88.0", max: "2").matches(value: "1.44.88.0"), .match)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "1.44.88.0", max: "2").matches(value: "1.44.88.1"), .match)
    }

    func testWhenVersionOutsideMinMaxShouldFail() throws {
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "2.88", max: "8.88").matches(value: "0.22"), .fail)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "2.88", max: "8.88").matches(value: "88.88"), .fail)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "44.44", max: "88.88").matches(value: "0.1"), .fail)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "44.44", max: "88.88").matches(value: "22.22"), .fail)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "1.44.89", max: "2").matches(value: "1.44.88.1"), .fail)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "1.44.88.1", max: "2").matches(value: "1.44.88"), .fail)
        XCTAssertEqual(RangeStringNumericMatchingAttribute(min: "1.44.88.1", max: "2").matches(value: "1.44.88.0"), .fail)

    }
}
