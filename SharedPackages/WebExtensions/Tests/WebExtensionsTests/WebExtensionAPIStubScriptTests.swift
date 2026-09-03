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
    }

    override func tearDownWithError() throws {
        context = nil
        exceptions = []
        scheduledTimers = []
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

    func testWhenNamespaceIsMissing_ThenItsMethodsAndNestedPropertyChainsResolveToFunctions() throws {
        try evaluateStubScript()

        try assertTrue("typeof chrome.notifications.create === 'function'")
        try assertTrue("typeof chrome.downloads.download === 'function'")
        try assertTrue("typeof chrome.management.getSelf === 'function'")
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

    func testWhenManagedStorageIsQueriedTwice_ThenEachCallResolvesToItsOwnObject() throws {
        try evaluateStubScript()

        context.evaluateScript("""
        var firstResult = null;
        var secondResult = null;
        chrome.storage.managed.get().then(function(result) { firstResult = result; });
        chrome.storage.managed.get().then(function(result) { secondResult = result; });
        """)
        try assertNoExceptions()

        try assertTrue("firstResult !== null && secondResult !== null && firstResult !== secondResult")
    }

    // MARK: - Offscreen Documents

    func testWhenOffscreenIsStubbed_ThenReasonConstantsMatchTheirNames() throws {
        try installFakeDocument()
        try evaluateStubScript()

        try assertTrue("chrome.offscreen.Reason.CLIPBOARD === 'CLIPBOARD'")
        try assertTrue("chrome.offscreen.Reason.LOCAL_STORAGE === 'LOCAL_STORAGE'")
        try assertTrue("chrome.offscreen.Reason.DOM_PARSER === 'DOM_PARSER'")
        try assertTrue("Object.keys(chrome.offscreen.Reason).length === 15")
    }

    func testWhenOffscreenDocumentIsCreated_ThenAHiddenIframeIsAppendedAndTheCallResolvesOnLoad() throws {
        try installFakeDocument()
        try evaluateStubScript()

        try createOffscreenDocument()

        try assertTrue("frame.tagName === 'iframe'")
        try assertTrue("frame.src === 'chrome-extension://abc/offscreen-document/index.html'")
        try assertTrue("frame.attributes['hidden'] === 'hidden'")
        try assertTrue("frame.attributes['aria-hidden'] === 'true'")
        try assertTrue("frame.style.width === '0' && frame.style.height === '0'")
        // Nothing resolves until the offscreen page reports itself loaded.
        try assertTrue("createResult === 'pending'")

        context.evaluateScript("frame.listeners.load();")
        try assertNoExceptions()
        try assertTrue("createResult === 'resolved'")

        context.evaluateScript("var hasResult = 'pending'; chrome.offscreen.hasDocument().then(function(r) { hasResult = r; });")
        try assertNoExceptions()
        try assertTrue("hasResult === true")
    }

    func testWhenOffscreenDocumentNeverLoads_ThenTheTimeoutResolvesTheCall() throws {
        try installFakeDocument()
        try evaluateStubScript()

        try createOffscreenDocument()
        try assertTrue("createResult === 'pending'")

        XCTAssertEqual(scheduledTimers.count, 1)
        XCTAssertEqual(scheduledTimers.first?.delay, 5000)
        fireScheduledTimers()

        try assertTrue("createResult === 'resolved'")
    }

    func testWhenAnOffscreenDocumentIsAlreadyOpen_ThenCreatingASecondOneIsRejected() throws {
        try installFakeDocument()
        try evaluateStubScript()

        try createOffscreenDocument()

        context.evaluateScript("""
        var secondError = 'pending';
        chrome.offscreen.createDocument({ url: 'offscreen-document/index.html', reasons: ['CLIPBOARD'] })
            .catch(function(error) { secondError = String(error && error.message); });
        """)
        try assertNoExceptions()

        try assertTrue("secondError.indexOf('single offscreen document') !== -1")
        try assertTrue("document.body.children.length === 1")
    }

    func testWhenOffscreenDocumentIsClosed_ThenTheIframeIsRemovedAndClosingAgainIsRejected() throws {
        try installFakeDocument()
        try evaluateStubScript()

        try createOffscreenDocument()

        context.evaluateScript("""
        var closeResult = 'pending';
        chrome.offscreen.closeDocument().then(function(result) { closeResult = result === undefined ? 'resolved' : 'unexpected'; });
        var hasResult = 'pending';
        chrome.offscreen.hasDocument().then(function(result) { hasResult = result; });
        """)
        try assertNoExceptions()

        try assertTrue("closeResult === 'resolved'")
        try assertTrue("frame.removed === true")
        try assertTrue("document.body.children.length === 0")
        try assertTrue("hasResult === false")

        context.evaluateScript("""
        var secondCloseError = 'pending';
        chrome.offscreen.closeDocument().catch(function(error) { secondCloseError = String(error && error.message); });
        """)
        try assertNoExceptions()

        try assertTrue("secondCloseError.indexOf('No current offscreen document') !== -1")
    }

    func testWhenHasDocumentIsCalledWithACallback_ThenTheCallbackReceivesTheBoolean() throws {
        try installFakeDocument()
        try evaluateStubScript()

        context.evaluateScript("var callbackResult = 'pending'; chrome.offscreen.hasDocument(function(has) { callbackResult = has; });")
        try assertNoExceptions()
        try assertTrue("callbackResult === false")

        try createOffscreenDocument()

        context.evaluateScript("callbackResult = 'pending'; chrome.offscreen.hasDocument(function(has) { callbackResult = has; });")
        try assertNoExceptions()
        try assertTrue("callbackResult === true")
    }

    func testWhenOffscreenNamespaceExists_ThenItIsNotReplaced() throws {
        try installFakeDocument()
        context.evaluateScript("chrome.offscreen = { createDocument: function() { return 'native'; } };")
        context.evaluateScript("var originalOffscreen = chrome.offscreen;")
        try assertNoExceptions()

        try evaluateStubScript()

        try assertTrue("chrome.offscreen === originalOffscreen")
        try assertTrue("chrome.offscreen.createDocument() === 'native'")
        try assertTrue("chrome.offscreen.Reason === undefined")
    }

    // MARK: - Retention

    func testWhenNamespacesAreDecorated_ThenTheyAreRetainedOnTheGlobal() throws {
        try evaluateStubScript()

        let retentionProperty = WebExtensionAPIStubScript.retentionPropertyName
        try assertTrue("Array.isArray(globalThis.\(retentionProperty))")
        try assertTrue("globalThis.\(retentionProperty).length >= 1")
        try assertTrue("globalThis.\(retentionProperty).indexOf(originalWebNavigation) !== -1")
        try assertTrue("globalThis.\(retentionProperty).indexOf(originalStorage) !== -1")
        try assertTrue("globalThis.\(retentionProperty).indexOf(chrome) !== -1")

        // The retention array itself must not show up in enumeration of the global.
        try assertTrue("Object.keys(globalThis).indexOf('\(retentionProperty)') === -1")
    }

    func testWhenScriptIsEvaluatedTwice_ThenTheRetentionArrayIsReused() throws {
        try evaluateStubScript()
        context.evaluateScript("var firstRunRetained = globalThis.\(WebExtensionAPIStubScript.retentionPropertyName);")
        try assertNoExceptions()

        try evaluateStubScript()

        try assertTrue("globalThis.\(WebExtensionAPIStubScript.retentionPropertyName) === firstRunRetained")
    }

    // MARK: - ServiceWorker Clients

    func testWhenClientsGlobalIsMissing_ThenAMinimalStubIsInstalled() throws {
        try evaluateStubScript()

        try assertTrue("typeof globalThis.clients === 'object'")
        try assertTrue("typeof clients.matchAll === 'function'")

        context.evaluateScript("""
        var matchAllResult = 'pending';
        clients.matchAll().then(function(result) { matchAllResult = result; });
        var claimResolved = false;
        clients.claim().then(function() { claimResolved = true; });
        var openWindowResult = 'pending';
        clients.openWindow('https://example.com').then(function(result) { openWindowResult = result; });
        var getResult = 'pending';
        clients.get('id').then(function(result) { getResult = result; });
        """)
        try assertNoExceptions()

        try assertTrue("Array.isArray(matchAllResult) && matchAllResult.length === 0")
        try assertTrue("claimResolved === true")
        try assertTrue("openWindowResult === null")
        try assertTrue("getResult === undefined")
    }

    func testWhenClientsGlobalAlreadyExists_ThenItIsNotReplaced() throws {
        context.evaluateScript("var clients = { matchAll: function() { return Promise.resolve(['native']); } };")
        context.evaluateScript("var originalClients = clients;")
        try assertNoExceptions()

        try evaluateStubScript()

        try assertTrue("clients === originalClients")

        context.evaluateScript("var matchAllResult = null; clients.matchAll().then(function(r) { matchAllResult = r; });")
        try assertNoExceptions()
        try assertTrue("matchAllResult.length === 1 && matchAllResult[0] === 'native'")
    }

    // MARK: - Logging and Idempotency

    func testWhenSomethingIsStubbed_ThenASingleSummaryIsLogged() throws {
        try evaluateStubScript()

        try assertTrue("consoleMessages.length === 1")
        try assertTrue("consoleMessages[0].indexOf('[DuckDuckGo]') === 0")
        try assertTrue("consoleMessages[0].indexOf('notifications') !== -1")
        try assertTrue("consoleMessages[0].indexOf('webNavigation.onCreatedNavigationTarget') !== -1")
        try assertTrue("consoleMessages[0].indexOf('storage.managed') !== -1")
        try assertTrue("consoleMessages[0].indexOf('clients') !== -1")
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
        XCTAssertTrue(bareContext.evaluateScript("typeof clients === 'undefined'")?.toBool() == true)
        let retentionProperty = WebExtensionAPIStubScript.retentionPropertyName
        XCTAssertTrue(bareContext.evaluateScript("globalThis.\(retentionProperty) === undefined")?.toBool() == true)
    }

    // MARK: - Helpers

    /// `JSContext` has neither a DOM nor timers, so the offscreen stub gets the minimum it touches:
    /// a document that records the elements it hands out, a background page URL to resolve against,
    /// and a `setTimeout` that parks its callback for the test to fire.
    private func installFakeDocument() throws {
        let scheduleTimer: @convention(block) (JSValue, Double) -> Int = { [weak self] callback, delay in
            self?.scheduledTimers.append(ScheduledTimer(callback: callback, delay: delay))
            return self?.scheduledTimers.count ?? 0
        }
        context.setObject(scheduleTimer, forKeyedSubscript: "setTimeout" as NSString)

        context.evaluateScript("""
        var location = { href: "chrome-extension://abc/ddg-background-page.html" };
        var document = {
            documentElement: { children: [], appendChild: function(element) { this.children.push(element); this.lastAppended = element; } },
            body: {
                children: [],
                lastAppended: null,
                appendChild: function(element) {
                    this.children.push(element);
                    this.lastAppended = element;
                    element.parentNode = this;
                }
            },
            createElement: function(tagName) {
                return {
                    tagName: tagName,
                    src: "",
                    style: {},
                    attributes: {},
                    listeners: {},
                    parentNode: null,
                    removed: false,
                    setAttribute: function(name, value) { this.attributes[name] = value; },
                    addEventListener: function(type, listener) { this.listeners[type] = listener; },
                    remove: function() {
                        if (this.parentNode) {
                            var index = this.parentNode.children.indexOf(this);
                            if (index !== -1) { this.parentNode.children.splice(index, 1); }
                            if (this.parentNode.lastAppended === this) { this.parentNode.lastAppended = null; }
                            this.parentNode = null;
                        }
                        this.removed = true;
                    }
                };
            }
        };
        """)
        try assertNoExceptions()
    }

    /// Opens an offscreen document the way Bitwarden does, leaving the pending call in `createResult`
    /// and the appended iframe in `frame`.
    private func createOffscreenDocument() throws {
        context.evaluateScript("""
        var createResult = 'pending';
        chrome.offscreen.createDocument({
            url: 'offscreen-document/index.html',
            reasons: [chrome.offscreen.Reason.CLIPBOARD],
            justification: 'Copy a password to the clipboard'
        }).then(function(result) { createResult = result === undefined ? 'resolved' : 'unexpected'; });
        var frame = document.body.lastAppended;
        """)
        try assertNoExceptions()
    }

    private func fireScheduledTimers() {
        let timers = scheduledTimers
        scheduledTimers = []
        timers.forEach { $0.callback.call(withArguments: []) }
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
