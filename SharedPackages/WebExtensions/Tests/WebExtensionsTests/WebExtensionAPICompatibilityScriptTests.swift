//
//  WebExtensionAPICompatibilityScriptTests.swift
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

/// Exercises `WebExtensionAPICompatibilityScript.source` in a bare `JSContext` shaped like an extension page.
final class WebExtensionAPICompatibilityScriptTests: XCTestCase {

    private var context: JSContext!
    private var exceptions: [String] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        exceptions = []
        context = JSContext()
        context.exceptionHandler = { [weak self] _, exception in
            self?.exceptions.append(exception?.toString() ?? "unknown exception")
        }
        // A page with `chrome`, a console that remembers what it logged, the report handler WebKit adds
        // once the app registers it, and the event hooks a real page has.
        context.evaluateScript("""
        var chrome = { runtime: {} };
        var consoleMessages = [];
        var console = {
            info: function(message) { consoleMessages.push(String(message)); },
            error: function(message) { consoleMessages.push(String(message)); },
            warn: function(message) { consoleMessages.push(String(message)); }
        };
        var reports = [];
        var listeners = {};
        var webkit = { messageHandlers: {
            "\(WebExtensionAPICompatibilityScript.messageHandlerName)": {
                postMessage: function(payload) { reports.push(payload); }
            }
        } };
        globalThis.addEventListener = function(type, listener) { listeners[type] = listener; };
        """)
        try assertNoExceptions()
    }

    override func tearDownWithError() throws {
        context = nil
        exceptions = []
        try super.tearDownWithError()
    }

    // MARK: - Errors

    func testWhenThePageRaisesAnError_ThenItsMessageIsReportedForClassification() throws {
        try evaluateScript()

        context.evaluateScript("""
        listeners.error({ error: new TypeError("undefined is not an object (evaluating 'chrome.tts.speak')") });
        listeners.error({ message: "Script error." });
        """)
        try assertNoExceptions()

        try assertReports("[{\"kind\":\"error\",\"message\":\"undefined is not an object (evaluating 'chrome.tts.speak')\"}]")
    }

    func testWhenAnErrorIsNotAboutAnAPI_ThenItNeverLeavesThePage() throws {
        try evaluateScript()

        context.evaluateScript("""
        console.error("Failed to fetch https://example.com/?token=secret");
        console.warn(new Error("Something broke for user@example.com"));
        listeners.error({ message: "Script error." });
        listeners.unhandledrejection({ reason: "Invalid argument" });
        """)
        try assertNoExceptions()

        try assertReports("[]")
    }

    func testWhenAPromiseIsRejected_ThenTheReasonMessageIsReported() throws {
        try evaluateScript()

        context.evaluateScript("""
        listeners.unhandledrejection({ reason: new Error("Invalid call to tabs.query().") });
        listeners.unhandledrejection({ reason: { unrelated: true } });
        """)
        try assertNoExceptions()

        try assertReports("[{\"kind\":\"error\",\"message\":\"Invalid call to tabs.query().\"}]")
    }

    func testWhenTheConsoleLogsAnErrorOrWarning_ThenItIsReportedAndStillLogged() throws {
        try evaluateScript()

        context.evaluateScript("""
        console.error(new Error("chrome.tts.speak is not a function. (In 'chrome.tts.speak()')"));
        console.warn("Invalid call to windows.create().");
        console.error({ notAnError: true });
        """)
        try assertNoExceptions()

        try assertReports("""
        [{"kind":"error","message":"chrome.tts.speak is not a function. (In 'chrome.tts.speak()')"},\
        {"kind":"error","message":"Invalid call to windows.create()."}]
        """)
        try assertTrue("consoleMessages.length === 3")
    }

    func testWhenAngularLogsAMissingLanguageFeature_ThenItIsReported() throws {
        try evaluateScript()

        // Bitwarden's ErrorHandler logs a label and then the error.
        context.evaluateScript("""
        console.error("Unhandled error in angular", new TypeError("Symbol.dispose is not defined."));
        console.error(new ReferenceError("Can't find variable: DisposableStack"));
        """)
        try assertNoExceptions()

        try assertReports("""
        [{"kind":"error","message":"Symbol.dispose is not defined."},\
        {"kind":"error","message":"Can't find variable: DisposableStack"}]
        """)
    }

    // MARK: - Reports From Other Scripts

    func testWhenAnotherScriptReportsAnAPI_ThenItIsPostedOncePerPage() throws {
        try evaluateScript()

        context.evaluateScript("""
        \(WebExtensionAPICompatibilityScript.reportFunctionName)("stubbed", "notifications.create");
        \(WebExtensionAPICompatibilityScript.reportFunctionName)("stubbed", "notifications.create");
        """)
        try assertNoExceptions()

        try assertReports("[{\"kind\":\"stubbed\",\"api\":\"notifications.create\"}]")
    }

    func testWhenErrorsAreReportedByTheHundred_ThenAPIReportsStillGetThrough() throws {
        try evaluateScript()

        context.evaluateScript("""
        for (var index = 0; index < 300; index++) {
            console.error("chrome.tts.method" + index + " is not a function. (In 'chrome.tts.method" + index + "()')");
        }
        \(WebExtensionAPICompatibilityScript.reportFunctionName)("stubbed", "notifications.create");
        """)
        try assertNoExceptions()

        try assertTrue("reports.filter(function(report) { return report.kind === 'error'; }).length === 50")
        try assertTrue("reports.filter(function(report) { return report.kind === 'stubbed'; }).length === 1")
    }

    // MARK: - Robustness

    func testWhenTheScriptRunsTwice_ThenTheConsoleIsWrappedOnce() throws {
        try evaluateScript()
        try evaluateScript()
        context.evaluateScript("consoleMessages = [];")

        context.evaluateScript("console.error('Invalid call to one.two().');")
        try assertNoExceptions()

        try assertTrue("consoleMessages.length === 1")
        try assertReports("[{\"kind\":\"error\",\"message\":\"Invalid call to one.two().\"}]")
    }

    func testWhenTheHostHasNoReportHandler_ThenThePageIsNotDisturbed() throws {
        context.evaluateScript("webkit = { messageHandlers: {} };")
        try evaluateScript()

        context.evaluateScript("console.error('Invalid call to one.two().'); listeners.error({ message: 'y' });")
        try assertNoExceptions()

        try assertReports("[]")
    }

    func testWhenTheReportHandlerThrows_ThenThePageIsNotDisturbed() throws {
        context.evaluateScript("""
        webkit.messageHandlers["\(WebExtensionAPICompatibilityScript.messageHandlerName)"].postMessage = function() {
            throw new Error("handler failed");
        };
        """)
        try evaluateScript()

        context.evaluateScript("console.error('Invalid call to one.two().');")
        try assertNoExceptions()
    }

    func testWhenPageIsAWebsite_ThenNothingIsHookedOrReported() throws {
        context.evaluateScript("var location = { protocol: 'https:' };")
        try evaluateScript()

        context.evaluateScript("console.error('Invalid call to one.two().');")
        try assertNoExceptions()

        try assertTrue("Object.keys(listeners).length === 0")
        try assertTrue("typeof \(WebExtensionAPICompatibilityScript.reportFunctionName) === 'undefined'")
        try assertReports("[]")
    }

    // MARK: - Helpers

    private func evaluateScript() throws {
        context.evaluateScript(WebExtensionAPICompatibilityScript.source)
        try assertNoExceptions()
    }

    private func assertReports(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let escaped = json.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        try assertTrue("JSON.stringify(reports) === '\(escaped)'", file: file, line: line)
    }

    private func assertTrue(_ script: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let result = context.evaluateScript(script)
        try assertNoExceptions(file: file, line: line)
        XCTAssertEqual(result?.toBool(), true, script, file: file, line: line)
    }

    private func assertNoExceptions(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(exceptions, [], file: file, line: line)
        exceptions = []
    }
}
