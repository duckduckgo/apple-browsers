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
    private var scheduledIntervals: [ScheduledTimer] = []
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
        scheduledIntervals = []
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

    // MARK: - Explicit Resource Management Symbols

    func testWhenScriptRuns_ThenDisposeSymbolsAreDefined() throws {
        try evaluateStubScript()

        try assertTrue("typeof Symbol.dispose === 'symbol'")
        try assertTrue("typeof Symbol.asyncDispose === 'symbol'")
        try assertTrue("Symbol.dispose !== Symbol.asyncDispose")
    }

    func testWhenCodeUsesTypeScriptDisposeHelperPattern_ThenResourceIsDisposed() throws {
        try evaluateStubScript()

        // Mirrors what TypeScript's `__addDisposableResource` / `__disposeResources` do for `using`.
        try assertTrue("""
        (function() {
            var disposed = false;
            var resource = {};
            resource[Symbol.dispose] = function() { disposed = true; };
            if (!Symbol.dispose) { throw new TypeError("Symbol.dispose is not defined."); }
            var dispose = resource[Symbol.dispose];
            if (typeof dispose !== "function") { throw new TypeError("Object not disposable."); }
            dispose.call(resource);
            return disposed;
        })()
        """)
    }

    func testWhenDisposeSymbolAlreadyExists_ThenScriptKeepsIt() throws {
        context.evaluateScript("""
        var existingDispose = typeof Symbol.dispose === "symbol" ? Symbol.dispose : Symbol("existing");
        if (typeof Symbol.dispose !== "symbol") {
            Object.defineProperty(Symbol, "dispose", { value: existingDispose, configurable: true });
        }
        """)
        try assertNoExceptions()

        try evaluateStubScript()

        try assertTrue("Symbol.dispose === existingDispose")
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
        try assertTrue("typeof chrome.sidePanel.options.nested.get === 'function'")
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

        try assertTrue("typeof chrome.downloads.download({}) === 'object'")
        try assertTrue("typeof chrome.downloads.download({}).then === 'function'")
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
        try assertTrue("chrome.downloads.state.then === undefined")
    }

    // MARK: - Idle

    func testWhenIdleIsQueried_ThenTheReplyIsHandedToThePromiseAndTheCallback() throws {
        try installFakeIdleHandler(reply: "locked")
        try evaluateStubScript()

        context.evaluateScript("""
        var promiseState = 'pending';
        var callbackState = 'pending';
        chrome.idle.queryState(120, function(state) { callbackState = state; }).then(function(state) { promiseState = state; });
        """)
        try assertNoExceptions()

        try assertTrue("promiseState === 'locked' && callbackState === 'locked'")
        try assertTrue("idleRequests.length === 1 && idleRequests[0].detectionInterval === 120")
    }

    func testWhenIdleIsQueriedWithoutACallback_ThenTheStatesAreResolvedAsGiven() throws {
        try installFakeIdleHandler(reply: "idle")
        try evaluateStubScript()

        context.evaluateScript("var promiseState = 'pending'; chrome.idle.queryState(60).then(function(state) { promiseState = state; });")
        try assertNoExceptions()

        try assertTrue("promiseState === 'idle'")
    }

    func testWhenTheIdleHandlerFails_ThenQueryStateAnswersActive() throws {
        try installFakeIdleHandler(reply: "idle", fails: true)
        try evaluateStubScript()

        context.evaluateScript("var promiseState = 'pending'; chrome.idle.queryState(60).then(function(state) { promiseState = state; });")
        try assertNoExceptions()

        try assertTrue("promiseState === 'active'")
    }

    func testWhenTheIdleHandlerAnswersAnUnknownState_ThenQueryStateAnswersActive() throws {
        try installFakeIdleHandler(reply: "asleep")
        try evaluateStubScript()

        context.evaluateScript("var promiseState = 'pending'; chrome.idle.queryState(60).then(function(state) { promiseState = state; });")
        try assertNoExceptions()

        try assertTrue("promiseState === 'active'")
    }

    func testWhenThereIsNoIdleHandler_ThenQueryStateAnswersActiveWithBothStyles() throws {
        try evaluateStubScript()

        context.evaluateScript("""
        var promiseState = 'pending';
        var callbackState = 'pending';
        chrome.idle.queryState(60, function(state) { callbackState = state; }).then(function(state) { promiseState = state; });
        """)
        try assertNoExceptions()

        try assertTrue("promiseState === 'active' && callbackState === 'active'")
    }

    func testWhenTheDetectionIntervalIsBelowChromesMinimum_ThenItIsClampedTo15() throws {
        try installFakeIdleHandler(reply: "active")
        try evaluateStubScript()

        context.evaluateScript("""
        chrome.idle.queryState(1);
        chrome.idle.queryState(0);
        chrome.idle.queryState(90.7);
        chrome.idle.queryState('soon');
        """)
        try assertNoExceptions()

        try assertTrue("JSON.stringify(idleRequests.map(function(r) { return r.detectionInterval; })) === '[15,15,90,60]'")
    }

    func testWhenTheDetectionIntervalIsSet_ThenPollingUsesItClampedAndTheDefaultIs60() throws {
        try installFakeIdleHandler(reply: "active")
        try installFakeIntervals()
        try evaluateStubScript()

        context.evaluateScript("chrome.idle.onStateChanged.addListener(function() {});")
        firePolls()
        try assertTrue("idleRequests[0].detectionInterval === 60")

        context.evaluateScript("chrome.idle.setDetectionInterval(5);")
        firePolls()
        try assertTrue("idleRequests[1].detectionInterval === 15")

        context.evaluateScript("chrome.idle.setDetectionInterval(300);")
        firePolls()
        try assertTrue("idleRequests[2].detectionInterval === 300")
    }

    func testWhenTheStateChanges_ThenListenersAreFiredOnlyOnTheChange() throws {
        try installFakeIdleHandler(reply: "active")
        try installFakeIntervals()
        try evaluateStubScript()
        context.evaluateScript("var heard = []; chrome.idle.onStateChanged.addListener(function(state) { heard.push(state); });")
        try assertNoExceptions()

        firePolls()
        try assertTrue("heard.length === 0")

        context.evaluateScript("idleReply = 'idle';")
        firePolls()
        firePolls()
        try assertTrue("JSON.stringify(heard) === '[\"idle\"]'")

        context.evaluateScript("idleReply = 'locked';")
        firePolls()
        context.evaluateScript("idleReply = 'active';")
        firePolls()
        try assertTrue("JSON.stringify(heard) === '[\"idle\",\"locked\",\"active\"]'")
    }

    func testWhenSeveralListenersAreAdded_ThenASingleTimerPollsEvery15Seconds() throws {
        try installFakeIdleHandler(reply: "active")
        try installFakeIntervals()
        try evaluateStubScript()

        context.evaluateScript("""
        function first() {}
        function second() {}
        chrome.idle.onStateChanged.addListener(first);
        chrome.idle.onStateChanged.addListener(first);
        chrome.idle.onStateChanged.addListener(second);
        """)
        try assertNoExceptions()

        XCTAssertEqual(scheduledIntervals.count, 1)
        XCTAssertEqual(scheduledIntervals.first?.delay, 15000)
        try assertTrue("chrome.idle.onStateChanged.hasListener(first) && chrome.idle.onStateChanged.hasListener(second)")
    }

    func testWhenTheLastListenerIsRemoved_ThenThePollingStops() throws {
        try installFakeIdleHandler(reply: "active")
        try installFakeIntervals()
        try evaluateStubScript()

        context.evaluateScript("""
        function first() {}
        function second() {}
        chrome.idle.onStateChanged.addListener(first);
        chrome.idle.onStateChanged.addListener(second);
        chrome.idle.onStateChanged.removeListener(first);
        """)
        try assertNoExceptions()
        try assertTrue("clearedIntervals.length === 0 && chrome.idle.onStateChanged.hasListeners()")

        context.evaluateScript("chrome.idle.onStateChanged.removeListener(second);")
        try assertNoExceptions()
        try assertTrue("clearedIntervals.length === 1 && !chrome.idle.onStateChanged.hasListeners()")
    }

    func testWhenAListenerThrows_ThenTheOthersStillHearTheChange() throws {
        try installFakeIdleHandler(reply: "idle")
        try installFakeIntervals()
        try evaluateStubScript()
        context.evaluateScript("""
        var heard = [];
        chrome.idle.onStateChanged.addListener(function() { throw new Error('boom'); });
        chrome.idle.onStateChanged.addListener(function(state) { heard.push(state); });
        """)

        firePolls()

        try assertNoExceptions()
        try assertTrue("JSON.stringify(heard) === '[\"idle\"]'")
    }

    func testWhenAutoLockDelayIsQueried_ThenItResolvesZero() throws {
        try evaluateStubScript()

        context.evaluateScript("var delay = 'pending'; chrome.idle.getAutoLockDelay().then(function(value) { delay = value; });")
        try assertNoExceptions()

        try assertTrue("delay === 0")
    }

    func testWhenIdleNamespaceExists_ThenItIsNotReplaced() throws {
        context.evaluateScript("var original = { custom: true }; chrome.idle = original;")
        try evaluateStubScript()

        try assertTrue("chrome.idle === original")
    }

    func testWhenIdleIsAskedAbout_ThenTheVirtualPermissionIsGrantedWithoutAskingTheHost() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['idle'] })")

        try assertTrue("permissionsResult === true")
        try assertTrue("permissionsLog.contains.length === 0")
    }

    func testWhenIdleIsRequestedWithAnotherPermission_ThenOnlyTheOtherOneReachesTheHost() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.request({ permissions: ['idle', 'nativeMessaging'] })")

        try assertTrue("permissionsResult === true")
        try assertTrue("JSON.stringify(permissionsLog.request) === '[{\"permissions\":[\"nativeMessaging\"]}]'")
    }

    // MARK: - Virtual Permissions

    func testWhenPrivacyIsUnknownToTheHost_ThenContainsResolvesTrueWithoutAskingTheHost() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['privacy'] })")

        try assertTrue("permissionsResult === true")
        try assertTrue("permissionsLog.contains.length === 0")
    }

    func testWhenContainsMixesPrivacyWithAHostPermission_ThenTheHostAnswersForTheRest() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['privacy', 'tabs'] })")
        try assertTrue("permissionsResult === false")
        try assertTrue("permissionsLog.contains.length === 1")
        try assertTrue("permissionsLog.contains[0].permissions.join(',') === 'tabs'")

        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['privacy', 'nativeMessaging'] })")
        try assertTrue("permissionsResult === true")
    }

    func testWhenContainsMixesPrivacyWithAnUnknownPermission_ThenItResolvesFalse() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['privacy', 'downloads'] })")

        try assertTrue("permissionsResult === false")
    }

    func testWhenPrivacyIsRequested_ThenRequestResolvesTrueWithBothStyles() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.request({ permissions: ['privacy'] })")
        try assertTrue("permissionsResult === true")
        try assertTrue("permissionsLog.request.length === 0")

        // Bitwarden's popup asks this way from its click handler.
        context.evaluateScript("""
        var requestCallbackResult = 'pending';
        chrome.permissions.request({ permissions: ['privacy'] }, function(granted) { requestCallbackResult = granted; });
        """)
        try assertNoExceptions()
        try assertTrue("requestCallbackResult === true")
    }

    func testWhenOnlyPrivacyIsRemoved_ThenRemoveResolvesFalseAndTheHostIsNotAsked() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.remove({ permissions: ['privacy'] })")

        try assertTrue("permissionsResult === false")
        try assertTrue("permissionsLog.remove.length === 0")
    }

    // MARK: - Privacy Settings

    func testWhenPrivacyIsStubbed_ThenServicesIsAnObjectAndNetworkIsANestableStub() throws {
        try evaluateStubScript()

        try assertTrue("chrome.privacy.services !== null && typeof chrome.privacy.services === 'object'")
        try assertTrue("typeof chrome.privacy.network === 'function'")
        try assertTrue("typeof chrome.privacy.network.webRTCIPHandlingPolicy.get === 'function'")
        try assertTrue("typeof chrome.privacy.websites.thirdPartyCookiesAllowed.set === 'function'")
        try assertTrue("globalThis.\(WebExtensionAPIStubScript.retentionPropertyName).indexOf(chrome.privacy) !== -1")
        try assertTrue("consoleMessages[0].indexOf('privacy') !== -1")
    }

    func testWhenEachServicesSettingIsInspected_ThenItHasTheChromeSettingShape() throws {
        try evaluateStubScript()

        for name in ["passwordSavingEnabled", "autofillAddressEnabled", "autofillCreditCardEnabled"] {
            let setting = "chrome.privacy.services.\(name)"
            try assertTrue("typeof \(setting).get === 'function'")
            try assertTrue("typeof \(setting).set === 'function'")
            try assertTrue("typeof \(setting).clear === 'function'")
            try assertTrue("typeof \(setting).onChange.addListener === 'function'")
        }
    }

    func testWhenNothingWasSet_ThenGetAnswersTheControllableDefaultWithBothStyles() throws {
        try evaluateStubScript()

        context.evaluateScript("""
        var callbackResult = 'pending';
        chrome.privacy.services.passwordSavingEnabled.get({}, function(details) { callbackResult = details; });
        var promiseResult = 'pending';
        chrome.privacy.services.passwordSavingEnabled.get({}).then(function(details) { promiseResult = details; });
        """)
        try assertNoExceptions()

        try assertTrue("callbackResult.value === true && callbackResult.levelOfControl === 'controllable_by_this_extension'")
        try assertTrue("promiseResult.value === true && promiseResult.levelOfControl === 'controllable_by_this_extension'")
    }

    func testWhenASettingIsSetToFalse_ThenGetAnswersControlledAndTheValueIsStored() throws {
        try evaluateStubScript()

        try disableBrowserPasswordManagerTheWayBitwardenDoes()

        try assertTrue("setResult === undefined")
        try assertTrue("overridden === true")
        try assertTrue("passwordSaving.value === false && passwordSaving.levelOfControl === 'controlled_by_this_extension'")

        XCTAssertEqual(try storedPrivacySettings(), [
            "passwordSavingEnabled": false,
            "autofillAddressEnabled": false,
            "autofillCreditCardEnabled": false
        ])
    }

    func testWhenAnotherPageOpens_ThenItReadsTheStoredSettingBack() throws {
        try evaluateStubScript()
        try disableBrowserPasswordManagerTheWayBitwardenDoes()

        // A fresh popup: a new page with its own script run, sharing the extension's storage.
        try makeExtensionPageContext()
        try evaluateStubScript()

        context.evaluateScript("""
        var reopened = 'pending';
        chrome.privacy.services.autofillCreditCardEnabled.get({}, function(details) { reopened = details; });
        """)
        try assertNoExceptions()

        try assertTrue("reopened.value === false && reopened.levelOfControl === 'controlled_by_this_extension'")
    }

    func testWhenASettingIsSetBackToTrue_ThenItStaysControlledWithTheNewValue() throws {
        try evaluateStubScript()
        try disableBrowserPasswordManagerTheWayBitwardenDoes()

        context.evaluateScript("""
        var restored = 'pending';
        chrome.privacy.services.passwordSavingEnabled.set({ value: true }).then(function() {
            return chrome.privacy.services.passwordSavingEnabled.get({});
        }).then(function(details) { restored = details; });
        """)
        try assertNoExceptions()

        try assertTrue("restored.value === true && restored.levelOfControl === 'controlled_by_this_extension'")
    }

    func testWhenASettingIsCleared_ThenGetAnswersTheDefaultAgain() throws {
        try evaluateStubScript()
        try disableBrowserPasswordManagerTheWayBitwardenDoes()

        context.evaluateScript("""
        var clearCallbackResult = 'pending';
        var cleared = 'pending';
        chrome.privacy.services.passwordSavingEnabled.clear({}, function(result) { clearCallbackResult = result; });
        chrome.privacy.services.passwordSavingEnabled.get({}).then(function(details) { cleared = details; });
        """)
        try assertNoExceptions()

        try assertTrue("clearCallbackResult === undefined")
        try assertTrue("cleared.value === true && cleared.levelOfControl === 'controllable_by_this_extension'")
        // Only the cleared setting went back to the default.
        let settings = try storedPrivacySettings()
        XCTAssertNil(settings["passwordSavingEnabled"])
        XCTAssertEqual(settings["autofillAddressEnabled"], false)
    }

    func testWhenStorageIsUnavailable_ThenSettingsLiveInMemoryAndNothingThrows() throws {
        context.evaluateScript("delete chrome.storage;")
        try assertNoExceptions()
        try evaluateStubScript()

        try disableBrowserPasswordManagerTheWayBitwardenDoes()

        try assertTrue("overridden === true")
        XCTAssertTrue(storageLocalItems.isEmpty)
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

    // MARK: - Namespace Constants

    func testWhenConstantsAreMissing_ThenChromesValuesAreInstalled() throws {
        try installFakeConstantNamespaces()
        try evaluateStubScript()

        // The call site that sent us here: Bitwarden's autofill injection.
        try assertTrue("chrome.scripting.ExecutionWorld.ISOLATED === 'ISOLATED'")
        try assertTrue("chrome.scripting.ExecutionWorld.MAIN === 'MAIN'")

        try assertTrue("chrome.tabs.TAB_ID_NONE === -1")

        try assertTrue("chrome.windows.WINDOW_ID_NONE === -1")
        try assertTrue("chrome.windows.WINDOW_ID_CURRENT === -2")
    }

    func testWhenConstantsAreInstalled_ThenTheyAreFrozenAndTheirNamespacesAreUntouched() throws {
        try installFakeConstantNamespaces()
        try evaluateStubScript()

        try assertTrue("Object.isFrozen(chrome.scripting.ExecutionWorld)")

        context.evaluateScript("try { chrome.scripting.ExecutionWorld.ISOLATED = 'tampered'; } catch (error) {}")
        try assertTrue("chrome.scripting.ExecutionWorld.ISOLATED === 'ISOLATED'")

        try assertTrue("chrome.scripting === originalScripting")
        try assertTrue("chrome.scripting.executeScript === originalExecuteScript")
        try assertTrue("chrome.windows === originalWindows")
    }

    func testWhenAConstantAlreadyExists_ThenItIsNotReplaced() throws {
        try installFakeConstantNamespaces()
        context.evaluateScript("""
        chrome.scripting.ExecutionWorld = { ISOLATED: 'x' };
        var originalExecutionWorld = chrome.scripting.ExecutionWorld;
        """)
        try assertNoExceptions()

        try evaluateStubScript()

        try assertTrue("chrome.scripting.ExecutionWorld === originalExecutionWorld")
        try assertTrue("chrome.scripting.ExecutionWorld.ISOLATED === 'x'")
        try assertTrue("chrome.scripting.ExecutionWorld.MAIN === undefined")
    }

    func testWhenNamespaceForConstantsIsMissing_ThenNothingIsInstalledAndNothingThrows() throws {
        // The default context has neither `scripting` nor `windows`, and neither is on the
        // stubbed-namespace list, so their constants have nowhere to go.
        try evaluateStubScript()

        try assertTrue("chrome.scripting === undefined")
        try assertTrue("chrome.windows === undefined")
        // Namespaces that are present still get theirs.
        try assertTrue("chrome.tabs.TAB_ID_NONE === -1")
    }

    func testWhenConstantsAreStubbed_ThenTheyAreNamedInTheSummary() throws {
        try installFakeConstantNamespaces()
        try evaluateStubScript()

        try assertTrue("consoleMessages.length === 1")
        try assertTrue("consoleMessages[0].indexOf('scripting.ExecutionWorld') !== -1")
        try assertTrue("consoleMessages[0].indexOf('tabs.TAB_ID_NONE') !== -1")
    }

    func testWhenScriptIsEvaluatedTwice_ThenConstantsAreUnchanged() throws {
        try installFakeConstantNamespaces()
        try evaluateStubScript()
        context.evaluateScript("var firstRunExecutionWorld = chrome.scripting.ExecutionWorld;")
        try assertNoExceptions()

        try evaluateStubScript()

        try assertTrue("chrome.scripting.ExecutionWorld === firstRunExecutionWorld")
        try assertTrue("chrome.tabs.TAB_ID_NONE === -1")
        try assertTrue("consoleMessages.length === 1")
    }

    // MARK: - Permissions

    func testWhenPermissionIsUnknownToTheHost_ThenContainsResolvesFalseInsteadOfThrowing() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['downloads'] })")

        try assertTrue("permissionsResult === false")
    }

    func testWhenPermissionIsKnownAndGranted_ThenContainsResolvesTrue() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['nativeMessaging'] })")

        try assertTrue("permissionsResult === true")
        // A host that recognizes every name is asked exactly once, as if the wrapper were not there.
        try assertTrue("permissionsLog.contains.length === 1")
    }

    func testWhenOneOfSeveralPermissionsIsUnknown_ThenContainsResolvesFalse() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['nativeMessaging', 'downloads'] })")

        try assertTrue("permissionsResult === false")
    }

    func testWhenPermissionIsKnownButNotGranted_ThenContainsResolvesFalse() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['tabs'] })")

        try assertTrue("permissionsResult === false")
    }

    func testWhenContainsIsCalledWithACallback_ThenTheCallbackReceivesTheBoolean() throws {
        try installFakePermissions()
        try evaluateStubScript()

        context.evaluateScript("""
        var unknownCallbackResult = 'pending';
        var grantedCallbackResult = 'pending';
        chrome.permissions.contains({ permissions: ['downloads'] }, function(result) { unknownCallbackResult = result; });
        chrome.permissions.contains({ permissions: ['nativeMessaging'] }, function(result) { grantedCallbackResult = result; });
        """)
        try assertNoExceptions()

        try assertTrue("unknownCallbackResult === false")
        try assertTrue("grantedCallbackResult === true")
    }

    func testWhenContainsIsCalledWithoutItsOwner_ThenItStillAnswers() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("(function() { var contains = chrome.permissions.contains; return contains({ permissions: ['downloads'] }); })()")

        try assertTrue("permissionsResult === false")
    }

    func testWhenPermissionIsUnknown_ThenRequestResolvesFalseAndAKnownOneIsRequested() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.request({ permissions: ['downloads'] })")
        try assertTrue("permissionsResult === false")

        try evaluatePermissionsCall("chrome.permissions.request({ permissions: ['nativeMessaging'] })")
        try assertTrue("permissionsResult === true")
    }

    func testWhenRemoveIncludesAnUnknownPermission_ThenOnlyTheKnownNamesAreRemoved() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.remove({ permissions: ['downloads', 'nativeMessaging'] })")

        try assertTrue("permissionsResult === true")
        try assertTrue("permissionsLog.removed.length === 1 && permissionsLog.removed[0] === 'nativeMessaging'")
    }

    func testWhenTheHostFailsForAnotherReason_ThenTheErrorIsPassedThrough() throws {
        try installFakePermissions()
        context.evaluateScript("""
        chrome.permissions.contains = function() { return Promise.reject(new Error('Network unreachable')); };
        """)
        try assertNoExceptions()
        try evaluateStubScript()

        context.evaluateScript("""
        var permissionsError = 'pending';
        chrome.permissions.contains({ permissions: ['downloads'] }).then(function() {
            permissionsError = 'unexpectedly resolved';
        }, function(error) {
            permissionsError = String(error && error.message);
        });
        """)
        try assertNoExceptions()

        try assertTrue("permissionsError === 'Network unreachable'")
    }

    func testWhenTheHostThrowsSynchronously_ThenContainsStillResolvesFalse() throws {
        try installFakePermissions()
        context.evaluateScript("""
        chrome.permissions.contains = function(descriptor) {
            permissionsLog.contains.push(descriptor);
            throw invalidPermissionError('contains', 'downloads');
        };
        """)
        try assertNoExceptions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['downloads'] })")

        try assertTrue("permissionsResult === false")
    }

    func testWhenAPermissionIsUnknown_ThenItIsLoggedOnceHoweverOftenItIsAsked() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['downloads'] })")
        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['downloads'] })")
        try evaluatePermissionsCall("chrome.permissions.request({ permissions: ['downloads'] })")

        try assertTrue("consoleMessages.filter(function(message) { return message.indexOf(\"'downloads' permission\") !== -1; }).length === 1")
    }

    func testWhenPermissionsIsWrapped_ThenTheNamespaceEventsAndGetAllAreUntouched() throws {
        try installFakePermissions()
        try evaluateStubScript()

        try assertTrue("chrome.permissions === originalPermissions")
        try assertTrue("chrome.permissions.onAdded === originalPermissionsOnAdded")
        try assertTrue("chrome.permissions.onRemoved === originalPermissionsOnRemoved")
        try assertTrue("chrome.permissions.getAll === originalPermissionsGetAll")
        try assertTrue("globalThis.\(WebExtensionAPIStubScript.retentionPropertyName).indexOf(originalPermissions) !== -1")
        try assertTrue("consoleMessages[0].indexOf('wrapped: [permissions]') !== -1")
    }

    func testWhenScriptIsEvaluatedTwice_ThenPermissionsMethodsAreNotWrappedTwice() throws {
        try installFakePermissions()
        try evaluateStubScript()
        context.evaluateScript("var firstRunContains = chrome.permissions.contains;")
        try assertNoExceptions()

        try evaluateStubScript()

        try assertTrue("chrome.permissions.contains === firstRunContains")

        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['nativeMessaging'] })")

        try assertTrue("permissionsResult === true")
        try assertTrue("permissionsLog.contains.length === 1")
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

    func testWhenOffscreenAndPrivacyAreUsed_ThenNothingIsReported() throws {
        try installFakeReporting()
        try evaluateStubScript()

        context.evaluateScript("""
        chrome.offscreen.hasDocument();
        chrome.privacy.services.passwordSavingEnabled.get();
        """)
        try assertNoExceptions()

        try assertReports("[]")
    }

    func testWhenAPermissionIsUnknownToTheHost_ThenItIsReportedAsMissing() throws {
        try installFakePermissions()
        try installFakeReporting()
        try evaluateStubScript()

        try evaluatePermissionsCall("chrome.permissions.contains({ permissions: ['downloads'] })")
        try evaluatePermissionsCall("chrome.permissions.request({ permissions: ['downloads'] })")

        try assertReports("[{\"kind\":\"missing\",\"api\":\"permission:downloads\"}]")
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

    /// What the stub script stored under its reserved `storage.local` key.
    private func storedPrivacySettings(file: StaticString = #filePath, line: UInt = #line) throws -> [String: Bool] {
        let stored = try XCTUnwrap(storageLocalItems["__ddgPrivacySettings"], file: file, line: line)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(stored.utf8)) as? [String: Bool], file: file, line: line)
    }

    /// Turns the three settings off in Bitwarden's order and reads them back with its check, leaving
    /// the last `set` result in `setResult`, the combined check in `overridden`, and the password
    /// saving details in `passwordSaving`.
    private func disableBrowserPasswordManagerTheWayBitwardenDoes() throws {
        context.evaluateScript("""
        var setResult = 'pending';
        var overridden = 'pending';
        var passwordSaving = 'pending';
        (function() {
            var services = chrome.privacy.services;
            function isOverridden(details) {
                return details.levelOfControl === 'controlled_by_this_extension' && !details.value;
            }
            function read(setting) {
                return new Promise(function(resolve) {
                    setting.get({}, function(details) { resolve(details); });
                });
            }
            services.autofillAddressEnabled.set({ value: false }).then(function() {
                return services.autofillCreditCardEnabled.set({ value: false });
            }).then(function() {
                return services.passwordSavingEnabled.set({ value: false });
            }).then(function(result) {
                setResult = result;
                return Promise.all([
                    read(services.passwordSavingEnabled),
                    read(services.autofillAddressEnabled),
                    read(services.autofillCreditCardEnabled)
                ]);
            }).then(function(details) {
                passwordSaving = details[0];
                overridden = details.every(isOverridden);
            });
        })();
        """)
        try assertNoExceptions()
        try assertTrue("overridden !== 'pending'")
    }

    /// `JSContext` has no DOM, no timers and no `URL`, so the offscreen stub gets the minimum it
    /// touches: a document that records the elements it hands out, a background page URL to resolve
    /// against, a minimal `URL` to resolve it with, and a `setTimeout` that parks its callback for
    /// the test to fire.
    private func installFakeDocument() throws {
        let scheduleTimer: @convention(block) (JSValue, Double) -> Int = { [weak self] callback, delay in
            self?.scheduledTimers.append(ScheduledTimer(callback: callback, delay: delay))
            return self?.scheduledTimers.count ?? 0
        }
        context.setObject(scheduleTimer, forKeyedSubscript: "setTimeout" as NSString)

        context.evaluateScript("""
        \(JSContextTestPolyfills.url)

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

    /// Adds the namespaces WebKit implements without their constants, the way a background page sees
    /// them: `scripting.executeScript` exists and takes the string a constant would have spelled out.
    private func installFakeConstantNamespaces() throws {
        context.evaluateScript("""
        chrome.scripting = { executeScript: function() {} };
        chrome.windows = {};
        var originalScripting = chrome.scripting;
        var originalExecuteScript = chrome.scripting.executeScript;
        var originalWindows = chrome.windows;
        """)
        try assertNoExceptions()
    }

    /// Mirrors WebKit's `chrome.permissions`: it answers for the permissions it implements and
    /// rejects the whole call with its validation error as soon as one name is not among them.
    /// `nativeMessaging` is granted, `tabs` is implemented but not granted, `privacy` and `idle` are
    /// unknown — the stub script answers for those itself, so `downloads` stands in for a truly unknown name.
    private func installFakePermissions() throws {
        context.evaluateScript("""
        var unknownPermissions = ['privacy', 'idle', 'offscreen', 'downloads'];
        var grantedPermissions = ['nativeMessaging'];
        var permissionsLog = { contains: [], request: [], remove: [], removed: [] };

        function requestedNames(descriptor) {
            return descriptor && descriptor.permissions ? descriptor.permissions : [];
        }
        function firstUnknownName(descriptor) {
            var names = requestedNames(descriptor);
            for (var index = 0; index < names.length; index++) {
                if (unknownPermissions.indexOf(names[index]) !== -1) {
                    return names[index];
                }
            }
            return null;
        }
        function invalidPermissionError(methodName, name) {
            return new Error("Invalid call to permissions." + methodName + "(). The 'permissions' value is invalid, because '"
                + name + "' is not a valid permission.");
        }

        chrome.permissions = {
            onAdded: { addListener: function() {} },
            onRemoved: { addListener: function() {} },
            getAll: function() {
                return Promise.resolve({ permissions: grantedPermissions.slice(), origins: [] });
            },
            contains: function(descriptor) {
                permissionsLog.contains.push(descriptor);
                var unknown = firstUnknownName(descriptor);
                if (unknown !== null) {
                    return Promise.reject(invalidPermissionError('contains', unknown));
                }
                return Promise.resolve(requestedNames(descriptor).every(function(name) {
                    return grantedPermissions.indexOf(name) !== -1;
                }));
            },
            request: function(descriptor) {
                permissionsLog.request.push(descriptor);
                var unknown = firstUnknownName(descriptor);
                if (unknown !== null) {
                    return Promise.reject(invalidPermissionError('request', unknown));
                }
                requestedNames(descriptor).forEach(function(name) {
                    if (grantedPermissions.indexOf(name) === -1) {
                        grantedPermissions.push(name);
                    }
                });
                return Promise.resolve(true);
            },
            remove: function(descriptor) {
                permissionsLog.remove.push(descriptor);
                var unknown = firstUnknownName(descriptor);
                if (unknown !== null) {
                    return Promise.reject(invalidPermissionError('remove', unknown));
                }
                requestedNames(descriptor).forEach(function(name) {
                    var index = grantedPermissions.indexOf(name);
                    if (index !== -1) {
                        grantedPermissions.splice(index, 1);
                    }
                    permissionsLog.removed.push(name);
                });
                return Promise.resolve(true);
            }
        };

        var originalPermissions = chrome.permissions;
        var originalPermissionsOnAdded = chrome.permissions.onAdded;
        var originalPermissionsOnRemoved = chrome.permissions.onRemoved;
        var originalPermissionsGetAll = chrome.permissions.getAll;
        """)
        try assertNoExceptions()
    }

    /// Runs a `chrome.permissions` call and leaves its settled value in `permissionsResult`.
    private func evaluatePermissionsCall(_ script: String, file: StaticString = #filePath, line: UInt = #line) throws {
        context.evaluateScript("""
        var permissionsResult = 'pending';
        (\(script)).then(function(result) { permissionsResult = result; });
        """)
        try assertNoExceptions(file: file, line: line)
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

    /// A page whose host answers `chrome.idle.queryState` through the idle message handler: it
    /// resolves with `idleReply` (read at call time, so a test can change it) or rejects, and
    /// `idleRequests` collects what the script posted.
    private func installFakeIdleHandler(reply: String, fails: Bool = false) throws {
        context.evaluateScript("""
        var idleRequests = [];
        var idleReply = "\(reply)";
        var webkit = { messageHandlers: {
            "\(WebExtensionAPIStubScript.idleMessageHandlerName)": {
                postMessage: function(payload) {
                    idleRequests.push(payload);
                    return \(fails ? "Promise.reject(new Error('nope'))" : "Promise.resolve(idleReply)");
                }
            }
        } };
        """)
        try assertNoExceptions()
    }

    /// `setInterval` and `clearInterval` that park the poll for the test to fire.
    private func installFakeIntervals() throws {
        let scheduleInterval: @convention(block) (JSValue, Double) -> Int = { [weak self] callback, delay in
            self?.scheduledIntervals.append(ScheduledTimer(callback: callback, delay: delay))
            return self?.scheduledIntervals.count ?? 0
        }
        let clearInterval: @convention(block) (JSValue) -> Void = { [weak self] _ in
            self?.context.evaluateScript("clearedIntervals.push(true);")
        }
        context.setObject(scheduleInterval, forKeyedSubscript: "setInterval" as NSString)
        context.setObject(clearInterval, forKeyedSubscript: "clearInterval" as NSString)
        context.evaluateScript("var clearedIntervals = [];")
        try assertNoExceptions()
    }

    private func firePolls() {
        scheduledIntervals.forEach { $0.callback.call(withArguments: []) }
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
