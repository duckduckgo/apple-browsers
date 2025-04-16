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
@testable import DuckDuckGo_Privacy_Browser

extension VisitIdentifier: @retroactive Equatable {
    public static func == (_ lhs: VisitIdentifier, _ rhs: VisitIdentifier) -> Bool {
        /// Second precision is enough for comparing `VisitIdentifier`s, because visits themselves are looked up with day precision.
        lhs.uuid == rhs.uuid && lhs.url == rhs.url && Int64(lhs.date.timeIntervalSince1970) == Int64(rhs.date.timeIntervalSince1970)
    }
}

final class VisitIdentifierTests: XCTestCase {

    func testThatDescriptionInitializerCreatesValidObject() throws {
        let date = Date()
        let url = try XCTUnwrap("https://example.com".url)
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
