//
//  AIChatBrowserToolsBridgeTests.swift
//  DuckDuckGo
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

import AIChat
import Core
import FeatureFlags_iOS
import JavaScriptCore
import Persistence
import UserScript
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatBrowserToolsBridgeTests: XCTestCase {
    private func makeFixture(fire: Bool = false, enabledFlags: [FeatureFlag] = [.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs]) -> BrowserToolsBridgeFixture {
        let fixture = BrowserToolsBridgeFixture(fire: fire, enabledFlags: enabledFlags)
        addTeardownBlock { @MainActor in fixture.cleanUp() }
        return fixture
    }

    private func publish(_ flags: [FeatureFlag], in fixture: BrowserToolsBridgeFixture) async {
        fixture.flags.enabledFeatureFlags = flags
        fixture.flags.triggerUpdate()
        await drainBridge()
    }

    private func drainBridge() async {
        let drained = expectation(description: "Feature update and broker delivery drained")
        Task { @MainActor in
            DispatchQueue.main.async { drained.fulfill() }
        }
        await fulfillment(of: [drained], timeout: 2)
    }

    private func assertEnabledConfiguration(_ payload: [String: Any]?, file: StaticString = #filePath, line: UInt = #line) throws {
        let payload = try XCTUnwrap(payload, file: file, line: line)
        let configuration = try XCTUnwrap(payload["clientTools"] as? [String: Any], file: file, line: line)
        let data = try JSONSerialization.data(withJSONObject: configuration)
        XCTAssertEqual(try JSONDecoder().decode(ClientToolsConfiguration.self, from: data).capabilities,
                       [.listOpenTabs], file: file, line: line)
    }

    func testConfigurationUpdatesDeduplicateEffectiveFlagsAndEncodeExplicitNull() async throws {
        let fixture = makeFixture()
        _ = fixture.script
        await publish([.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs], in: fixture)
        XCTAssertTrue(fixture.webView.configurationPayloads.isEmpty)
        await publish([.aiChatBrowserToolListOpenTabs], in: fixture)
        XCTAssertEqual(fixture.webView.configurationPayloads.count, 1)
        XCTAssertTrue(fixture.webView.configurationPayloads.last?["clientTools"] is NSNull)
        await publish([], in: fixture)
        XCTAssertEqual(fixture.webView.configurationPayloads.count, 1)
        await publish([.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs], in: fixture)
        XCTAssertEqual(fixture.webView.configurationPayloads.count, 2)
        try assertEnabledConfiguration(fixture.webView.configurationPayloads.last)
        await publish([.aiChatBrowserTools], in: fixture)
        XCTAssertEqual(fixture.webView.configurationPayloads.count, 3)
        XCTAssertTrue(fixture.webView.configurationPayloads.last?["clientTools"] is NSNull)
        await publish([.aiChatBrowserTools], in: fixture)
        XCTAssertEqual(fixture.webView.configurationPayloads.count, 3)
    }

    func testInitiallyDisabledToolCanEnableForFullAndContextualChat() async throws {
        for contextual in [false, true] {
            let fixture = makeFixture(enabledFlags: [.aiChatBrowserTools])
            fixture.script.setDisplayMode(contextual ? .contextual : .fullTab)
            await publish([.aiChatBrowserTools], in: fixture)
            XCTAssertTrue(fixture.webView.configurationPayloads.isEmpty)
            await publish([.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs], in: fixture)
            XCTAssertEqual(fixture.webView.configurationPayloads.count, 1)
            try assertEnabledConfiguration(fixture.webView.configurationPayloads.last)
        }
    }

    func testConfigurationUpdatesRejectUntrustedMissingAndHomepageDocuments() async {
        for url in [nil, URL(string: "https://untrusted.example/chat"), URL(string: "https://duckduckgo.com/")] {
            let fixture = makeFixture()
            _ = fixture.script
            fixture.webView.documentURL = url
            await publish([], in: fixture)
            XCTAssertTrue(fixture.webView.configurationPayloads.isEmpty)
            XCTAssertFalse(fixture.script.pushClientToolsChanged(ClientToolsChangedData(clientTools: nil)))
        }
    }

    func testConfigurationUpdatesHonorCustomDocumentPolicy() async {
        let fixture = makeFixture()
        let settings = AIChatDebugSettings(userDefault: fixture.defaults)
        settings.customURL = "https://dev.example/start"
        settings.messagePolicyHostname = "dev.example:8443"
        let source = fixture.makeScript()
        fixture.webView.documentURL = URL(string: "https://dev.example:8443/chat")
        await publish([], in: fixture)
        XCTAssertEqual(fixture.webView.configurationPayloads.count, 1)
        XCTAssertTrue(fixture.webView.configurationPayloads.last?["clientTools"] is NSNull)
        fixture.webView.documentURL = URL(string: "https://dev.example:9443/chat")
        await publish([.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs], in: fixture)
        XCTAssertEqual(fixture.webView.configurationPayloads.count, 1)
        XCTAssertFalse(source.pushClientToolsChanged(ClientToolsChangedData(clientTools: nil)))
    }

    func testConfigurationUpdatesRejectFireOwnerRemovedOwnerAndProcessLoss() async {
        let fire = makeFixture(fire: true)
        _ = fire.script
        await publish([], in: fire)
        XCTAssertTrue(fire.webView.configurationPayloads.isEmpty)
        let removed = makeFixture()
        _ = removed.script
        removed.ownerPresent = false
        await publish([], in: removed)
        XCTAssertTrue(removed.webView.configurationPayloads.isEmpty)
        let terminated = makeFixture()
        terminated.script.browserToolsDocumentProcessDidTerminate()
        await publish([], in: terminated)
        XCTAssertTrue(terminated.webView.configurationPayloads.isEmpty)
        terminated.script.browserToolsDocumentDidCommit()
        await publish([.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs], in: terminated)
        XCTAssertEqual(terminated.webView.configurationPayloads.count, 1)
    }

    func testConfigurationUpdatesRejectCleanedUpAndReleasedSourcesButReachReplacement() async throws {
        let fixture = makeFixture()
        let stale = fixture.script
        stale.cleanUpForReplacement()
        stale.webView = fixture.webView
        stale.broker = fixture.broker
        var released: AIChatUserScript? = fixture.makeScript()
        weak var weakSource = released
        released = nil
        XCTAssertNil(weakSource)
        await publish([], in: fixture)
        XCTAssertTrue(fixture.webView.configurationPayloads.isEmpty)
        XCTAssertFalse(stale.pushClientToolsChanged(ClientToolsChangedData(clientTools: nil)))
        let replacement = fixture.makeScript()
        await publish([.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs], in: fixture)
        XCTAssertEqual(fixture.webView.configurationPayloads.count, 1)
        try assertEnabledConfiguration(fixture.webView.configurationPayloads.last)
        replacement.detachBrowserTools()
        replacement.browserToolsService = fixture.service
        XCTAssertFalse(replacement.pushClientToolsChanged(ClientToolsChangedData(clientTools: nil)))
        await publish([], in: fixture)
        XCTAssertEqual(fixture.webView.configurationPayloads.count, 1)
    }

    func testConfigurationRevocationWaitsForFinalOverlappingClearingToken() async {
        let fixture = makeFixture()
        _ = fixture.script
        let first = fixture.service.beginClearing(.owner(tabID: fixture.owner.uid))
        let second = fixture.service.beginClearing(.chats(ids: ["chat"]))
        await publish([], in: fixture)
        XCTAssertTrue(fixture.webView.configurationPayloads.isEmpty)
        fixture.service.endClearing(first)
        await drainBridge()
        XCTAssertTrue(fixture.webView.configurationPayloads.isEmpty)
        fixture.service.didClear(second)
        fixture.service.endClearing(second)
        await drainBridge()
        XCTAssertEqual(fixture.webView.configurationPayloads.count, 1)
        XCTAssertTrue(fixture.webView.configurationPayloads.last?["clientTools"] is NSNull)
        await publish([], in: fixture)
        XCTAssertEqual(fixture.webView.configurationPayloads.count, 1)
    }

    func testConfigurationRefreshCoalescesLatestValueDuringClearing() async throws {
        let fixture = makeFixture()
        _ = fixture.script
        let token = fixture.service.beginClearing(.all)
        await publish([], in: fixture)
        await publish([.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs], in: fixture)
        await publish([.aiChatBrowserTools], in: fixture)
        await publish([.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs], in: fixture)
        XCTAssertTrue(fixture.webView.configurationPayloads.isEmpty)
        fixture.service.endClearing(token)
        await drainBridge()
        XCTAssertEqual(fixture.webView.configurationPayloads.count, 1)
        try assertEnabledConfiguration(fixture.webView.configurationPayloads.last)
    }

    func testConfigurationPushRequiresBrokerAndSourceBindingEvenWhenDisabled() async {
        let fixture = makeFixture()
        let source = fixture.script
        source.broker = nil
        await publish([], in: fixture)
        XCTAssertFalse(source.pushClientToolsChanged(ClientToolsChangedData(clientTools: nil)))
        XCTAssertTrue(fixture.webView.configurationPayloads.isEmpty)
        source.broker = fixture.broker
        XCTAssertTrue(source.pushClientToolsChanged(ClientToolsChangedData(clientTools: nil)))
        await drainBridge()
        XCTAssertTrue(fixture.webView.configurationPayloads.last?["clientTools"] is NSNull)
        let foreign = AIChatUserScript(handler: fixture.handler, debugSettings: AIChatDebugSettings(userDefault: fixture.defaults))
        foreign.webView = fixture.webView
        foreign.broker = fixture.broker
        foreign.browserToolsService = fixture.service
        XCTAssertFalse(foreign.pushClientToolsChanged(ClientToolsChangedData(clientTools: nil)))
    }

    func testPendingConfigurationRechecksOwnerAndDocumentAfterClearing() async {
        for removeOwner in [false, true] {
            let fixture = makeFixture()
            _ = fixture.script
            let token = fixture.service.beginClearing(.all)
            await publish([], in: fixture)
            if removeOwner {
                fixture.ownerPresent = false
            } else {
                fixture.webView.documentURL = URL(string: "https://untrusted.example/chat")
            }
            fixture.service.endClearing(token)
            await drainBridge()
            XCTAssertTrue(fixture.webView.configurationPayloads.isEmpty)
        }
    }

    func testPendingConfigurationIsDiscardedOnCommitProcessLossAndDetach() async {
        for transition in ["commit", "processLoss", "detach"] {
            let fixture = makeFixture()
            _ = fixture.script
            let token = fixture.service.beginClearing(.all)
            await publish([], in: fixture)
            switch transition {
            case "commit": fixture.script.browserToolsDocumentDidCommit()
            case "processLoss": fixture.script.browserToolsDocumentProcessDidTerminate()
            default: fixture.script.detachBrowserTools()
            }
            fixture.service.endClearing(token)
            await drainBridge()
            XCTAssertTrue(fixture.webView.configurationPayloads.isEmpty, transition)
        }
    }

    func testHandlerParsesBeforeMissingSourceAndPreservesInvalidIdentifierEcho() async {
        let fixture = makeFixture()
        for identifier in ["readable", String(repeating: "é", count: 64), String(repeating: "é", count: 65)] {
            let result = await fixture.handler.executeClientTool(params: ["callId": identifier], source: nil)
            XCTAssertEqual(result, .failure(callId: identifier.utf8.count <= 128 ? identifier : "", error: .invalidArguments))
        }
        let unavailable = await fixture.handler.executeClientTool(params: fixture.params(), source: nil)
        XCTAssertEqual(unavailable, .failure(callId: "call", error: .unavailable))
    }

    func testConfigurationRoutePreservesExistingFieldsForUntrustedOrHomepageSource() async throws {
        let fixture = makeFixture()
        let message = WKScriptMessage()
        let original = try XCTUnwrap(fixture.handler.getAIChatNativeConfigValues(params: [:], message: message) as? AIChatNativeConfigValues)
        let route = try XCTUnwrap(fixture.script.handler(forMethodNamed: "getAIChatNativeConfigValues"))
        fixture.webView.documentURL = URL(string: "https://duckduckgo.com/")
        let routed = try await route([:], message)
        let response = try XCTUnwrap(routed as? AIChatNativeConfigValues)
        XCTAssertNil(response.clientTools)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(response)) as? [String: Any])
        XCTAssertEqual(encoded["supportsBrowserTools"] as? Bool, false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(response), try encoder.encode(original))
    }

    func testConfigurationRouteReturnsHandlerResponseUnchangedWhenToolsAreDisabledOrUnbound() async throws {
        let fixture = makeFixture()
        var original = AIChatNativeConfigValues.defaultValues
        original.clientTools = try ClientToolsConfiguration(capabilities: [.listOpenTabs])
        let handler = MockAIChatUserScriptHandling()
        handler.nativeConfigResponse = original
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for bound in [true, false] {
            fixture.flags.enabledFeatureFlags = bound ? [.aiChatBrowserToolListOpenTabs] : [.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs]
            let source = AIChatUserScript(handler: handler, debugSettings: AIChatDebugSettings(userDefault: fixture.defaults))
            source.browserToolsService = bound ? fixture.service : nil
            let route = try XCTUnwrap(source.handler(forMethodNamed: "getAIChatNativeConfigValues"))
            let routed = try await route([:], WKScriptMessage())
            let response = try XCTUnwrap(routed as? AIChatNativeConfigValues)
            XCTAssertEqual(try encoder.encode(response), try encoder.encode(original))
        }
    }

    func testConfigurationRouteStillReturnsHandlerResponseAfterSourceRelease() async throws {
        let fixture = makeFixture()
        var source: AIChatUserScript? = fixture.makeScript()
        weak var releasedSource = source
        let route = try XCTUnwrap(source?.handler(forMethodNamed: "getAIChatNativeConfigValues"))
        source?.detachBrowserTools()
        source = nil
        XCTAssertNil(releasedSource)
        let message = WKScriptMessage()
        let original = try XCTUnwrap(fixture.handler.getAIChatNativeConfigValues(params: [:], message: message) as? AIChatNativeConfigValues)
        let routed = try await route([:], message)
        let response = try XCTUnwrap(routed as? AIChatNativeConfigValues)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(response), try encoder.encode(original))
    }

    func testRetainedRouteAfterSourceReleaseStillParsesValidRequestAsUnavailable() async throws {
        let fixture = makeFixture()
        var source: AIChatUserScript? = fixture.makeScript()
        let route = try XCTUnwrap(source?.handler(forMethodNamed: "executeClientTool"))
        source?.detachBrowserTools()
        source = nil
        let result = try await route(fixture.params(), WKScriptMessage()) as? ExecuteClientToolResponse
        XCTAssertEqual(result, .failure(callId: "call", error: .unavailable))
    }

    func testActualScriptRoutesRejectUntrustedWebKitMessageBeforePermission() async throws {
        let fixture = makeFixture()
        let route = try XCTUnwrap(fixture.script.handler(forMethodNamed: "executeClientTool"))
        let result = try await route(fixture.params(), WKScriptMessage()) as? ExecuteClientToolResponse
        XCTAssertEqual(result, .failure(callId: "call", error: .unavailable))
        let malformed = try await route(["callId": "echo"], WKScriptMessage()) as? ExecuteClientToolResponse
        XCTAssertEqual(malformed, .failure(callId: "echo", error: .invalidArguments))
        XCTAssertTrue(fixture.webView.permissionPrompts.isEmpty)
        XCTAssertEqual(fixture.listings, 0)
    }

    func testOriginRequiresActualCurrentSchemeHostAndEffectivePort() {
        let document = URL(string: "https://dev.example:8443/chat")!
        XCTAssertTrue(AIChatUserScript.browserToolsOriginMatches(scheme: "https", host: "dev.example", port: 8443, document: document))
        XCTAssertFalse(AIChatUserScript.browserToolsOriginMatches(scheme: "https", host: "dev.example", port: 443, document: document))
        XCTAssertFalse(AIChatUserScript.browserToolsOriginMatches(scheme: "http", host: "dev.example", port: 8443, document: document))
        XCTAssertFalse(AIChatUserScript.browserToolsOriginMatches(scheme: "https", host: "other.example", port: 8443, document: document))
        XCTAssertTrue(AIChatUserScript.browserToolsOriginMatches(
            scheme: "https", host: "duck.ai", port: 0, document: URL(string: "https://duck.ai/chat")!))
    }

    func testMessageBoundaryRejectsForeignViewSubframeAndHomepage() {
        let fixture = makeFixture()
        var message = BrowserToolsBoundaryMessage(webView: fixture.webView)
        XCTAssertTrue(fixture.script.acceptsBrowserToolsMessage(message, senderScheme: "https", senderHost: "duck.ai", senderPort: 443))
        message.mainFrame = false
        XCTAssertFalse(fixture.script.acceptsBrowserToolsMessage(message, senderScheme: "https", senderHost: "duck.ai", senderPort: 443))
        message.mainFrame = true
        message.webView = WKWebView()
        XCTAssertFalse(fixture.script.acceptsBrowserToolsMessage(message, senderScheme: "https", senderHost: "duck.ai", senderPort: 443))
        message.webView = fixture.webView
        fixture.webView.documentURL = URL(string: "https://duckduckgo.com/")
        XCTAssertFalse(fixture.script.acceptsBrowserToolsMessage(message, senderScheme: "https", senderHost: "duck.ai", senderPort: 443))
    }

    func testCustomDocumentPreservesMatcherPortSemanticsAndBrokerPolicy() {
        let fixture = makeFixture()
        let settings = AIChatDebugSettings(userDefault: fixture.defaults)
        settings.customURL = "https://dev.example/start"
        settings.messagePolicyHostname = "dev.example:8443"
        let script = fixture.makeScript()
        fixture.webView.documentURL = URL(string: "https://dev.example:8443/chat")
        let message = BrowserToolsBoundaryMessage(webView: fixture.webView, host: "dev.example:8443")
        XCTAssertNotNil(fixture.service.configuration(for: script))
        XCTAssertTrue(script.acceptsBrowserToolsMessage(message, senderScheme: "https", senderHost: "dev.example", senderPort: 8443))
        XCTAssertFalse(script.acceptsBrowserToolsMessage(message, senderScheme: "https", senderHost: "dev.example", senderPort: 443))
        fixture.webView.documentURL = URL(string: "https://other.example:8443/chat")
        XCTAssertNil(fixture.service.configuration(for: script))
    }

    func testBindingBeforeOwnerMembershipResolvesAfterInsertionButCleanupCannotRebind() async {
        let fixture = makeFixture()
        fixture.ownerPresent = false
        let source = fixture.script
        XCTAssertNil(fixture.service.configuration(for: source))
        fixture.ownerPresent = true
        XCTAssertNotNil(fixture.service.configuration(for: source))
        fixture.service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        let inserted = await fixture.invoke()
        XCTAssertEqual(inserted, fixture.success)
        source.cleanUpForReplacement()
        source.webView = fixture.webView
        let stale = await fixture.invoke()
        XCTAssertEqual(stale, .failure(callId: "call", error: .unavailable))
    }

    func testDiscoveryRequiresCurrentChatAndBothDynamicFlags() {
        let fixture = makeFixture()
        XCTAssertEqual(fixture.service.configuration(for: fixture.script)?.capabilities, [.listOpenTabs])
        fixture.webView.documentURL = URL(string: "https://duckduckgo.com/")
        XCTAssertNil(fixture.service.configuration(for: fixture.script))
        fixture.webView.documentURL = URL(string: "https://untrusted.example/chat")
        XCTAssertNil(fixture.service.configuration(for: fixture.script))
        fixture.webView.documentURL = URL(string: "https://duck.ai/chat")
        fixture.flags.enabledFeatureFlags = [.aiChatBrowserTools]
        XCTAssertNil(fixture.service.configuration(for: fixture.script))
        XCTAssertTrue(fixture.service.canPushMetadata(from: fixture.script))
        fixture.flags.enabledFeatureFlags = [.aiChatBrowserToolListOpenTabs]
        XCTAssertNil(fixture.service.configuration(for: fixture.script))
        XCTAssertFalse(fixture.service.canPushMetadata(from: fixture.script))
    }

    func testRealPermissionPushAndHandlerResponseReturnOriginalExecutionResult() async throws {
        let fixture = makeFixture()
        let delivered = expectation(description: "Permission delivered through broker")
        fixture.webView.onPermission = { params in
            XCTAssertEqual(params["callId"] as? String, "call")
            XCTAssertEqual(params["choices"] as? [String], ["allow", "always", "never"])
            let reply = fixture.handler.respondToClientToolPermission(
                params: fixture.response(params, decision: "allow"), source: fixture.script)
            XCTAssertEqual(try? JSONEncoder().encode(reply), Data("{}".utf8))
            delivered.fulfill()
        }
        let result = await fixture.invoke()
        await fulfillment(of: [delivered], timeout: 2)
        XCTAssertEqual(result, fixture.success)
        XCTAssertEqual(fixture.listings, 1)
        XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "listOpenTabs"), .ask)
    }

    func testAllowThenCleanupBeforeAdmissionDoesNotListOrReviveOldSource() async {
        let fixture = makeFixture()
        fixture.webView.onPermission = { params in
            _ = fixture.handler.respondToClientToolPermission(params: fixture.response(params, decision: "allow"), source: fixture.script)
            fixture.script.cleanUpForReplacement()
        }
        let result = await fixture.invoke()
        XCTAssertEqual(result, .failure(callId: "call", error: .cancelled))
        XCTAssertEqual(fixture.listings, 0)
        fixture.script.webView = fixture.webView
        let stale = await fixture.invoke()
        XCTAssertEqual(stale, .failure(callId: "call", error: .unavailable))
        let replacement = fixture.makeScript()
        fixture.service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        let renewed = await fixture.handler.executeClientTool(params: fixture.params(), source: replacement)
        XCTAssertEqual(renewed, fixture.success)
    }

    func testDisabledFlagsRejectAlwaysAndNeverWithoutWritingOrListing() async {
        for decision in ["always", "never"] {
            let states: [[FeatureFlag]] = [[.aiChatBrowserTools], [.aiChatBrowserToolListOpenTabs]]
            for enabled in states {
                let fixture = makeFixture()
                fixture.webView.onPermission = { params in
                    fixture.flags.enabledFeatureFlags = enabled
                    _ = fixture.handler.respondToClientToolPermission(
                        params: fixture.response(params, decision: decision), source: fixture.script)
                    fixture.script.detachBrowserTools()
                }
                let result = await fixture.invoke()
                XCTAssertEqual(result, .failure(callId: "call", error: .cancelled))
                XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "listOpenTabs"), .ask)
                XCTAssertEqual(fixture.listings, 0)
            }
        }
    }

    func testMalformedAndUnmatchedResponsesAcknowledgeWithoutWritingThenOriginalCallCanFinish() async {
        let fixture = makeFixture()
        fixture.webView.onPermission = { params in
            let malformed: [[String: Any]] = [[:], ["callId": "call", "requestId": 1, "decision": "always"],
                                              ["callId": "other", "requestId": params["requestId"] ?? "", "decision": "always"],
                                              ["callId": "call", "requestId": "unmatched", "decision": "never"]]
            for response in malformed {
                let reply = fixture.handler.respondToClientToolPermission(params: response, source: fixture.script)
                XCTAssertEqual(try? JSONEncoder().encode(reply), Data("{}".utf8))
                XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "listOpenTabs"), .ask)
                XCTAssertEqual(fixture.listings, 0)
            }
            _ = fixture.handler.respondToClientToolPermission(params: fixture.response(params, decision: "allow"), source: fixture.script)
        }
        let result = await fixture.invoke()
        XCTAssertEqual(result, fixture.success)
        XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "listOpenTabs"), .ask)
    }

    func testOwnerRemovalCancelsPendingAndRejectsLatePersistentDecision() async {
        let fixture = makeFixture()
        fixture.webView.onPermission = { params in
            fixture.service.detachSources(ownerTabID: fixture.owner.uid)
            _ = fixture.handler.respondToClientToolPermission(params: fixture.response(params, decision: "always"), source: fixture.script)
        }
        let result = await fixture.invoke()
        XCTAssertEqual(result, .failure(callId: "call", error: .cancelled))
        XCTAssertEqual(fixture.listings, 0)
        XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "listOpenTabs"), .ask)
    }

    func testCommitAndProcessLossCancelOnlyLocalSourceAndRequireRealCommit() async {
        let fixture = makeFixture()
        let contextual = fixture.makeScript()
        fixture.service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        fixture.script.browserToolsDocumentProcessDidTerminate()
        let lost = await fixture.invoke()
        XCTAssertEqual(lost, .failure(callId: "call", error: .unavailable))
        let actual1 = await fixture.handler.executeClientTool(params: fixture.params(), source: contextual)
        XCTAssertEqual(actual1, fixture.success)
        fixture.script.browserToolsDocumentDidCommit()
        let actual2 = await fixture.invoke()
        XCTAssertEqual(actual2, fixture.success)
        fixture.script.browserToolsDocumentDidCommit()
        let actual3 = await fixture.invoke()
        XCTAssertEqual(actual3, fixture.success)
    }

    func testCommittedDocumentCancelsPendingButAnotherSourceSameOwnerStillWorks() async {
        let fixture = makeFixture()
        let contextual = fixture.makeScript()
        fixture.webView.onPermission = { _ in fixture.script.browserToolsDocumentDidCommit() }
        let cancelled = await fixture.invoke()
        XCTAssertEqual(cancelled, .failure(callId: "call", error: .cancelled))
        XCTAssertEqual(fixture.listings, 0)
        fixture.service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        let actual4 = await fixture.handler.executeClientTool(params: fixture.params(), source: contextual)
        XCTAssertEqual(actual4, fixture.success)
        let actual5 = await fixture.invoke()
        XCTAssertEqual(actual5, fixture.success)
    }

    func testStoredAllowStillHonorsFireOwnerAndProcessLoss() async {
        let fixture = makeFixture()
        fixture.service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        let first = fixture.service.beginClearing(.all)
        let second = fixture.service.beginClearing(.chats(ids: ["chat"]))
        XCTAssertNil(fixture.service.configuration(for: fixture.script))
        let actual6 = await fixture.invoke()
        XCTAssertEqual(actual6, .failure(callId: "call", error: .unavailable))
        fixture.service.endClearing(first)
        let actual7 = await fixture.invoke()
        XCTAssertEqual(actual7, .failure(callId: "call", error: .unavailable))
        fixture.service.endClearing(second)
        let actual8 = await fixture.invoke()
        XCTAssertEqual(actual8, fixture.success)
        fixture.ownerPresent = false
        let actual9 = await fixture.invoke()
        XCTAssertEqual(actual9, .failure(callId: "call", error: .unavailable))
        XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "listOpenTabs"), .allow)
    }

    func testFireCancelsGrantedBeforeExecutionAndFailureAllowsFreshRequest() async {
        let fixture = makeFixture()
        fixture.webView.onPermission = { params in
            _ = fixture.handler.respondToClientToolPermission(params: fixture.response(params, decision: "allow"), source: fixture.script)
            let token = fixture.service.beginClearing(.chats(ids: ["chat"]))
            _ = fixture.handler.respondToClientToolPermission(params: fixture.response(params, decision: "always"), source: fixture.script)
            fixture.service.endClearing(token)
        }
        let actual10 = await fixture.invoke()
        XCTAssertEqual(actual10, .failure(callId: "call", error: .cancelled))
        XCTAssertEqual(fixture.listings, 0)
        XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "listOpenTabs"), .ask)
        fixture.webView.onPermission = { params in
            _ = fixture.handler.respondToClientToolPermission(params: fixture.response(params, decision: "allow"), source: fixture.script)
        }
        let actual11 = await fixture.invoke()
        XCTAssertEqual(actual11, fixture.success)
    }

    func testFireOwnerCannotDiscoverInvokeOrPersistPermission() async {
        let fixture = makeFixture(fire: true)
        fixture.service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        XCTAssertNil(fixture.service.configuration(for: fixture.script))
        let actual12 = await fixture.invoke()
        XCTAssertEqual(actual12, .failure(callId: "call", error: .unavailable))
        XCTAssertEqual(fixture.listings, 0)
        XCTAssertTrue(fixture.webView.permissionPrompts.isEmpty)
    }

    func testContextualMetadataUsesOnlyMainFlagAndOwnerNavigationPreservesPermission() async {
        let fixture = makeFixture()
        fixture.script.setDisplayMode(.contextual)
        let metadata = expectation(description: "Owner navigation metadata delivered")
        fixture.webView.onTabChanged = { params in
            XCTAssertEqual(params["tabId"] as? String, "owner")
            XCTAssertEqual(params["change"] as? String, "navigated")
            XCTAssertEqual(params["url"] as? String, "https://next.example")
            XCTAssertNil(params["title"])
            metadata.fulfill()
        }
        fixture.webView.onPermission = { params in
            fixture.service.ownerDidNavigate(tabID: fixture.owner.uid, url: URL(string: "https://next.example"))
            _ = fixture.handler.respondToClientToolPermission(params: fixture.response(params, decision: "allow"), source: fixture.script)
        }
        let allowed = await fixture.invoke()
        XCTAssertEqual(allowed, fixture.success)
        await fulfillment(of: [metadata], timeout: 2)
        fixture.flags.enabledFeatureFlags = [.aiChatBrowserTools]
        let childDisabled = expectation(description: "Metadata independent of tool flag")
        let settings = AIChatDebugSettings(userDefault: fixture.defaults)
        settings.customURL = "https://dev.example/chat"
        fixture.webView.onTabChanged = { params in
            XCTAssertEqual(params["url"] as? String, "https://dev.example/chat")
            XCTAssertEqual(params["isAttachable"] as? Bool, false)
            childDisabled.fulfill()
        }
        fixture.service.ownerDidNavigate(tabID: fixture.owner.uid, url: URL(string: "https://dev.example/chat"))
        await fulfillment(of: [childDisabled], timeout: 2)
        fixture.flags.enabledFeatureFlags = []
        let deliveredCount = fixture.webView.metadataPayloads.count
        fixture.service.ownerDidNavigate(tabID: fixture.owner.uid, url: URL(string: "https://blocked.example"))
        let drained = expectation(description: "Queued bridge deliveries drained")
        DispatchQueue.main.async { drained.fulfill() }
        await fulfillment(of: [drained], timeout: 2)
        XCTAssertEqual(fixture.webView.metadataPayloads.count, deliveredCount)
    }

    func testPermissionPushRequiresBrokerAndTrustedLiveDocument() throws {
        let fixture = makeFixture()
        let prompt = try ClientToolPermissionRequested(requestId: "request", callId: "call", message: "Allow?", choices: [.allow])
        let oversized = try ClientToolPermissionRequested(
            requestId: "large", callId: "call", message: String(repeating: "\u{0000}", count: 4096), choices: [.allow])
        XCTAssertFalse(ClientToolPayloadLimits.fits(oversized, within: ClientToolPayloadLimits.permissionBytes))
        XCTAssertFalse(fixture.script.pushClientToolPermissionRequested(oversized))
        fixture.script.broker = nil
        XCTAssertFalse(fixture.script.pushClientToolPermissionRequested(prompt))
        fixture.script.broker = fixture.broker
        fixture.webView.documentURL = URL(string: "https://duckduckgo.com/")
        XCTAssertFalse(fixture.script.pushClientToolPermissionRequested(prompt))
        fixture.webView.documentURL = URL(string: "https://duck.ai/chat")
        fixture.script.browserToolsDocumentProcessDidTerminate()
        XCTAssertFalse(fixture.script.pushClientToolPermissionRequested(prompt))
    }
}

