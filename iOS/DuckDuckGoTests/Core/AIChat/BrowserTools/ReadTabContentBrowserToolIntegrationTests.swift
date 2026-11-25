//
//  ReadTabContentBrowserToolIntegrationTests.swift
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
import XCTest
@testable import DuckDuckGo

@MainActor
final class ReadTabContentBrowserToolIntegrationTests: XCTestCase {
    private let enabledFlags: [FeatureFlag] = [.aiChatBrowserTools, .aiChatBrowserToolReadTabContent, .aiChatBrowserToolListOpenTabs]

    func testReadTabContentUsesNativeDecisionsAndStoredPermissions() async throws {
        for decision: ClientToolPermissionDecision in [.allowOnce, .always, .never, .dismiss] {
            let fixture = makeFixture()
            defer { fixture.cleanUp() }
            fixture.presenter.autoAnswer = decision
            let response = await fixture.service.invoke(try request(), from: fixture.script)
            XCTAssertEqual(fixture.presenter.prompts.map(\.toolName), ["readTabContent"])
            let tool = try XCTUnwrap(fixture.service.catalog.tool(for: .readTabContent))
            XCTAssertEqual(tool.permissionMode, .ask)
            switch decision {
            case .allowOnce, .always:
                guard case .success = response else { XCTFail("Expected success: \(response)"); continue }
            case .never: XCTAssertEqual(response, .failure(callId: "call", error: .denied))
            case .dismiss: XCTAssertEqual(response, .failure(callId: "call", error: .cancelled))
            case .allowForChat, .allowAccess, .dontAllow: XCTFail("Not answered in this test: \(decision)")
            }
            if decision == .never || decision == .dismiss {
                XCTAssertEqual(fixture.pageAcquisitions, 0)
            }
            if decision == .always || decision == .never {
                let second = await fixture.service.invoke(try request(), from: fixture.script)
                if decision == .never {
                    XCTAssertEqual(second, .failure(callId: "call", error: .denied))
                } else if case .failure = second {
                    XCTFail("Stored allow did not execute")
                }
                XCTAssertEqual(fixture.presenter.prompts.count, 1)
                XCTAssertEqual(fixture.service.permissions.state(forToolNamed: "readTabContent"), decision == .always ? .allow : .deny)
            } else if decision == .allowOnce {
                _ = await fixture.service.invoke(try request(), from: fixture.script)
                XCTAssertEqual(fixture.presenter.prompts.count, 2)
            }
        }
    }

