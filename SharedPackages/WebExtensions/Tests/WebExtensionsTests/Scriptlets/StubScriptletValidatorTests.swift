//
//  StubScriptletValidatorTests.swift
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
@testable import WebExtensions

final class StubScriptletValidatorTests: XCTestCase {

    var validator: StubScriptletValidator!

    override func setUp() {
        super.setUp()
        validator = StubScriptletValidator()
    }

    override func tearDown() {
        validator = nil
        super.tearDown()
    }

    func testWhenAllScriptletsHaveValidUTF8ThenValidationSucceeds() throws {
        let fetched = [
            makeFetchedScriptlet(name: "script1.js", data: Data("console.log('hello')".utf8)),
            makeFetchedScriptlet(name: "script2.js", data: Data("var x = 1;".utf8))
        ]

        XCTAssertNoThrow(try validator.validate(fetched))
    }

    func testWhenScriptletHasInvalidEncodingThenThrowsInvalidEncoding() {
        let invalidData = Data([0xFF, 0xFE, 0x80, 0x81])
        let fetched = [makeFetchedScriptlet(name: "bad.js", data: invalidData)]

        XCTAssertThrowsError(try validator.validate(fetched)) { error in
            XCTAssertEqual(error as? ScriptletError, .invalidEncoding(name: "bad.js"))
        }
    }

    func testWhenEmptyArrayPassedThenValidationSucceeds() throws {
        XCTAssertNoThrow(try validator.validate([]))
    }

    // MARK: - Helpers

    private func makeFetchedScriptlet(name: String, data: Data) -> FetchedScriptlet {
        let descriptor = ScriptletDescriptor(
            name: name,
            url: URL(string: "https://example.com/\(name)")!,
            signature: "sig")
        return FetchedScriptlet(descriptor: descriptor, data: data)
    }
}
