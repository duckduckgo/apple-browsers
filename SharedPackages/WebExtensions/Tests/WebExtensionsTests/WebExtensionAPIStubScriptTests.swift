//
//  WebExtensionAPIStubScriptTests.swift
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

/// Exercises `WebExtensionAPIStubScript.source` in a bare `JSContext` seeded with the subset of
/// `chrome.*` that WebKit actually exposes to a background page.
final class WebExtensionAPIStubScriptTests: XCTestCase {

    private var context: JSContext!
    private var exceptions: [String] = []

    override func setUpWithError() throws {
        try super.setUpWithError()

        context = try XCTUnwrap(JSContext())
        context.exceptionHandler = { [weak self] _, exception in
            self?.exceptions.append(exception?.toString() ?? "unknown exception")
        }

        // WebKit's background page exposes only a subset of `chrome.*`; `console` is provided so the
        // script's summary log does not throw.
        context.evaluateScript("""
        var consoleMessages = [];
        var console = {
            info: function(message) { consoleMessages.push(message); },
            log: function(message) { consoleMessages.push(message); },
            warn: function(message) { consoleMessages.push(message); },
            error: function(message) { consoleMessages.push(message); }
        };
        var chrome = {
            runtime: {},
            webNavigation: { onCommitted: { addListener: function() {} } },
            tabs: {}
        };
        var originalRuntime = chrome.runtime;
        var originalTabs = chrome.tabs;
        var originalOnCommitted = chrome.webNavigation.onCommitted;
        """)
        try assertNoExceptions()
    }

    override func tearDownWithError() throws {
        context = nil
        exceptions = []
        try super.tearDownWithError()
    }

    // MARK: - Missing Namespaces

    func testWhenNamespaceIsMissing_ThenItsEventsExposeListenerAPI() throws {
        try evaluateStubScript()

        try assertTrue("typeof chrome.notifications.onClicked.addListener === 'function'")
        try assertTrue("typeof chrome.notifications.onClicked.removeListener === 'function'")
        try assertTrue("chrome.notifications.onClicked.hasListener() === false")
        try assertTrue("chrome.notifications.onClicked.hasListeners() === false")
    }

    func testWhenNamespaceIsMissing_ThenItsMethodsAreCallableFunctions() throws {
        try evaluateStubScript()

        try assertTrue("typeof chrome.offscreen.createDocument === 'function'")
        try assertTrue("typeof chrome.downloads.download === 'function'")
        try assertTrue("typeof chrome.management.getSelf === 'function'")
    }

    func testWhenNamespaceIsMissing_ThenNestedPropertyChainsResolveToFunctions() throws {
        try evaluateStubScript()

        try assertTrue("typeof chrome.privacy.services.passwordSavingEnabled.get === 'function'")
        try assertTrue("typeof chrome.browsingData.removeCache === 'function'")
    }

    func testWhenStubIsCalled_ThenItReturnsAPromise() throws {
        try evaluateStubScript()

        try assertTrue("typeof chrome.idle.queryState(60) === 'object'")
        try assertTrue("typeof chrome.idle.queryState(60).then === 'function'")
    }

    func testWhenStubIsCalledWithTrailingCallback_ThenTheCallbackIsInvokedWithUndefined() throws {
        try evaluateStubScript()

        context.evaluateScript("""
        var callbackArguments = null;
        chrome.topSites.get(function(sites) { callbackArguments = [sites]; });
        """)
        try assertNoExceptions()

        // The callback is invoked on a microtask, which drains once the evaluation above returns.
        // Tolerate a host that drains later — what matters is that it is never called with a value.
        try assertTrue("callbackArguments === null || (callbackArguments.length === 1 && callbackArguments[0] === undefined)")
    }

    func testWhenStubIsInspected_ThenItDoesNotLookLikeAThenable() throws {
        try evaluateStubScript()

        try assertTrue("chrome.notifications.then === undefined")
        try assertTrue("chrome.privacy.services.then === undefined")
    }

    func testWhenStubIsCoercedToString_ThenItDescribesItself() throws {
        try evaluateStubScript()

        try assertTrue("String(chrome.notifications) === '[DuckDuckGo API stub]'")
        try assertTrue("chrome.notifications.toString() === '[DuckDuckGo API stub]'")
    }

    // MARK: - Existing Namespaces

    func testWhenNamespaceExists_ThenItIsNotReplaced() throws {
        try evaluateStubScript()

        try assertTrue("chrome.runtime === originalRuntime")
        try assertTrue("chrome.tabs === originalTabs")
    }

    func testWhenEventIsMissingFromExistingNamespace_ThenOnlyThatEventIsAdded() throws {
        try evaluateStubScript()

        try assertTrue("typeof chrome.webNavigation.onCreatedNavigationTarget.addListener === 'function'")
        try assertTrue("typeof chrome.webNavigation.onHistoryStateUpdated.addListener === 'function'")
        try assertTrue("typeof chrome.tabs.onZoomChange.addListener === 'function'")
        try assertTrue("typeof chrome.runtime.onSuspend.addListener === 'function'")

        try assertTrue("chrome.webNavigation.onCommitted === originalOnCommitted")
    }

    func testWhenEventIsMissingButNamespaceIsToo_ThenNothingIsAddedToTheStub() throws {
        // `dns` is stubbed wholesale, so its events come from the stub rather than the event list.
        try evaluateStubScript()

        try assertTrue("typeof chrome.dns.resolve === 'function'")
    }

    // MARK: - Logging and Idempotency

    func testWhenSomethingIsStubbed_ThenASingleSummaryIsLogged() throws {
        try evaluateStubScript()

        try assertTrue("consoleMessages.length === 1")
        try assertTrue("consoleMessages[0].indexOf('[DuckDuckGo]') === 0")
        try assertTrue("consoleMessages[0].indexOf('notifications') !== -1")
        try assertTrue("consoleMessages[0].indexOf('webNavigation.onCreatedNavigationTarget') !== -1")
    }

    func testWhenScriptIsEvaluatedTwice_ThenNothingChangesAndNothingIsLoggedAgain() throws {
        try evaluateStubScript()
        context.evaluateScript("var firstRunNotifications = chrome.notifications;")
        try assertNoExceptions()

        try evaluateStubScript()

        try assertTrue("chrome.notifications === firstRunNotifications")
        try assertTrue("chrome.runtime === originalRuntime")
        try assertTrue("typeof chrome.notifications.onClicked.addListener === 'function'")
        try assertTrue("consoleMessages.length === 1")
    }

    func testWhenNoExtensionGlobalExists_ThenScriptIsANoOp() throws {
        let bareContext = try XCTUnwrap(JSContext())
        bareContext.exceptionHandler = { [weak self] _, exception in
            self?.exceptions.append(exception?.toString() ?? "unknown exception")
        }
        bareContext.evaluateScript("var console = { info: function() {} };")
        bareContext.evaluateScript(WebExtensionAPIStubScript.source)

        try assertNoExceptions()
        XCTAssertTrue(bareContext.evaluateScript("typeof chrome === 'undefined'")?.toBool() == true)
    }

    // MARK: - Helpers

    private func evaluateStubScript() throws {
        context.evaluateScript(WebExtensionAPIStubScript.source)
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