@MainActor
final class BrowserToolsBridgeFixture {
    let suiteName: String
    let defaults: UserDefaults
    let flags: MockFeatureFlagger
    let owner: Tab
    let service: AIChatBrowserToolsService
    let handler: AIChatUserScriptHandler
    let webView = BrowserToolsBridgeWebView()
    let broker = UserScriptMessageBroker(context: "aiChat", requiresRunInPageContentWorld: true)
    var ownerPresent = true
    var listings = 0
    lazy var script = makeScript()

    init(fire: Bool = false, enabledFlags: [FeatureFlag] = [.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs]) {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        let flags = MockFeatureFlagger(enabledFeatureFlags: enabledFlags)
        self.suiteName = suiteName
        self.defaults = defaults
        self.flags = flags
        owner = Tab(uid: "owner", link: Link(title: "Owner", url: URL(string: "https://owner.example")!), fireTab: fire)
        service = AIChatBrowserToolsService(featureFlagger: flags, permissionStorage: defaults.keyedStoring())
        handler = AIChatUserScriptHandler(experimentalAIChatManager: ExperimentalAIChatManager(featureFlagger: flags),
                                          syncHandler: MockAIChatSyncHandling(), featureFlagger: flags, keyValueStore: defaults)
    }

    func makeScript() -> AIChatUserScript {
        let script = AIChatUserScript(handler: handler, debugSettings: AIChatDebugSettings(userDefault: defaults))
        script.webView = webView
        script.broker = broker
        script.bindBrowserTools(to: service, owner: owner) { [weak self] in self?.makeScope() }
        return script
    }

