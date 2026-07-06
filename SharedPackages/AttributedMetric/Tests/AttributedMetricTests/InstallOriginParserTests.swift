//
//  InstallOriginParserTests.swift
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

@testable import AttributedMetric
import XCTest

final class InstallOriginParserTests: XCTestCase {

    func testWhenAllFiveSegmentsPresentThenParsesEachField() {
        let result = InstallOriginParser.parse("funnel_home_website_foo_bar")

        XCTAssertEqual(result, InstallOriginComponents(
            funnel: "funnel",
            entry: "home",
            source: "website",
            campaign: "foo",
            content: "bar"
        ))
    }

    func testWhenExplicitEmptyMiddleSegmentsThenPreservesBlanks() {
        let result = InstallOriginParser.parse("funnel_home__foo_bar")

        XCTAssertEqual(result, InstallOriginComponents(
            funnel: "funnel",
            entry: "home",
            source: "",
            campaign: "foo",
            content: "bar"
        ))
    }

    func testWhenTrailingFieldsOmittedThenOptionalFieldsAreNil() {
        let result = InstallOriginParser.parse("funnel_home")

        XCTAssertEqual(result, InstallOriginComponents(
            funnel: "funnel",
            entry: "home",
            source: nil,
            campaign: nil,
            content: nil
        ))
    }

    func testWhenMoreThanFiveSegmentsThenReturnsNil() {
        XCTAssertNil(InstallOriginParser.parse("funnel_home_a_b_c_d"))
    }

    func testWhenEmptyOrWhitespaceThenReturnsNil() {
        XCTAssertNil(InstallOriginParser.parse(""))
        XCTAssertNil(InstallOriginParser.parse("   "))
    }

    func testWhenSingleSegmentThenReturnsNil() {
        XCTAssertNil(InstallOriginParser.parse("funnel"))
    }
}
