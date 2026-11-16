//
//  AIChatBrowserToolsServiceTests.swift
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

@testable import AIChat
import Core
import FeatureFlags_iOS
import Persistence
import PrivacyConfig
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatBrowserToolsServiceTests: XCTestCase {
    private func request(name: String = "listOpenTabs", version: Int = 1, input: JSONValue = [:]) throws -> ExecuteClientToolRequest {
        let value: JSONValue = ["callId": "call", "capability": ["name": .string(name), "version": .int(version)], "input": input]
        return try JSONDecoder().decode(ExecuteClientToolRequest.self, from: JSONEncoder().encode(value))
    }

#if DEBUG || ALPHA
    func testDebugSessionInvokesThroughSharedPermissionCoordinator() async throws {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        fixture.presenter.autoAnswer = .always
        let session = BrowserToolsDebugSession(service: fixture.service, scope: try XCTUnwrap(fixture.makeScope()),
                                               presenter: fixture.presenter, isNormalMode: { true })
        defer { session.close() }

        let result = await fixture.service.invoke(try request(), from: session)

        XCTAssertEqual(result, fixture.success)
        XCTAssertEqual(fixture.presenter.prompts.count, 1)
        XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "listOpenTabs"), .allow)
    }

    func testDebugSessionSwitchesTabWithoutPromptingOrChangingOwner() async throws {
        let fixture = BrowserToolsBridgeFixture(enabledFlags: [.aiChatBrowserTools, .aiChatBrowserToolSwitchToTab])
        defer { fixture.cleanUp() }
        let service = AIChatBrowserToolsService(featureFlagger: fixture.flags, permissionStorage: fixture.defaults.keyedStoring())
        let owner = fixture.owner
        let target = Tab(uid: "target", link: Link(title: "Target", url: URL(string: "https://example.com")!), fireTab: false)
        var selected = owner
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner, target] })
        let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { selected.uid }, selectTab: {
            selected = $0
            return true
        })
        fixture.presenter.autoAnswer = .never
        let session = BrowserToolsDebugSession(service: service, scope: scope, presenter: fixture.presenter, isNormalMode: { true })
        defer { session.close() }

        let result = await service.invoke(try request(name: "switchToTab", input: ["tabId": "target"]), from: session)

        XCTAssertEqual(result, .success(callId: "call", value: ["tabId": "target"]))
        XCTAssertTrue(selected === target)
        XCTAssertEqual(scope.ownerTabID, owner.uid)
        XCTAssertTrue(fixture.presenter.prompts.isEmpty)
        XCTAssertTrue(service.permissions.storedDecisions.isEmpty)
    }

    func testOwnerDetachRevokesDebugSessionWithoutWebBindings() async throws {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        let scope = try XCTUnwrap(fixture.makeScope())
        let session = BrowserToolsDebugSession(service: fixture.service, scope: scope,
                                               presenter: fixture.presenter, isNormalMode: { true })

        fixture.service.detachSources(ownerTabID: fixture.owner.uid)
        let result = await fixture.service.invoke(try request(), from: session)

        XCTAssertFalse(scope.isValid)
        XCTAssertEqual(result, .failure(callId: "call", error: .unavailable))
        XCTAssertTrue(fixture.presenter.prompts.isEmpty)
        XCTAssertEqual(fixture.listings, 0)
    }

    func testClearingRevokesDebugSessionAndFreshSessionWorksAfterward() async throws {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        let session = BrowserToolsDebugSession(service: fixture.service, scope: try XCTUnwrap(fixture.makeScope()),
                                               presenter: fixture.presenter, isNormalMode: { true })
        let token = fixture.service.beginClearing(.chats(ids: ["unrelated-chat"]))
        fixture.service.endClearing(token)

        let stale = await fixture.service.invoke(try request(), from: session)
        XCTAssertEqual(stale, .failure(callId: "call", error: .unavailable))
        let fresh = BrowserToolsDebugSession(service: fixture.service, scope: try XCTUnwrap(fixture.makeScope()),
                                             presenter: fixture.presenter, isNormalMode: { true })
        defer { fresh.close() }
        let result = await fixture.service.invoke(try request(), from: fresh)
        XCTAssertEqual(result, fixture.success)
    }

    func testInvalidatedDebugSessionCannotPersistPermissionDecision() async throws {
        for invalidation in 0..<5 {
            let fixture = BrowserToolsBridgeFixture()
            defer { fixture.cleanUp() }
            var normalMode = true
            let session = BrowserToolsDebugSession(service: fixture.service, scope: try XCTUnwrap(fixture.makeScope()),
                                                   presenter: fixture.presenter, isNormalMode: { normalMode })
            defer { session.close() }
            fixture.presenter.autoAnswer = .always
            defer { fixture.presenter.onPresent = nil }
            fixture.presenter.onPresent = {
                switch invalidation {
                case 0: normalMode = false
                case 1: fixture.ownerPresent = false
                case 2: fixture.flags.enabledFeatureFlags = []
                case 3: fixture.presenter.isAvailable = false
                default: session.close()
                }
            }

            let result = await fixture.service.invoke(try request(), from: session)

            XCTAssertEqual(result, .failure(callId: "call", error: .cancelled))
            XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "listOpenTabs"), .ask)
            XCTAssertEqual(fixture.listings, 0)
        }
    }
