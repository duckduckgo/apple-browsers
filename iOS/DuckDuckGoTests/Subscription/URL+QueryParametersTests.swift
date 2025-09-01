//
//  URL+QueryParametersTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

final class URL_QueryParametersTests: XCTestCase {

    func testHasQueryParameterWithMatchingNameAndValue() {
        let url = URL(string: "https://example.com?preventBackNavigation=true")!
        XCTAssertTrue(url.hasQueryParameter(name: "preventBackNavigation", value: "true"))
    }
    
    func testHasQueryParameterWithMatchingNameButDifferentValue() {
        let url = URL(string: "https://example.com?preventBackNavigation=false")!
        XCTAssertFalse(url.hasQueryParameter(name: "preventBackNavigation", value: "true"))
    }
    
    func testHasQueryParameterWithDifferentNameButMatchingValue() {
        let url = URL(string: "https://example.com?someOtherParam=true")!
        XCTAssertFalse(url.hasQueryParameter(name: "preventBackNavigation", value: "true"))
    }
    
    func testHasQueryParameterWithNoQueryParameters() {
        let url = URL(string: "https://example.com")!
        XCTAssertFalse(url.hasQueryParameter(name: "preventBackNavigation", value: "true"))
    }
    
    func testHasQueryParameterWithMultipleParameters() {
        let url = URL(string: "https://example.com?foo=bar&preventBackNavigation=true&baz=qux")!
        XCTAssertTrue(url.hasQueryParameter(name: "preventBackNavigation", value: "true"))
    }
    
    func testShouldPreventBackNavigationWhenParameterIsTrue() {
        let url = URL(string: "https://example.com?preventBackNavigation=true")!
        XCTAssertTrue(url.shouldPreventBackNavigation)
    }
    
    func testShouldPreventBackNavigationWhenParameterIsFalse() {
        let url = URL(string: "https://example.com?preventBackNavigation=false")!
        XCTAssertFalse(url.shouldPreventBackNavigation)
    }
    
    func testShouldPreventBackNavigationWhenParameterIsMissing() {
        let url = URL(string: "https://example.com?someOtherParam=value")!
        XCTAssertFalse(url.shouldPreventBackNavigation)
    }
    
    func testShouldPreventBackNavigationWhenNoQueryParameters() {
        let url = URL(string: "https://example.com")!
        XCTAssertFalse(url.shouldPreventBackNavigation)
    }

}
