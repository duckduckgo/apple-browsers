//
//  WebExtensionImportScriptsShimTests.swift
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

/// Exercises `WebExtensionImportScriptsShim.source` in a bare `JSContext` standing in for the
/// generated background page: a `location`, a `document.scripts` list of preloaded chunk tags, and a
/// webpack chunk array whose `push` the bundle's runtime replaces on startup.
///
/// `JSContext` has no DOM, so the fixture also supplies a minimal `URL` — enough to resolve a
/// relative path against a base, which is all the shim asks of it.
final class WebExtensionImportScriptsShimTests: XCTestCase {

    private var context: JSContext!
    private var exceptions: [String] = []

    override func setUpWithError() throws {
        try super.setUpWithError()

        context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { [weak self] _, exception in
            self?.exceptions.append(exception?.toString() ?? "unknown exception")
        }

        context.evaluateScript("""
        var consoleMessages = [];
        var console = {
            info: function(message) { consoleMessages.push(message); },
            log: function(message) { consoleMessages.push(message); },
            warn: function(message) { consoleMessages.push(message); },
            error: function(message) { consoleMessages.push(message); }
        };

        \(JSContextPolyfills.url)

        globalThis.location = { href: "chrome-extension://abc/ddg-background-page.html" };
        globalThis.document = { scripts: [{ src: "chrome-extension://abc/719.background.js" }] };

        // What `(self.webpackChunk_test = self.webpackChunk_test || []).push([[719], {…}])` leaves
        // behind when the chunk file is preloaded before the bundle that consumes it.
        var capturedChunk = [[719], {}];
        globalThis.webpackChunk_test = [capturedChunk];
        """)
        try assertNoExceptions()
    }

    override func tearDownWithError() throws {
        context = nil
        exceptions = []
        try super.tearDownWithError()
    }

    // MARK: - Definition

    func testWhenImportScriptsIsMissing_ThenTheShimDefinesIt() throws {
        try evaluateShim()

        try assertTrue("typeof importScripts === 'function'")
    }

    func testWhenImportScriptsAlreadyExists_ThenTheShimLeavesItAlone() throws {
        context.evaluateScript("""
        var hostImportScripts = function() {};
        globalThis.importScripts = hostImportScripts;
        """)
        try assertNoExceptions()

        try evaluateShim()

        try assertTrue("globalThis.importScripts === hostImportScripts")
    }

    // MARK: - Chunk Replay

    func testWhenImportScriptsIsCalled_ThenCapturedChunksAreReplayedThroughTheRuntimePush() throws {
        try evaluateShim()
        try installRuntimePush()

        context.evaluateScript("importScripts('719.background.js');")
        try assertNoExceptions()

        try assertTrue("pushedEntries.length === 1")
        try assertTrue("pushedEntries[0] === capturedChunk")
    }

    func testWhenImportScriptsIsCalledAgain_ThenNothingIsReplayedTwice() throws {
        try evaluateShim()
        try installRuntimePush()

        context.evaluateScript("""
        importScripts('719.background.js');
        importScripts('719.background.js');
        """)
        try assertNoExceptions()

        try assertTrue("pushedEntries.length === 1")
    }

    func testWhenAWebpackChunkGlobalIsNotAnArray_ThenItIsIgnored() throws {
        context.evaluateScript("globalThis.webpackChunkFoo = { push: function() { throw new Error('must not be called'); } };")
        try assertNoExceptions()

        try evaluateShim()
        try installRuntimePush()

        context.evaluateScript("importScripts('719.background.js');")
        try assertNoExceptions()

        try assertTrue("pushedEntries.length === 1")
        try assertTrue("pushedEntries[0] === capturedChunk")
    }

    // MARK: - Missing Preload

    func testWhenTheRequestedScriptWasNotPreloaded_ThenImportScriptsThrows() throws {
        try evaluateShim()
        try installRuntimePush()

        context.evaluateScript("""
        var thrownError = null;
        try {
            importScripts('404.background.js');
        } catch (error) {
            thrownError = error;
        }
        """)
        try assertNoExceptions()

        try assertTrue("thrownError instanceof Error")
        try assertTrue("thrownError.message.indexOf('404.background.js') !== -1")
        try assertTrue("pushedEntries.length === 0")
    }

    // MARK: - Helpers

    /// Replaces the chunk array's `push` the way the webpack runtime does on startup, recording what
    /// it is handed instead of installing modules.
    private func installRuntimePush() throws {
        context.evaluateScript("""
        var pushedEntries = [];
        globalThis.webpackChunk_test.push = function(entry) {
            pushedEntries.push(entry);
            return pushedEntries.length;
        };
        """)
        try assertNoExceptions()
    }

    private func evaluateShim() throws {
        context.evaluateScript(WebExtensionImportScriptsShim.source)
        try assertNoExceptions()
    }

    private func assertTrue(_ script: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let value = context.evaluateScript(script)
        try assertNoExceptions(file: file, line: line)
        XCTAssertEqual(value?.toBool(), true, script, file: file, line: line)
    }

    private func assertNoExceptions(file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(exceptions.isEmpty, "Unexpected JavaScript exceptions: \(exceptions)", file: file, line: line)
    }
}
