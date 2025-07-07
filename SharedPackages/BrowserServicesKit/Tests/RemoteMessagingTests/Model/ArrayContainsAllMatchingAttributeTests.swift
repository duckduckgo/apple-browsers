//
//  ArrayContainsAllMatchingAttributeTests.swift
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
@testable import RemoteMessaging

class ArrayContainsAllMatchingAttributeTests: XCTestCase {

    func testWhenEmptyRequiredArrayThenMatchesShouldMatch() throws {
        let matcher = StringArrayContainsAllMatchingAttribute([])
        XCTAssertEqual(matcher.matches(value: ["sync", "textZoom"]), .match)
    }

    func testWhenAllRequiredValuesPresentThenMatchesShouldMatch() throws {
        let matcher = StringArrayContainsAllMatchingAttribute(["sync", "textZoom"])
        XCTAssertEqual(matcher.matches(value: ["sync", "textZoom", "subfeature"]), .match)
    }

    func testWhenExactRequiredValuesPresentThenMatchesShouldMatch() throws {
        let matcher = StringArrayContainsAllMatchingAttribute(["sync", "textZoom"])
        XCTAssertEqual(matcher.matches(value: ["sync", "textZoom"]), .match)
    }

    func testWhenSomeRequiredValuesMissingThenMatchesShouldFail() throws {
        let matcher = StringArrayContainsAllMatchingAttribute(["sync", "textZoom", "subfeature"])
        XCTAssertEqual(matcher.matches(value: ["sync", "textZoom"]), .fail)
    }

    func testWhenProvidedArrayEmptyThenMatchesShouldFail() throws {
        let matcher = StringArrayContainsAllMatchingAttribute(["sync", "textZoom"])
        XCTAssertEqual(matcher.matches(value: []), .fail)
    }

    func testWhenNoMatchingValuesThenMatchesShouldFail() throws {
        let matcher = StringArrayContainsAllMatchingAttribute(["sync", "textZoom"])
        XCTAssertEqual(matcher.matches(value: ["subfeature", "duckPlayer"]), .fail)
    }

    func testWhenCaseInsensitiveMatchThenMatchesShouldMatch() throws {
        let matcher = StringArrayContainsAllMatchingAttribute(["SYNC", "TextZoom"])
        XCTAssertEqual(matcher.matches(value: ["sync", "textzoom", "subfeature"]), .match)
    }

    func testWhenSingleRequiredValuePresentThenMatchesShouldMatch() throws {
        let matcher = StringArrayContainsAllMatchingAttribute(["sync"])
        XCTAssertEqual(matcher.matches(value: ["sync", "textZoom"]), .match)
    }

    func testWhenSingleRequiredValueMissingThenMatchesShouldFail() throws {
        let matcher = StringArrayContainsAllMatchingAttribute(["sync"])
        XCTAssertEqual(matcher.matches(value: ["textZoom", "subfeature"]), .fail)
    }

}
