//
//  WebExtensionWindowCloseScriptTests.swift
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

import JavaScriptCore
import XCTest
@testable import WebExtensions

/// Exercises `WebExtensionWindowCloseScript.source` in a bare `JSContext` that stands in for a
/// popup page: `close` is the page's own function, `webkit.messageHandlers` is what WebKit adds
/// once a handler is registered.
final class WebExtensionWindowCloseScriptTests: XCTestCase {

    private var context: JSContext!
    private var exceptions: [String] = []

    override func setUpWithError() throws {
        try super.setUpWithError()

        context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { [weak self] _, exception in
            self?.exceptions.append(exception?.toString() ?? "unknown exception")
        }

        context.evaluateScript("""
        var closeCalls = 0;
        var postedMessages = [];
        var location = { href: "webkit-extension://abc/popup.html" };
        function close() { closeCalls++; }
        """)
    }

    override func tearDown() {
        XCTAssertEqual(exceptions, [], "The script must not throw")
        context = nil
        exceptions = []
        super.tearDown()
    }

    func testWhenHandlerIsRegistered_ThenCloseReportsThePageAndStillCloses() throws {
        installHandler()
        context.evaluateScript(WebExtensionWindowCloseScript.source)

        context.evaluateScript("close();")

        try assertTrue("closeCalls === 1")
        try assertTrue("postedMessages.length === 1")
        try assertTrue("postedMessages[0] === 'webkit-extension://abc/popup.html'")
    }

    func testWhenHandlerThrows_ThenThePageStillCloses() throws {
        installHandler(throwing: true)
        context.evaluateScript(WebExtensionWindowCloseScript.source)

        context.evaluateScript("close();")

        try assertTrue("closeCalls === 1")
        try assertTrue("postedMessages.length === 0")
    }

    func testWhenNoHandlerIsRegistered_ThenCloseIsLeftAlone() throws {
        context.evaluateScript("var originalClose = close;")
        context.evaluateScript(WebExtensionWindowCloseScript.source)

        try assertTrue("close === originalClose")

        context.evaluateScript("close();")
        try assertTrue("closeCalls === 1")
    }

    func testWhenHandlerHasAnotherName_ThenCloseIsLeftAlone() throws {
        context.evaluateScript("""
        var webkit = { messageHandlers: { somethingElse: { postMessage: function() {} } } };
        var originalClose = close;
        """)
        context.evaluateScript(WebExtensionWindowCloseScript.source)

        try assertTrue("close === originalClose")
    }

    // MARK: - Helpers

    private func installHandler(throwing: Bool = false) {
        let body = throwing
            ? "throw new Error('no handler');"
            : "postedMessages.push(message);"
        context.evaluateScript("""
        var webkit = { messageHandlers: {} };
        webkit.messageHandlers["\(WebExtensionWindowCloseScript.messageHandlerName)"] = {
            postMessage: function(message) { \(body) }
        };
        """)
    }

    private func assertTrue(_ expression: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let value = try XCTUnwrap(context.evaluateScript(expression), file: file, line: line)
        XCTAssertTrue(value.toBool(), "Expected `\(expression)` to be true", file: file, line: line)
    }
}
