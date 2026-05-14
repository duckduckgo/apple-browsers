//
//  UserScriptTests.swift
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

import Foundation
import XCTest
import WebKit
import UserScript

class UserScriptTests: XCTestCase {

    class TestUserScript: NSObject, UserScript {
        var val: String
        var source: String
        var injectionTime: WKUserScriptInjectionTime
        var forMainFrameOnly: Bool
        var messageNames: [String]

        init(val: String, injectionTime: WKUserScriptInjectionTime, forMainFrameOnly: Bool, messageNames: [String]) throws {
            self.val = val
            self.injectionTime = injectionTime
            self.forMainFrameOnly = forMainFrameOnly
            self.messageNames = messageNames
            self.source = try Self.loadJS("testUserScript", from: .module, withReplacements: ["${val}": val])
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        }
    }

    @MainActor
    func testWhenWKUserScriptCreatedValuesInitializedCorrectly() async throws {
        let src = "var val = 'Test';\n"
        let us = try TestUserScript(val: "Test", injectionTime: .atDocumentStart, forMainFrameOnly: true, messageNames: [])
        let script = await us.makeWKUserScript().wkUserScript
        XCTAssertTrue(script.source.contains(src))
        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertEqual(script.isForMainFrameOnly, true)
    }

    @MainActor
    func testWhenWKUserScriptCreatedValuesInitializedCorrectly2() async throws {
        let src = "var val = 'test2';\n"
        let us = try TestUserScript(val: "test2", injectionTime: .atDocumentEnd, forMainFrameOnly: false, messageNames: [])
        let script = await us.makeWKUserScript().wkUserScript
        XCTAssertTrue(script.source.contains(src))
        XCTAssertEqual(script.injectionTime, .atDocumentEnd)
        XCTAssertEqual(script.isForMainFrameOnly, false)
    }

    @MainActor
    func testWhenLoadJSFails_ExpectedErrorIsThrown() {
        let fileName = "testUserScript"
        let mockBundle = MockBundle()
        mockBundle.pathToReturn = "/invalidPath/to/testUserScript.js"

        XCTAssertThrowsError(try TestUserScript.loadJS(fileName, from: mockBundle, withReplacements: [:])) { error in
            guard case let UserScriptError.failedToLoadJS(jsFile, underlyingError) = error else {
                return XCTFail("Expected failedToLoadJS error but got: \(error)")
            }
            XCTAssertEqual(fileName, jsFile)
            XCTAssertNotNil(underlyingError)
        }
    }

    // MARK: - loadJS replacement integration tests

    func testLoadJSWithMultipleReplacements() throws {
        let result = try TestUserScript.loadJS("testLoadJSReplacements", from: .module, withReplacements: [
            "$A$": "1",
            "$B$": "2",
            "$C$": "3"
        ])

        XCTAssertEqual(result, "var a = 1;\nvar b = 2;\nvar c = 3;\nvar a2 = 1;\n")
    }

    func testLoadJSReplacesAllOccurrencesOfRepeatedKey() throws {
        let result = try TestUserScript.loadJS("testLoadJSReplacements", from: .module, withReplacements: [
            "$A$": "hello",
            "$B$": "x",
            "$C$": "x"
        ])

        XCTAssertTrue(result.contains("var a = hello;"))
        XCTAssertTrue(result.contains("var a2 = hello;"))
    }

    func testLoadJSDoesNotReExpandReplacementValues() throws {
        let result = try TestUserScript.loadJS("testLoadJSReplacements", from: .module, withReplacements: [
            "$A$": "1",
            "$B$": "$A$",
            "$C$": "3"
        ])

        XCTAssertTrue(result.contains("var b = $A$;"))
        XCTAssertTrue(result.contains("var a = 1;"))
    }

    func testLoadJSWithEmptyReplacements() throws {
        let result = try TestUserScript.loadJS("testLoadJSReplacements", from: .module, withReplacements: [:])

        XCTAssertTrue(result.contains("$A$"))
        XCTAssertTrue(result.contains("$B$"))
        XCTAssertTrue(result.contains("$C$"))
    }

    private class MockBundle: Bundle, @unchecked Sendable {
        var pathToReturn: String?

        override func path(forResource name: String?, ofType ext: String?) -> String? {
            return pathToReturn
        }
    }

}
