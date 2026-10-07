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

    private struct ScheduledTimer {
        let callback: JSValue
        let delay: Double
    }

    private var context: JSContext!
    private var exceptions: [String] = []
    private var scheduledTimers: [ScheduledTimer] = []
    /// Backs the fake `chrome.storage.local`, as JSON per key, so it outlives a context: two
    /// contexts made in one test see the same storage, like two pages of one extension.
    private var storageLocalItems: [String: String] = [:]

    override func setUpWithError() throws {
        try super.setUpWithError()
        try makeExtensionPageContext()
    }

    override func tearDownWithError() throws {
        context = nil
        exceptions = []
        scheduledTimers = []
        storageLocalItems = [:]
        try super.tearDownWithError()
    }

    // MARK: - Page Origin

    func testWhenPageIsAWebsite_ThenScriptDoesNothing() throws {
        context.evaluateScript("""
        var location = { protocol: "https:" };
        chrome = { runtime: {} };
        """)
        try assertNoExceptions()

        try evaluateStubScript()

        try assertTrue("chrome.notifications === undefined")
        try assertTrue("globalThis['\(WebExtensionAPIStubScript.retentionPropertyName)'] === undefined")
        try assertTrue("consoleMessages.length === 0")
    }

    func testWhenPageIsAnExtensionPage_ThenScriptInstallsStubs() throws {
        context.evaluateScript("""
        var location = { protocol: "webkit-extension:" };
        """)
        try assertNoExceptions()

        try evaluateStubScript()

        try assertTrue("chrome.notifications !== undefined")
    }

    // MARK: - DuckDuckGo Extensions

    func testWhenManifestIsADuckDuckGoExtension_ThenScriptDoesNothing() throws {
        context.evaluateScript("""
        chrome.runtime.getManifest = function() {
            return { browser_specific_settings: { duckduckgo: { id: "com.duckduckgo.web-extension.embedded" } } };
        };
        """)
        try assertNoExceptions()

        try evaluateStubScript()

        try assertTrue("chrome.notifications === undefined")
        try assertTrue("globalThis['\(WebExtensionAPIStubScript.retentionPropertyName)'] === undefined")
    }

    func testWhenManifestIsThirdParty_ThenScriptInstallsStubs() throws {
        context.evaluateScript("""
        chrome.runtime.getManifest = function() { return { name: "Third party" }; };
        """)
        try assertNoExceptions()

        try evaluateStubScript()

        try assertTrue("chrome.notifications !== undefined")
    }

    // MARK: - Missing Namespaces

    func testWhenNamespaceIsMissing_ThenItsEventsExposeListenerAPI() throws {
        try evaluateStubScript()

        try assertTrue("typeof chrome.notifications.onClicked.addListener === 'function'")
        try assertTrue("typeof chrome.notifications.onClicked.removeListener === 'function'")
        try assertTrue("chrome.notifications.onClicked.hasListener() === false")
        try assertTrue("chrome.notifications.onClicked.hasListeners() === false")
    }

    func testWhenNamespaceIsMissing_ThenItsMethodsAndNestedPropertyChainsResolveToFunctions() throws {
        try evaluateStubScript()

        try assertTrue("typeof chrome.notifications.create === 'function'")
        try assertTrue("typeof chrome.downloads.download === 'function'")
        try assertTrue("typeof chrome.management.getSelf === 'function'")
        try assertTrue("typeof chrome.privacy.services.passwordSavingEnabled.get === 'function'")
        try assertTrue("typeof chrome.browsingData.removeCache === 'function'")
    }

    func testWhenNamespaceIsMissing_ThenItIsAnObjectWhoseMembersAreCallable() throws {
        try evaluateStubScript()

        try assertTrue("typeof chrome.notifications === 'object'")
        try assertTrue("typeof chrome.notifications.create === 'function'")
        context.evaluateScript("var namespaceCallThrew = false; try { chrome.notifications(); } catch (error) { namespaceCallThrew = true; }")
        try assertTrue("namespaceCallThrew")
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
        try assertTrue("callbackArguments !== null && callbackArguments.length === 1 && callbackArguments[0] === undefined")
    }

    func testWhenStubCallbackThrows_ThenTheErrorIsThrownAgainFromATimer() throws {
        let scheduleTimer: @convention(block) (JSValue, Double) -> Int = { [weak self] callback, delay in
            self?.scheduledTimers.append(ScheduledTimer(callback: callback, delay: delay))
            return self?.scheduledTimers.count ?? 0
        }
        context.setObject(scheduleTimer, forKeyedSubscript: "setTimeout" as NSString)
        try evaluateStubScript()

        context.evaluateScript("chrome.topSites.get(function(sites) { sites.forEach(function() {}); });")
        try assertNoExceptions()

        XCTAssertEqual(scheduledTimers.count, 1)
        scheduledTimers.first?.callback.call(withArguments: [])
        XCTAssertEqual(exceptions.count, 1)
        exceptions = []
    }

    func testWhenStubIsInspected_ThenItDoesNotLookLikeAThenable() throws {
        try evaluateStubScript()

        try assertTrue("chrome.notifications.then === undefined")
        try assertTrue("chrome.privacy.services.then === undefined")
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
        try assertTrue("typeof chrome.runtime.onSuspend.addListener === 'function'")

        try assertTrue("chrome.webNavigation.onCommitted === originalOnCommitted")
    }

    func testWhenSubNamespaceIsMissing_ThenItIsStubbedAndSiblingsAreUntouched() throws {
        try evaluateStubScript()

        try assertTrue("typeof chrome.storage.managed.onChanged.addListener === 'function'")
        try assertTrue("typeof chrome.storage.managed.get === 'function'")
        try assertTrue("chrome.storage === originalStorage")
        try assertTrue("chrome.storage.local === originalStorageLocal")
    }

    func testWhenManagedStorageIsStubbed_ThenGetResolvesToAnEmptyObject() throws {
        try evaluateStubScript()

        context.evaluateScript("""
        var promiseResult = 'pending';
        chrome.storage.managed.get('CredentialIntelligence').then(function(result) { promiseResult = result; });
        var callbackResult = 'pending';
        chrome.storage.managed.get('CredentialIntelligence', function(result) { callbackResult = result; });
        var bytesResult = 'pending';
        chrome.storage.managed.getBytesInUse().then(function(result) { bytesResult = result; });
        """)
        try assertNoExceptions()

        try assertTrue("promiseResult !== null && typeof promiseResult === 'object'")
        try assertTrue("Object.keys(promiseResult).length === 0")
        // The read that used to throw: an absent policy must come back as `undefined`, not an error.
        try assertTrue("promiseResult['CredentialIntelligence'] === undefined")

        try assertTrue("callbackResult !== null && typeof callbackResult === 'object'")
        try assertTrue("Object.keys(callbackResult).length === 0")

        try assertTrue("bytesResult === 0")
        try assertTrue("typeof chrome.storage.managed.onChanged.addListener === 'function'")
    }

    // MARK: - Logging and Idempotency

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
        let retentionProperty = WebExtensionAPIStubScript.retentionPropertyName
        XCTAssertTrue(bareContext.evaluateScript("globalThis.\(retentionProperty) === undefined")?.toBool() == true)
    }

    // MARK: - Compatibility Reports

    func testWhenNestedStubIsCalled_ThenTheFullPathIsReported() throws {
        try installFakeReporting()
        try evaluateStubScript()

        context.evaluateScript("chrome.notifications.create({ title: 'secret' }); chrome.notifications.foo.bar();")
        try assertNoExceptions()

        try assertReports("[{\"kind\":\"stubbed\",\"api\":\"notifications.create\"},{\"kind\":\"stubbed\",\"api\":\"notifications.foo.bar\"}]")
    }

    func testWhenStubIsOnlyRead_ThenNothingIsReported() throws {
        try installFakeReporting()
        try evaluateStubScript()

        context.evaluateScript("chrome.notifications.create; chrome.notifications.onClicked; chrome.notifications.onClicked.hasListener();")
        try assertNoExceptions()

        try assertReports("[]")
    }

    func testWhenListenerIsAddedToAStubbedEvent_ThenItIsReported() throws {
        try installFakeReporting()
        try evaluateStubScript()

        context.evaluateScript("""
        chrome.notifications.onClicked.addListener(function() {});
        chrome.webNavigation.onCreatedNavigationTarget.addListener(function() {});
        """)
        try assertNoExceptions()

        try assertReports("""
        [{"kind":"stubbed","api":"notifications.onClicked.addListener"},\
        {"kind":"stubbed","api":"webNavigation.onCreatedNavigationTarget.addListener"}]
        """)
    }

    func testWhenManagedStorageIsUsed_ThenNothingIsReported() throws {
        try installFakeReporting()
        try evaluateStubScript()

        context.evaluateScript("""
        chrome.storage.managed.get();
        chrome.storage.managed.onChanged.addListener(function() {});
        """)
        try assertNoExceptions()

        try assertReports("[]")
    }

    func testWhenAStubIsSerializedOrConverted_ThenNothingIsReported() throws {
        try installFakeReporting()
        try evaluateStubScript()

        context.evaluateScript("JSON.stringify({ stub: chrome.notifications }); chrome.notifications.valueOf();")
        try assertNoExceptions()

        try assertReports("[]")
    }

    func testWhenAStubIsCalledThroughCallApplyOrBind_ThenTheStubPathIsReported() throws {
        try installFakeReporting()
        try evaluateStubScript()

        context.evaluateScript("""
        chrome.downloads.download.call(null, {});
        chrome.downloads.pause.apply(null, [1]);
        chrome.downloads.resume.bind(null)(1);
        """)
        try assertNoExceptions()

        try assertReports("""
        [{"kind":"stubbed","api":"downloads.download"},\
        {"kind":"stubbed","api":"downloads.pause"},\
        {"kind":"stubbed","api":"downloads.resume"}]
        """)
    }

    // MARK: - Helpers

    /// A fresh `JSContext` shaped like an extension page: WebKit exposes only a subset of `chrome.*`,
    /// and `console` is provided so the script's summary log does not throw. `storage.local` is
    /// backed by `storageLocalItems`, so a second context sees what the first one stored.
    private func makeExtensionPageContext() throws {
        exceptions = []
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
        var chrome = {
            runtime: {},
            webNavigation: { onCommitted: { addListener: function() {} } },
            tabs: {},
            storage: { local: {} }
        };
        var originalRuntime = chrome.runtime;
        var originalTabs = chrome.tabs;
        var originalWebNavigation = chrome.webNavigation;
        var originalOnCommitted = chrome.webNavigation.onCommitted;
        var originalStorage = chrome.storage;
        var originalStorageLocal = chrome.storage.local;
        """)
        try assertNoExceptions()
        try installFakeStorageLocal()
    }

    /// Callback-style `storage.local.get`/`set`, answering on a microtask like the real one. Only
    /// the key shapes the script under test uses are supported: a single key, or an array of keys.
    private func installFakeStorageLocal() throws {
        let readItem: @convention(block) (String) -> String = { [weak self] key in
            self?.storageLocalItems[key] ?? ""
        }
        let writeItem: @convention(block) (String, String) -> Void = { [weak self] key, json in
            self?.storageLocalItems[key] = json
        }
        context.setObject(readItem, forKeyedSubscript: "__readStorageLocalItem" as NSString)
        context.setObject(writeItem, forKeyedSubscript: "__writeStorageLocalItem" as NSString)

        context.evaluateScript("""
        chrome.storage.local.get = function(keys, callback) {
            var names = Array.isArray(keys) ? keys : [keys];
            var items = {};
            names.forEach(function(name) {
                var json = __readStorageLocalItem(String(name));
                if (json !== "") {
                    items[name] = JSON.parse(json);
                }
            });
            Promise.resolve().then(function() { callback(items); });
        };
        chrome.storage.local.set = function(items, callback) {
            Object.keys(items).forEach(function(name) {
                __writeStorageLocalItem(name, JSON.stringify(items[name]));
            });
            Promise.resolve().then(function() { callback(); });
        };
        """)
        try assertNoExceptions()
    }

    /// A page with the report handler WebKit adds once the app registers it, and the compatibility
    /// script the stubs report through. `reports` collects what reaches the handler.
    private func installFakeReporting() throws {
        context.evaluateScript("""
        var reports = [];
        var listeners = {};
        var webkit = { messageHandlers: {
            "\(WebExtensionAPICompatibilityScript.messageHandlerName)": {
                postMessage: function(payload) { reports.push(payload); }
            }
        } };
        globalThis.addEventListener = function(type, listener) { listeners[type] = listener; };
        """)
        context.evaluateScript(WebExtensionAPICompatibilityScript.source)
        try assertNoExceptions()
    }

    private func assertReports(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let escaped = json.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        try assertTrue("JSON.stringify(reports) === '\(escaped)'", file: file, line: line)
    }

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
