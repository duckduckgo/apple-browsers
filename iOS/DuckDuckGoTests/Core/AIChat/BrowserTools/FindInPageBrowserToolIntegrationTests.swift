//
//  FindInPageBrowserToolIntegrationTests.swift
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
import Combine
import Core
import FeatureFlags_iOS
import Persistence
import SitePermissions
import XCTest
@testable import DuckDuckGo

@MainActor
final class FindInPageBrowserToolIntegrationTests: XCTestCase {
    private let enabledFlags: [FeatureFlag] = [.aiChatBrowserTools, .aiChatBrowserToolFindInPage]

    func testDefaultRegistrationUsesIndependentFindAndReadFlagsAndParentGate() async throws {
        let fixture = BrowserToolsBridgeFixture(enabledFlags: [])
        defer { fixture.cleanUp() }
        let service = AIChatBrowserToolsService(featureFlagger: fixture.flags, historyManager: MockHistoryManager(), sitePermissionsStore: SitePermissionsStore(storage: fixture.defaults.keyedStoring()))
        fixture.script.bindBrowserTools(to: service, owner: fixture.owner, presenter: fixture.presenter, makeScope: fixture.makeScope)
        let states: [([FeatureFlag], [ClientToolCapability])] = [
            ([.aiChatBrowserTools, .aiChatBrowserToolReadTabContent, .aiChatBrowserToolSearchHistory, .aiChatBrowserToolFindInPage],
             [.readTabContent, .searchHistory, .findInPage]),
            ([.aiChatBrowserTools, .aiChatBrowserToolReadTabContent, .aiChatBrowserToolFindInPage], [.readTabContent, .findInPage]),
            ([.aiChatBrowserTools, .aiChatBrowserToolReadTabContent], [.readTabContent]),
            ([.aiChatBrowserTools, .aiChatBrowserToolFindInPage], [.findInPage]),
            ([.aiChatBrowserToolReadTabContent, .aiChatBrowserToolFindInPage], []),
            ([.aiChatBrowserTools], [])
        ]
        for (flags, capabilities) in states {
            fixture.flags.enabledFeatureFlags = flags
            XCTAssertEqual(service.clientToolsConfiguration?.capabilities, capabilities.isEmpty ? nil : capabilities)
            XCTAssertEqual(service.catalog.tool(for: .findInPage)?.permissionMode, capabilities.contains(.findInPage) ? .ask : nil)
            XCTAssertEqual(service.catalog.tool(for: .readTabContent) != nil, capabilities.contains(.readTabContent))
            if !capabilities.contains(.findInPage) {
                let result = await service.invoke(try request(), from: fixture.script)
                XCTAssertEqual(result, .failure(callId: "call", error: .unavailable))
            }
        }
        XCTAssertTrue(fixture.presenter.prompts.isEmpty)
        XCTAssertEqual(fixture.pageAcquisitions, 0)
    }

