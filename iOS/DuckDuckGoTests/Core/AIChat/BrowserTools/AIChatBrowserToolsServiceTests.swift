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

import AIChat
import Core
import FeatureFlags_iOS
import Persistence
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatBrowserToolsServiceTests: XCTestCase {
    private func request(name: String = "listOpenTabs", version: Int = 1, input: JSONValue = [:]) throws -> ExecuteClientToolRequest {
        let value: JSONValue = ["callId": "call", "capability": ["name": .string(name), "version": .int(version)], "input": input]
        return try JSONDecoder().decode(ExecuteClientToolRequest.self, from: JSONEncoder().encode(value))
    }

    func testBothGatesAreDynamicForSameServiceAndParentFeature() throws {
        let flags = MockFeatureFlagger(enabledFeatureFlags: [])
        let feature = ChatToBrowserToolCallingFeature(featureFlagger: flags)
        let suiteName = UUID().uuidString
        let storage = UserDefaults(suiteName: suiteName)!
        defer { storage.removePersistentDomain(forName: suiteName) }
        let service = AIChatBrowserToolsService(featureFlagger: flags, permissionStorage: storage.keyedStoring())
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
        let flags = MockFeatureFlagger(enabledFeatureFlags: [.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs])
        let suiteName = UUID().uuidString
        let storage = UserDefaults(suiteName: suiteName)!
        defer { storage.removePersistentDomain(forName: suiteName) }
        let service = AIChatBrowserToolsService(featureFlagger: flags,
                                               permissionStorage: storage.keyedStoring())
        let context = BrowserToolCallContext(ownerTabID: "owner", isBurner: false)
        for name in ["switchToTab", "searchHistory", "readTabContent", "findInPage", "highlightInPage", "unknown", "featureEnabled"] {
            XCTAssertNil(service.catalog.tool(named: name))
            let result = await service.invoker.invokeClientTool(try request(name: name), context: context, permissionPusher: nil)
            XCTAssertEqual(result, .failure(callId: "call", error: .unavailable))
        }
        let otherVersion = try ClientToolCapability(name: "listOpenTabs", version: 2)
        XCTAssertNil(service.catalog.tool(for: otherVersion))
        let versionResult = await service.invoker.invokeClientTool(try request(version: 2), context: context, permissionPusher: nil)
        XCTAssertEqual(versionResult, .failure(callId: "call", error: .unavailable))
        let disabledStates: [[FeatureFlag]] = [[], [.aiChatBrowserTools], [.aiChatBrowserToolListOpenTabs]]
        for state in disabledStates {
            flags.enabledFeatureFlags = state
            let result = await service.invoker.invokeClientTool(try request(), context: context, permissionPusher: nil)
            XCTAssertEqual(result, .failure(callId: "call", error: .unavailable))
        }
    }

    func testDefaultResolverRefusesEvenWithStoredPermission() async throws {
        let flags = MockFeatureFlagger(enabledFeatureFlags: [.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs])
        let suiteName = UUID().uuidString
        let storage = UserDefaults(suiteName: suiteName)!
        defer { storage.removePersistentDomain(forName: suiteName) }
        let service = AIChatBrowserToolsService(featureFlagger: flags,
                                               permissionStorage: storage.keyedStoring())
        service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        let context = BrowserToolCallContext(ownerTabID: "owner", isBurner: false)
        let result = await service.invoker.invokeClientTool(try request(), context: context, permissionPusher: nil)
        XCTAssertEqual(result, .failure(callId: "call", error: .unavailable))
    }

    func testInvokerUsesSharedPermissionStoreAndDynamicScopeResolver() async throws {
        let owner = Tab(uid: "owner", link: Link(title: "Owner", url: URL(string: "https://example.com")!), fireTab: false)
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner] })
        let scope = BrowserToolScope(owner: owner, source: source, selectedTabID: { owner.uid })
        var available = true
        let flags = MockFeatureFlagger(enabledFeatureFlags: [.aiChatBrowserTools, .aiChatBrowserToolListOpenTabs])
        let suiteName = UUID().uuidString
        let storage = UserDefaults(suiteName: suiteName)!
        defer { storage.removePersistentDomain(forName: suiteName) }
        let service = AIChatBrowserToolsService(featureFlagger: flags, scopeProvider: { _ in available ? scope : nil },
                                               permissionStorage: storage.keyedStoring())
        let context = BrowserToolCallContext(ownerTabID: owner.uid, ownerWindowToken: scope.token,
                                             isBurner: false)
        service.permissions.setState(.deny, forToolNamed: "listOpenTabs")
        let denied = await service.invoker.invokeClientTool(try request(), context: context, permissionPusher: nil)
        XCTAssertEqual(denied, .failure(callId: "call", error: .denied))
        service.permissions.setState(.allow, forToolNamed: "listOpenTabs")
        let allowed = await service.invoker.invokeClientTool(try request(), context: context, permissionPusher: nil)
        let expected: JSONValue = ["tabs": [["tabId": "owner", "title": "Owner", "url": "https://example.com",
                                             "isCurrentTab": true, "isAttachable": true]]]
        XCTAssertEqual(allowed, .success(callId: "call", value: expected))
        available = false
        let unavailable = await service.invoker.invokeClientTool(try request(), context: context, permissionPusher: nil)
        XCTAssertEqual(unavailable, .failure(callId: "call", error: .unavailable))
        available = true
        let malformed = await service.invoker.invokeClientTool(try request(input: ["other": true]), context: context, permissionPusher: nil)
        XCTAssertEqual(malformed, .failure(callId: "call", error: .invalidArguments))
    }
}
