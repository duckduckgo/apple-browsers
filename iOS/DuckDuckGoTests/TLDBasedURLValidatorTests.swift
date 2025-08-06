//
//  TLDBasedURLValidatorTests.swift
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
@testable import Core
import Common

final class TLDBasedURLValidatorTests: XCTestCase {

    func test() throws {
        let tld = TLD()
        let validator = TLDBasedURLValidator(tld: tld)

        XCTAssertTrue(validator.isValid(try XCTUnwrap(URL.webUrl(from: "chrisbrind.rocks"))))
        XCTAssertTrue(validator.isValid(try XCTUnwrap(URL.webUrl(from: "1.2.3.4"))))
        XCTAssertTrue(validator.isValid(try XCTUnwrap(URL.webUrl(from: "http://example.com"))))
        XCTAssertTrue(validator.isValid(try XCTUnwrap(URL.webUrl(from: "https://example.com/path/to/resource"))))
        XCTAssertTrue(validator.isValid(try XCTUnwrap(URL.webUrl(from: "localhost"))))
        XCTAssertTrue(validator.isValid(try XCTUnwrap(URL.webUrl(from: "random.local"))))

        XCTAssertFalse(validator.isValid(try XCTUnwrap(URL.webUrl(from: "friends.cast"))))

        // URL.webUrl doesn't return URLs for other schemes
        XCTAssertTrue(validator.isValid(try XCTUnwrap(URL(string: "ftp://friends.cast"))))
    }

}