    func testFirstAuthorizedReadPreparesColdPageAndReturnsUnattachedContent() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        fixture.presenter.autoAnswer = .allowOnce
        let owner = fixture.owner
        let webView = NSObject()
        let changes = PassthroughSubject<Void, Never>()
        var navigation = UUID()
        var loaded = false
        var acquisitions = 0
        var releases = 0
        fixture.sourceProvider = {
            MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [owner] }, pageProvider: { _ in
                MultiTabAttachmentPage(state: {
                    .init(identity: .init(webView: ObjectIdentifier(webView), navigation: navigation),
                          url: loaded ? owner.link?.url : nil, isLoading: !loaded, isLoaded: loaded,
                          isAttachable: loaded, isInitialRequestPending: !loaded)
                }, changes: changes.eraseToAnyPublisher(), collect: { url, isValid in
                    guard isValid() else { return .unavailable }
                    return .collected(AIChatPageContextData(title: "Owner", favicon: [], url: url.absoluteString,
                                                           content: "cold body", truncated: false, fullContentLength: 9))
                }, loadIfNeeded: {
                    navigation = UUID()
                    loaded = true
                    changes.send(())
                })
            }, acquirePage: { _ in
                acquisitions += 1
                return MultiTabAttachmentPage.Reservation { releases += 1 }
            })
        }
        let response = await fixture.service.invoke(try request(), from: fixture.script)
        guard case .success(_, let value) = response else { return XCTFail("Expected cold page content: \(response)") }
        XCTAssertEqual(value["content"], "cold body")
        XCTAssertEqual(value["attached"], false)
        XCTAssertEqual(value["tabId"], .string(owner.uid))
        XCTAssertEqual(fixture.presenter.prompts.count, 1)
        XCTAssertEqual(acquisitions, 1)
        XCTAssertEqual(releases, 1)
    }

    func testPageIsAcquiredOnlyAfterPermissionAndTargetIsResolvedThen() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        var acquisitions = 0
        let target = Tab(uid: "target", link: fixture.owner.link, fireTab: false)
        var tabs = [fixture.owner, target]
        let owner = fixture.owner
        fixture.sourceProvider = {
            MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { tabs },
                                     acquirePage: { _ in acquisitions += 1; return nil })
        }
        fixture.presenter.autoAnswer = nil
        let prompted = expectation(description: "Permission requested")
        fixture.presenter.onPresent = { prompted.fulfill() }
        let request = try request(target: target.uid)
        let task = Task { await fixture.service.invoke(request, from: fixture.script) }
        await fulfillment(of: [prompted], timeout: 1)
        XCTAssertEqual(acquisitions, 0)
        tabs = [fixture.owner]
        fixture.presenter.select(.allowOnce)
        let result = await task.value
        XCTAssertEqual(result, .failure(callId: "call", error: .notFound))
        XCTAssertEqual(acquisitions, 0)
    }

    func testRelevantFlagDisabledWhilePermissionPendingPreventsPageAcquisition() async throws {
        for disableParent in [false, true] {
            let fixture = makeFixture()
            defer { fixture.cleanUp() }
            fixture.presenter.autoAnswer = nil
            let prompted = expectation(description: "Permission requested")
            fixture.presenter.onPresent = { prompted.fulfill() }
            let request = try request()
            let task = Task { await fixture.service.invoke(request, from: fixture.script) }
            await fulfillment(of: [prompted], timeout: 1)
            let flag = disableParent ? FeatureFlag.aiChatBrowserTools : FeatureFlag.aiChatBrowserToolReadTabContent
            fixture.flags.enabledFeatureFlags.removeAll { $0 == flag }
            fixture.flags.triggerUpdate()
            fixture.presenter.select(.always)
            let result = await task.value
            XCTAssertEqual(result, .failure(callId: "call", error: .cancelled))
            XCTAssertTrue(fixture.service.permissions.storedDecisions.isEmpty)
            XCTAssertEqual(fixture.pageAcquisitions, 0)
        }
    }

    func testUnrelatedConfigurationUpdateKeepsPromptAndExecutionAvailable() async throws {
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        fixture.presenter.autoAnswer = nil
        let prompted = expectation(description: "Permission requested")
        fixture.presenter.onPresent = { prompted.fulfill() }
        let request = try request()
        let task = Task { await fixture.service.invoke(request, from: fixture.script) }
        await fulfillment(of: [prompted], timeout: 1)
        fixture.flags.enabledFeatureFlags.removeAll { $0 == .aiChatBrowserToolListOpenTabs }
        fixture.flags.triggerUpdate()
        fixture.presenter.select(.allowOnce)
        let result = await task.value
        guard case .success = result else { return XCTFail("Unrelated update cancelled read: \(result)") }
    }

    func testMainAndIndividualGatesBlockBeforePrompting() async throws {
        for flag in [FeatureFlag.aiChatBrowserTools, FeatureFlag.aiChatBrowserToolReadTabContent] {
            let fixture = makeFixture()
            defer { fixture.cleanUp() }
            fixture.flags.enabledFeatureFlags.removeAll { $0 == flag }
            let result = await fixture.service.invoke(try request(), from: fixture.script)
            XCTAssertEqual(result, .failure(callId: "call", error: .unavailable))
            XCTAssertTrue(fixture.presenter.prompts.isEmpty)
        }
    }

    func testFireOwnerAndClearingCannotRead() async throws {
        let fire = BrowserToolsBridgeFixture(fire: true, enabledFlags: enabledFlags, capabilities: [.readTabContent])
        defer { fire.cleanUp() }
        let fireResult = await fire.service.invoke(try request(), from: fire.script)
        XCTAssertEqual(fireResult, .failure(callId: "call", error: .unavailable))
        let fixture = makeFixture()
        defer { fixture.cleanUp() }
        _ = fixture.script
        let token = fixture.service.beginClearing(.all)
        let result = await fixture.service.invoke(try request(), from: fixture.script)
        fixture.service.endClearing(token)
        XCTAssertEqual(result, .failure(callId: "call", error: .unavailable))
        XCTAssertTrue(fixture.presenter.prompts.isEmpty)
    }

    func testLifecycleChangesCancelReadsAndFlagChangesAllowCompletionWithPageRelease() async throws {
        for event in ["fire", "detach", "document", "toolFlag", "mainFlag", "ownerLoss"] {
            let fixture = makeFixture()
            defer { fixture.cleanUp() }
            let owner = fixture.owner
            let webView = NSObject()
            let navigation = UUID()
            let completion = PassthroughSubject<AIChatPageContextData, Never>()
            let tabsChanged = PassthroughSubject<[Tab], Never>()
            let started = expectation(description: "Extraction started")
            let cancelled = XCTestExpectation(description: "Extraction cancelled")
            var ownerPresent = true
            var releases = 0
            fixture.sourceProvider = {
                MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { ownerPresent ? [owner] : [] },
                                         tabsPublisher: tabsChanged.eraseToAnyPublisher(), pageProvider: { _ in
                    MultiTabAttachmentPage(state: {
                        .init(identity: .init(webView: ObjectIdentifier(webView), navigation: navigation), url: owner.link?.url,
                              isLoading: false, isLoaded: true, isAttachable: true)
                    }, changes: Empty().eraseToAnyPublisher(), collect: { _, _ in
                        let result = await MultiTabAttachmentWaiter.firstValue(from: completion.eraseToAnyPublisher(), timeout: 30) {
                            started.fulfill()
                        }
                        if Task.isCancelled { cancelled.fulfill(); return .cancelled }
                        if case .value(let context) = result { return .collected(context) }
                        return .unavailable
                    })
                }, acquirePage: { _ in MultiTabAttachmentPage.Reservation { releases += 1 } })
            }
            let request = try request()
            let task = Task { await fixture.service.invoke(request, from: fixture.script) }
            await fulfillment(of: [started], timeout: 1)
            switch event {
            case "fire":
                let token = fixture.service.beginClearing(.all)
                fixture.service.didClear(token)
                fixture.service.endClearing(token)
            case "detach": fixture.script.detachBrowserTools()
            case "document": fixture.service.documentDidCommit(fixture.script)
            case "ownerLoss": ownerPresent = false; tabsChanged.send([])
            default:
                let disabled = event == "toolFlag" ? FeatureFlag.aiChatBrowserToolReadTabContent : .aiChatBrowserTools
                fixture.flags.enabledFeatureFlags.removeAll { $0 == disabled }
                fixture.flags.triggerUpdate()
            }
            if event == "toolFlag" || event == "mainFlag" {
                completion.send(AIChatPageContextData(title: "Owner", favicon: [], url: "https://owner.example", content: "body", truncated: false, fullContentLength: 4))
                let result = await task.value
                guard case .success(_, let value) = result else { XCTFail("Expected content for \(event): \(result)"); continue }
                XCTAssertEqual(value["content"], "body", event)
                XCTAssertEqual(value["attached"], false, event)
            } else {
                let result = await task.value
                guard case .failure = result else { XCTFail("Stale result for \(event)"); continue }
                await fulfillment(of: [cancelled], timeout: 1)
                XCTAssertEqual(releases, 1, event)
                completion.send(AIChatPageContextData(title: "stale", favicon: [], url: "https://owner.example", content: "body", truncated: false, fullContentLength: 4))
            }
            XCTAssertEqual(releases, 1, event)
        }
    }

    private func makeFixture() -> BrowserToolsBridgeFixture {
        let fixture = BrowserToolsBridgeFixture(enabledFlags: enabledFlags, capabilities: [.readTabContent])
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
                    .collected(AIChatPageContextData(title: "Owner", favicon: [], url: "https://owner.example", content: "body", truncated: false, fullContentLength: 4))
                })
            }, acquirePage: { [weak fixture] _ in
                fixture?.pageAcquisitions += 1
                return MultiTabAttachmentPage.Reservation {}
            })
        }
        return fixture
    }

    private func request(target: String? = nil) throws -> ExecuteClientToolRequest {
        var input: [String: JSONValue] = [:]
        if let target { input["tabId"] = .string(target) }
        let value: JSONValue = ["callId": "call", "capability": ["name": .string(ClientToolCapability.readTabContent.name), "version": 1], "input": .object(input)]
        return try JSONDecoder().decode(ExecuteClientToolRequest.self, from: JSONEncoder().encode(value))
    }

}