    func testNativeDecisionsGateReadingAndAreStoredSeparatelyForFindInPage() async throws {
        for decision: ClientToolPermissionDecision in [.always, .never] {
            let fixture = makeFixture()
            defer { fixture.cleanUp() }
            fixture.service.permissions.setState(.deny, forToolNamed: "readTabContent")
            fixture.presenter.autoAnswer = nil
            let prompted = expectation(description: "Find permission requested")
            fixture.presenter.onPresent = { prompted.fulfill() }
            let request = try request()
            let task = Task { await fixture.service.invoke(request, from: fixture.script) }
            await fulfillment(of: [prompted], timeout: 1)
            XCTAssertEqual(fixture.pageAcquisitions, 0)
            XCTAssertEqual(fixture.presenter.prompts.map(\.toolName), ["findInPage"])
            XCTAssertTrue(fixture.webView.permissionPrompts.isEmpty)
            fixture.presenter.select(decision)
            let first = await task.value
            let second = await fixture.service.invoke(request, from: fixture.script)
            if decision == .always {
                for response in [first, second] {
                    guard case .success(_, let value) = response else { XCTFail("Expected allowed search: \(response)"); continue }
                    XCTAssertEqual(value["matchCount"], 2)
                    XCTAssertEqual(value["matchIndexesReliable"], false)
                }
                XCTAssertEqual(fixture.pageAcquisitions, 2)
                XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "findInPage"), .allow)
            } else {
                XCTAssertEqual(first, .failure(callId: "call", error: .denied))
                XCTAssertEqual(second, .failure(callId: "call", error: .denied))
                XCTAssertEqual(fixture.pageAcquisitions, 0)
                XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "findInPage"), .deny)
            }
            XCTAssertEqual(fixture.presenter.prompts.count, 1)
            XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "readTabContent"), .deny)
        }
    }

    func testDisablingFlagsDuringReadAllowsCompletionAndBlocksNextInvocation() async throws {
        for disabled in [FeatureFlag.aiChatBrowserTools, .aiChatBrowserToolFindInPage] {
            let fixture = makeFixture()
            defer { fixture.cleanUp() }
            let owner = fixture.owner
            let webView = NSObject()
            let navigation = UUID()
            let completion = PassthroughSubject<AIChatPageContextData, Never>()
            let started = expectation(description: "Find extraction started")
            var releases = 0
            fixture.sourceProvider = {
                MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner] }, pageProvider: { _ in
                    MultiTabAttachmentPage(state: {
                        .init(identity: .init(webView: ObjectIdentifier(webView), navigation: navigation), url: owner.link?.url,
                              isLoading: false, isLoaded: true, isAttachable: true)
                    }, changes: Empty().eraseToAnyPublisher(), collect: { _, _ in
                        let result = await MultiTabAttachmentWaiter.firstValue(from: completion.eraseToAnyPublisher(), timeout: 2) {
                            started.fulfill()
                        }
                        guard case .value(let context) = result else { return .unavailable }
                        return .collected(context)
                    })
                }, acquirePage: { _ in MultiTabAttachmentPage.Reservation { releases += 1 } })
            }
            let request = try request()
            let task = Task { await fixture.service.invoke(request, from: fixture.script) }
            await fulfillment(of: [started], timeout: 1)
            fixture.flags.enabledFeatureFlags.removeAll { $0 == disabled }
            fixture.flags.triggerUpdate()
            completion.send(AIChatPageContextData(title: "Owner", favicon: [], url: "https://owner.example", content: "body body",
                                                   truncated: false, fullContentLength: 9))
            let result = await task.value
            guard case .success(_, let value) = result else { XCTFail("Expected admitted search: \(result)"); continue }
            XCTAssertEqual(value["matchCount"], 2)
            XCTAssertEqual(value["contentTruncated"], false)
            XCTAssertEqual(value["matchIndexesReliable"], false)
            XCTAssertEqual(releases, 1)
            let next = await fixture.service.invoke(request, from: fixture.script)
            XCTAssertEqual(next, .failure(callId: "call", error: .unavailable))
            XCTAssertEqual(fixture.presenter.prompts.count, 1)
        }
    }

    private func makeFixture() -> BrowserToolsBridgeFixture {
        let fixture = BrowserToolsBridgeFixture(enabledFlags: enabledFlags, capabilities: [.findInPage])
        let owner = fixture.owner
        let webView = NSObject()
        let navigation = UUID()
        fixture.sourceProvider = { [weak fixture] in
            MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [weak fixture] in
                fixture?.ownerPresent == true ? [owner] : []
            }, pageProvider: { _ in
                MultiTabAttachmentPage(state: {
                    .init(identity: .init(webView: ObjectIdentifier(webView), navigation: navigation), url: owner.link?.url,
                          isLoading: false, isLoaded: true, isAttachable: true)
                }, changes: Empty().eraseToAnyPublisher(), collect: { _, _ in
                    .collected(AIChatPageContextData(title: "Owner", favicon: [], url: "https://owner.example", content: "body body",
                                                       truncated: false, fullContentLength: 9))
                })
            }, acquirePage: { [weak fixture] _ in
                fixture?.pageAcquisitions += 1
                return MultiTabAttachmentPage.Reservation {}
            })
        }
        return fixture
    }

    private func request() throws -> ExecuteClientToolRequest {
        let value: JSONValue = ["callId": "call", "capability": ["name": "findInPage", "version": 1], "input": ["query": "body"]]
        return try JSONDecoder().decode(ExecuteClientToolRequest.self, from: JSONEncoder().encode(value))
    }
}