#endif

    func testExternalUserCanDiscoverAndInvokeToolsWhenAllFlagsAreEnabled() async {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        fixture.flags.internalUserDecider = MockInternalUserDecider(isInternalUser: false)
        fixture.flags.enabledFeatureFlags = [.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs, .aiChatBrowserToolSwitchToTab]
        fixture.service.permissions.setState(.allow, forToolNamed: "listOpenTabs")

        XCTAssertTrue(fixture.flags.isFeatureOn(.aiChatBrowserTools))
        XCTAssertTrue(ChatToBrowserToolCallingFeature(featureFlagger: fixture.flags).isAvailable)
        XCTAssertTrue(fixture.service.isEnabled)
        XCTAssertNotNil(fixture.service.clientToolsConfiguration)
        XCTAssertNotNil(fixture.service.configuration(for: fixture.script))
        XCTAssertEqual(fixture.service.catalog.enabledTools.map(\.name), ["listOpenTabs", "switchToTab"])

        let result = await fixture.invoke()

        XCTAssertEqual(result, fixture.success)
        XCTAssertEqual(fixture.listings, 1)
        XCTAssertTrue(fixture.webView.permissionPrompts.isEmpty)
    }

    func testInjectedScopeCannotBypassActiveFireBlock() async throws {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        let scope = try XCTUnwrap(fixture.makeScope())
        let service = AIChatBrowserToolsService(featureFlagger: fixture.flags, scopeProvider: { _ in scope },
                                                permissionStorage: fixture.defaults.keyedStoring(), capabilities: [.listOpenTabs])
        service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        let context = BrowserToolCallContext(ownerTabID: scope.ownerTabID, ownerWindowToken: scope.token,
                                             isBurner: false)
        let token = service.beginClearing(.all)
        let blocked = await service.invoker.invokeClientTool(try request(), context: context, permissionPrompter: nil)
        XCTAssertEqual(blocked, .failure(callId: "call", error: .unavailable))
        XCTAssertEqual(fixture.listings, 0)
        service.endClearing(token)
        let fresh = await service.invoker.invokeClientTool(try request(), context: context, permissionPrompter: nil)
        XCTAssertEqual(fresh, fixture.success)
        XCTAssertEqual(service.permissions.state(forToolNamed: "listOpenTabs"), .allow)
    }

    func testScopeLookupDoesNotCreateScopesForOtherChatsWithSameOrDifferentOwner() async throws {
        for sameOwner in [false, true] {
            let fixture = BrowserToolsBridgeFixture()
            defer { fixture.cleanUp() }
            _ = fixture.script
            let otherOwner = sameOwner ? fixture.owner : Tab(uid: "other-owner", fireTab: false)
            let otherScript = fixture.makeScript()
            defer { otherScript.detachBrowserTools() }
            var otherScopeCreations = 0
            otherScript.bindBrowserTools(to: fixture.service, owner: otherOwner) {
                otherScopeCreations += 1
                let source = MultiTabAttachmentSource(currentTabID: otherOwner.uid, mode: .normal, tabsProvider: { [otherOwner] })
                return BrowserToolScope(owner: otherOwner, source: source, selectedTabID: { otherOwner.uid })
            }
            otherScript.browserToolsDocumentDidCommit()
            otherScopeCreations = 0
            fixture.service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
            let unknownContext = BrowserToolCallContext(ownerTabID: fixture.owner.uid, ownerWindowToken: UUID().uuidString, isBurner: false)

            let rejected = await fixture.service.invoker.invokeClientTool(try request(), context: unknownContext, permissionPrompter: nil)

            XCTAssertEqual(rejected, .failure(callId: "call", error: .unavailable))
            XCTAssertEqual(otherScopeCreations, 0)
            let accepted = await fixture.invoke()
            XCTAssertEqual(accepted, fixture.success)
            XCTAssertEqual(otherScopeCreations, 0)
        }
    }

    func testStaleContextDoesNotCreateScopeForNewDocument() async throws {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        var scopeCreations = 0
        var createdScope: BrowserToolScope?
        fixture.script.bindBrowserTools(to: fixture.service, owner: fixture.owner, presenter: fixture.presenter) { [weak fixture] in
            scopeCreations += 1
            createdScope = fixture?.makeScope()
            return createdScope
        }
        let originalScope = try XCTUnwrap(createdScope)
        let staleContext = BrowserToolCallContext(ownerTabID: originalScope.ownerTabID, ownerWindowToken: originalScope.token, isBurner: false)
        fixture.script.browserToolsDocumentDidCommit()
        scopeCreations = 0

        fixture.service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        let rejected = await fixture.service.invoker.invokeClientTool(try request(), context: staleContext, permissionPrompter: nil)

        XCTAssertEqual(rejected, .failure(callId: "call", error: .unavailable))
        XCTAssertEqual(scopeCreations, 0)
        let accepted = await fixture.invoke()
        XCTAssertEqual(accepted, fixture.success)
        XCTAssertEqual(scopeCreations, 1)
        XCTAssertNotEqual(createdScope?.token, originalScope.token)
    }

    func testBothGatesAreDynamicForSameServiceAndParentFeature() throws {
        let flags = MockFeatureFlagger(internalUserDecider: MockInternalUserDecider(isInternalUser: false), enabledFeatureFlags: [])
        let feature = ChatToBrowserToolCallingFeature(featureFlagger: flags)
        let suiteName = UUID().uuidString
        let storage = UserDefaults(suiteName: suiteName)!
        defer { storage.removePersistentDomain(forName: suiteName) }
        let service = AIChatBrowserToolsService(featureFlagger: flags, permissionStorage: storage.keyedStoring(), capabilities: [.listOpenTabs])
        let catalog = service.catalog
        let invoker = service.invoker
        let permissions = service.permissions
        let coordinator = service.clientToolPermissions
        let states: [[FeatureFlag]] = [[], [.aiChatBrowserTools], [.aiChatBrowserToolListOpenTabs],
                                      [.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs], [],
                                      [.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs]]
        for state in states {
            flags.enabledFeatureFlags = state
            let parentEnabled = state.contains(.aiChatBrowserTools)
            let toolEnabled = parentEnabled && state.contains(.aiChatBrowserToolListOpenTabs)
            XCTAssertEqual(feature.isAvailable, parentEnabled)
            XCTAssertEqual(service.isEnabled, parentEnabled)
            XCTAssertEqual(service.catalog.enabledClientToolCapabilities, toolEnabled ? [.listOpenTabs] : [])
            XCTAssertEqual(service.clientToolsConfiguration?.capabilities, toolEnabled ? [.listOpenTabs] : nil)
            XCTAssertEqual(service.catalog.enabledTools.map(\.name), toolEnabled ? ["listOpenTabs"] : [])
            XCTAssertEqual(service.catalog.tool(named: "listOpenTabs") != nil, toolEnabled)
            XCTAssertTrue(service.catalog === catalog)
            XCTAssertTrue(service.invoker === invoker)
            XCTAssertTrue(service.permissions === permissions)
            XCTAssertTrue(service.clientToolPermissions === coordinator)
        }
        let config = try XCTUnwrap(service.clientToolsConfiguration)
        XCTAssertEqual(config.protocolVersion, 1)
        XCTAssertEqual(config.capabilities.first?.version, 1)
        XCTAssertTrue(ClientToolPayloadLimits.fits(config, within: ClientToolPayloadLimits.configBytes))
    }

    func testCatalogAndInvokerRefuseUnsupportedNamesVersionsAndDisabledGates() async throws {
        let flags = MockFeatureFlagger(internalUserDecider: MockInternalUserDecider(isInternalUser: true),
                                      enabledFeatureFlags: [.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs])
        let suiteName = UUID().uuidString
        let storage = UserDefaults(suiteName: suiteName)!
        defer { storage.removePersistentDomain(forName: suiteName) }
        let service = AIChatBrowserToolsService(featureFlagger: flags,
                                               permissionStorage: storage.keyedStoring(), capabilities: [.listOpenTabs])
        let context = BrowserToolCallContext(ownerTabID: "owner", isBurner: false)
        for name in ["switchToTab", "searchHistory", "readTabContent", "findInPage", "highlightInPage", "unknown", "featureEnabled"] {
            XCTAssertNil(service.catalog.tool(named: name))
            let result = await service.invoker.invokeClientTool(try request(name: name), context: context, permissionPrompter: nil)
            XCTAssertEqual(result, .failure(callId: "call", error: .unavailable))
        }
        let otherVersion = try ClientToolCapability(name: "listOpenTabs", version: 2)
        XCTAssertNil(service.catalog.tool(for: otherVersion))
        let versionResult = await service.invoker.invokeClientTool(try request(version: 2), context: context, permissionPrompter: nil)
        XCTAssertEqual(versionResult, .failure(callId: "call", error: .unavailable))
        let disabledStates: [[FeatureFlag]] = [[], [.aiChatBrowserTools], [.aiChatBrowserToolListOpenTabs]]
        for state in disabledStates {
            flags.enabledFeatureFlags = state
            let result = await service.invoker.invokeClientTool(try request(), context: context, permissionPrompter: nil)
            XCTAssertEqual(result, .failure(callId: "call", error: .unavailable))
        }
    }

    func testDefaultResolverRefusesEvenWithStoredPermission() async throws {
        let flags = MockFeatureFlagger(internalUserDecider: MockInternalUserDecider(isInternalUser: true),
                                      enabledFeatureFlags: [.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs])
        let suiteName = UUID().uuidString
        let storage = UserDefaults(suiteName: suiteName)!
        defer { storage.removePersistentDomain(forName: suiteName) }
        let service = AIChatBrowserToolsService(featureFlagger: flags,
                                               permissionStorage: storage.keyedStoring(), capabilities: [.listOpenTabs])
        service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        let context = BrowserToolCallContext(ownerTabID: "owner", isBurner: false)
        let result = await service.invoker.invokeClientTool(try request(), context: context, permissionPrompter: nil)
        XCTAssertEqual(result, .failure(callId: "call", error: .unavailable))
    }

    func testStoredListingPermissionRechecksDynamicScope() async throws {
        let owner = Tab(uid: "owner", link: Link(title: "Owner", url: URL(string: "https://example.com")!), fireTab: false)
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner] })
        let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { owner.uid })
        var available = true
        let flags = MockFeatureFlagger(internalUserDecider: MockInternalUserDecider(isInternalUser: true),
                                      enabledFeatureFlags: [.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs])
        let suiteName = UUID().uuidString
        let storage = UserDefaults(suiteName: suiteName)!
        defer { storage.removePersistentDomain(forName: suiteName) }
        let service = AIChatBrowserToolsService(featureFlagger: flags, scopeProvider: { _ in available ? scope : nil },
                                               permissionStorage: storage.keyedStoring(), capabilities: [.listOpenTabs])
        let context = BrowserToolCallContext(ownerTabID: owner.uid, ownerWindowToken: scope.token,
                                             isBurner: false)
        service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        let allowed = await service.invoker.invokeClientTool(try request(), context: context, permissionPrompter: nil)
        let expected: JSONValue = ["tabs": [["tabId": "owner", "title": "Owner", "url": "https://example.com",
                                             "isCurrentTab": true, "isAttachable": true]]]
        XCTAssertEqual(allowed, .success(callId: "call", value: expected))
        XCTAssertEqual(service.permissions.state(forToolNamed: "listOpenTabs"), .allow)
        available = false
        let unavailable = await service.invoker.invokeClientTool(try request(), context: context, permissionPrompter: nil)
        XCTAssertEqual(unavailable, .failure(callId: "call", error: .unavailable))
        available = true
        let malformed = await service.invoker.invokeClientTool(try request(input: ["other": true]), context: context, permissionPrompter: nil)
        XCTAssertEqual(malformed, .failure(callId: "call", error: .invalidArguments))
    }

    func testDefaultCapabilitiesAdvertiseListingAndSwitchAndPromptForListing() async throws {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        fixture.flags.enabledFeatureFlags.append(.aiChatBrowserToolSwitchToTab)
        let service = AIChatBrowserToolsService(featureFlagger: fixture.flags,
                                               permissionStorage: fixture.defaults.keyedStoring())
        fixture.script.bindBrowserTools(to: service, owner: fixture.owner, presenter: fixture.presenter, makeScope: fixture.makeScope)
        XCTAssertEqual(service.configuration(for: fixture.script)?.capabilities, [.listOpenTabs, .switchToTab])
        XCTAssertEqual(service.catalog.enabledTools.map(\.name), ["listOpenTabs", "switchToTab"])
        XCTAssertNotNil(service.catalog.tool(named: "listOpenTabs"))
        XCTAssertNotNil(service.catalog.tool(for: .listOpenTabs))
        let result = await service.invoke(try request(), from: fixture.script)
        XCTAssertEqual(result, fixture.success)
        XCTAssertTrue(fixture.webView.permissionPrompts.isEmpty)
        XCTAssertEqual(fixture.listings, 1)
    }

    func testDefaultCapabilitiesRespectIndependentToolFlagsAndParentFlag() {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        let service = AIChatBrowserToolsService(featureFlagger: fixture.flags,
                                               permissionStorage: fixture.defaults.keyedStoring())
        let catalog = service.catalog
        let states: [([FeatureFlag], [ClientToolCapability])] = [
            ([], []),
            ([.aiChatBrowserTools], []),
            ([.aiChatBrowserToolListOpenTabs], []),
            ([.aiChatBrowserToolSwitchToTab], []),
            ([.aiChatBrowserToolListOpenTabs, .aiChatBrowserToolSwitchToTab], []),
            ([.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs], [.listOpenTabs]),
            ([.aiChatBrowserTools, .aiChatBrowserToolSwitchToTab], [.switchToTab]),
            ([.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs, .aiChatBrowserToolSwitchToTab], [.listOpenTabs, .switchToTab]),
            ([], [])
        ]
        for (state, capabilities) in states {
            fixture.flags.enabledFeatureFlags = state
            XCTAssertEqual(service.clientToolsConfiguration?.capabilities, capabilities.isEmpty ? nil : capabilities)
            XCTAssertEqual(service.catalog.tool(for: .listOpenTabs) != nil, capabilities.contains(.listOpenTabs))
            XCTAssertEqual(service.catalog.tool(for: .switchToTab) != nil, capabilities.contains(.switchToTab))
            XCTAssertTrue(service.catalog === catalog)
        }
    }

    func testAutomaticSwitchCannotBypassUnavailableNativeSurface() async throws {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        fixture.flags.enabledFeatureFlags.append(.aiChatBrowserToolSwitchToTab)
        let service = AIChatBrowserToolsService(featureFlagger: fixture.flags,
                                               permissionStorage: fixture.defaults.keyedStoring())
        fixture.script.bindBrowserTools(to: service, owner: fixture.owner, presenter: fixture.presenter, makeScope: fixture.makeScope)
        fixture.presenter.isAvailable = false
        let result = await service.invoke(try request(name: "switchToTab", input: ["tabId": "owner"]), from: fixture.script)
        XCTAssertEqual(result, .failure(callId: "call", error: .cancelled))
        XCTAssertTrue(fixture.presenter.prompts.isEmpty)
    }

    func testExecutingSwitchSurvivesItsOwnSourceDeparture() async throws {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        fixture.flags.enabledFeatureFlags.append(.aiChatBrowserToolSwitchToTab)
        let service = AIChatBrowserToolsService(featureFlagger: fixture.flags,
                                               permissionStorage: fixture.defaults.keyedStoring())
        let source = MultiTabAttachmentSource(currentTabID: fixture.owner.uid, mode: .normal,
                                              tabsProvider: { [fixture.owner] })
        let scope = BrowserToolScope(owner: fixture.owner, source: source, selectedTabID: { fixture.owner.uid },
                                     selectTab: { [weak service, weak script = fixture.script] _ in
            guard let service, let script else { return false }
            fixture.presenter.isAvailable = false
            service.sourceWillDisappear(script)
            return true
        })
        fixture.script.bindBrowserTools(to: service, owner: fixture.owner, presenter: fixture.presenter, makeScope: { scope })
        let result = await service.invoke(try request(name: "switchToTab", input: ["tabId": "owner"]), from: fixture.script)
        XCTAssertEqual(result, .success(callId: "call", value: ["tabId": "owner"]))
        XCTAssertTrue(fixture.presenter.prompts.isEmpty)
    }

    func testSourceBoundSwitchIgnoresStoredDenyAndActivePermissionPrompt() async throws {
        let fixture = BrowserToolsBridgeFixture()
        defer { fixture.cleanUp() }
        fixture.flags.enabledFeatureFlags.append(.aiChatBrowserToolSwitchToTab)
        let target = Tab(uid: "target", link: Link(title: "Private title", url: URL(string: "https://private.example")!), fireTab: false)
        var selections: [Tab] = []
        let source = MultiTabAttachmentSource(currentTabID: fixture.owner.uid, mode: .normal,
                                              tabsProvider: { [fixture.owner, target] })
        let scope = BrowserToolScope(owner: fixture.owner, source: source, selectedTabID: { fixture.owner.uid },
                                     selectTab: { selections.append($0); return true })
        let service = AIChatBrowserToolsService(featureFlagger: fixture.flags,
                                               permissionStorage: fixture.defaults.keyedStoring())
        service.permissions.setState(.deny, forToolNamed: "switchToTab")
        fixture.script.bindBrowserTools(to: service, owner: fixture.owner, presenter: fixture.presenter, makeScope: { scope })
        fixture.presenter.autoAnswer = nil
        let prompt = ClientToolPermissionPrompt(requestID: "pending", callID: "pending-call", toolName: "listOpenTabs")
        XCTAssertTrue(fixture.presenter.present(prompt, message: "Permission") { _ in XCTFail("No decision selected") })
        defer { fixture.presenter.withdrawActive {} }
        let result = await service.invoke(try request(name: "switchToTab", input: ["tabId": "target"]), from: fixture.script)
        XCTAssertEqual(result, .success(callId: "call", value: ["tabId": "target"]))
        XCTAssertEqual(selections.count, 1)
        XCTAssertTrue(selections.first === target)
        XCTAssertTrue(fixture.webView.permissionPrompts.isEmpty)
        XCTAssertEqual(fixture.presenter.prompts.count, 1)
        XCTAssertTrue(fixture.presenter.isPresentingPermission)
        XCTAssertEqual(service.permissions.state(forToolNamed: "switchToTab"), .deny)
    }

}