    func makeScope() -> BrowserToolScope? {
        guard ownerPresent else { return nil }
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: owner.mode, tabsProvider: { [weak self] in
            guard let self, self.ownerPresent else { return [] }
            return [self.owner]
        })
        return BrowserToolScope(owner: owner, source: source, selectedTabID: { [weak self] in
            self?.listings += 1
            return self?.owner.uid
        })
    }

    func params() -> [String: Any] {
        ["callId": "call", "capability": ["name": "listOpenTabs", "version": 1], "input": [:]]
    }

    func response(_ prompt: [String: Any], decision: String) -> [String: Any] {
        ["requestId": prompt["requestId"] as? String ?? "", "callId": prompt["callId"] as? String ?? "", "decision": decision]
    }

    func invoke() async -> ExecuteClientToolResponse {
        await handler.executeClientTool(params: params(), source: script)
    }

    var success: ExecuteClientToolResponse {
        .success(callId: "call", value: ["tabs": [["tabId": "owner", "title": "Owner", "url": "https://owner.example",
                                                  "isCurrentTab": true, "isAttachable": true]]])
    }

    func cleanUp() {
        webView.onPermission = nil
        webView.onTabChanged = nil
        script.detachBrowserTools()
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@MainActor
final class BrowserToolsBridgeWebView: WKWebView {
    var documentURL: URL? = URL.duckAi.withChatID("chat")
    override var url: URL? { documentURL }
    var permissionPrompts: [[String: Any]] = []
    var configurationPayloads: [[String: Any]] = []
    var metadataPayloads: [[String: Any]] = []
    var onPermission: (([String: Any]) -> Void)?
    var onTabChanged: (([String: Any]) -> Void)?
    private let context = JSContext()!

    override func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, Error?) -> Void)? = nil) {
        context.evaluateScript("""
            var capturedPermission = null;
            var capturedMetadata = null;
            var capturedConfiguration = null;
            var navigator = { duckduckgo: { messageHandlers: {
                clientToolsChanged: function(event) { capturedConfiguration = event.params; },
                clientToolPermissionRequested: function(event) { capturedPermission = event.params; },
                aiChatTabChanged: function(event) { capturedMetadata = event.params; }
            } } };
            """)
        context.evaluateScript(javaScriptString)
        if let error = context.exception { XCTFail("Bridge JavaScript failed: \(error)") }
        if let params = context.objectForKeyedSubscript("capturedPermission")?.toDictionary() as? [String: Any] {
            permissionPrompts.append(params)
            onPermission?(params)
        }
        if let params = context.objectForKeyedSubscript("capturedMetadata")?.toDictionary() as? [String: Any] {
            metadataPayloads.append(params)
            onTabChanged?(params)
        }
        if let params = context.objectForKeyedSubscript("capturedConfiguration")?.toDictionary() as? [String: Any] {
            configurationPayloads.append(params)
        }
        completionHandler?(nil, nil)
    }
}

private struct BrowserToolsBoundaryMessage: UserScriptMessage {
    var webView: WKWebView?
    var host = "duck.ai"
    var mainFrame = true
    var messageName: String { "aiChat" }
    var messageBody: Any { [:] }
    var messageHost: String { host }
    var isMainFrame: Bool { mainFrame }
    var messageWebView: WKWebView? { webView }
}
