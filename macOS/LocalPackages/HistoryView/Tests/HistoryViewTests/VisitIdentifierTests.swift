//
//  VisitIdentifierTests.swift
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
@testable import HistoryView

final class VisitIdentifierTests: XCTestCase {

    func testThatDescriptionInitializerCreatesValidObject() throws {
        let date = Date()
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let identifier = VisitIdentifier("abcd|\(url.absoluteString)|\(String(date.timeIntervalSince1970))")
        XCTAssertEqual(identifier, VisitIdentifier(uuid: "abcd", url: url, date: date))
    }

    func testThatDescriptionInitializerReturnsNilForInvalidInput() throws {
        XCTAssertNil(VisitIdentifier(""))
        XCTAssertNil(VisitIdentifier("abcd|abcd|abcd"))
        XCTAssertNil(VisitIdentifier("|abcd|abcd"))
        XCTAssertNil(VisitIdentifier("abcd|abcd|"))
        XCTAssertNil(VisitIdentifier("||"))
        XCTAssertNil(VisitIdentifier("||20"))
        XCTAssertNil(VisitIdentifier("|https://example.com|20"))
    }
}
