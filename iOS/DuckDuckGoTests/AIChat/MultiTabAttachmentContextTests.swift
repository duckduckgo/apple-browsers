//
//  MultiTabAttachmentContextTests.swift
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
@_spi(Testing) import Persistence
import UserScript
import WebKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class MultiTabAttachmentContextTests: XCTestCase {
    private let url = URL(string: "https://example.com/article")!

    private func makeContext(content: String = "Article content") -> AIChatPageContextData {
        AIChatPageContextData(title: "Article", favicon: [], url: url.absoluteString,
                              content: content, truncated: false, fullContentLength: content.count)
    }

    private func makeSubject(tabs: @escaping () -> [Tab],
                             content: @escaping (Tab) async -> AIChatPageContextData?) -> MultiTabAttachmentContext {
        let feature = MultiTabAttachmentHackFeature(keyValueStore: InMemoryKeyValueStore())
        feature.isMultiTabAttachmentHackPhaseEnabled = true
        return MultiTabAttachmentContext(feature: feature, openTabsProvider: tabs, contentProvider: content)
    }

    func testWhenCacheIsEmptyThenContentIsCollectedBeforeReturningAttachment() async {
        let tab = Tab(link: Link(title: "Article", url: url))
        let expected = makeContext()
        var requestedTab: Tab?
        let subject = makeSubject(tabs: { [tab] }, content: {
            requestedTab = $0
            return expected
        })
        XCTAssertNil(subject.cache.context(forTabId: tab.uid))

        let contexts = await subject.pageContexts(
            for: [.init(tabId: tab.uid, title: "Article", url: url)], currentTabId: nil)

        XCTAssertTrue(requestedTab === tab)
        XCTAssertEqual(contexts, [expected.withTabId(tab.uid)])
        XCTAssertGreaterThan(contexts.first?.content.count ?? 0, 0)
    }

    func testWhenCacheHasOldContentThenSubmissionCollectsFreshContent() async {
        let tab = Tab(link: Link(title: "Article", url: url))
        let expected = makeContext(content: "Fresh article")
        let subject = makeSubject(tabs: { [tab] }, content: { _ in expected })
        subject.cache.store(context: makeContext(content: "Old article"), url: url, forTabId: tab.uid)

        let contexts = await subject.pageContexts(
            for: [.init(tabId: tab.uid, title: "Article", url: url)], currentTabId: nil)

        XCTAssertEqual(contexts.first?.content, "Fresh article")
    }

    func testWhenCollectionFailsThenNoMetadataOnlyAttachmentIsSent() async {
        let tab = Tab(link: Link(title: "Article", url: url))
        let subject = makeSubject(tabs: { [tab] }, content: { _ in nil })
        let contexts = await subject.pageContexts(
            for: [.init(tabId: tab.uid, title: "Article", url: url)], currentTabId: nil)
        XCTAssertTrue(contexts.isEmpty)
    }

    func testWhenTabClosesDuringCollectionThenItsContextIsDropped() async {
        let tab = Tab(link: Link(title: "Article", url: url))
        var tabs = [tab]
        let expected = makeContext()
        let subject = makeSubject(tabs: { tabs }, content: { _ in
            tabs.removeAll()
            return expected
        })
        let contexts = await subject.pageContexts(
            for: [.init(tabId: tab.uid, title: "Article", url: url)], currentTabId: nil)
        XCTAssertTrue(contexts.isEmpty)
    }

    func testWhenTabNavigatesDuringCollectionThenOldContextIsDropped() async {
        let tab = Tab(link: Link(title: "Article", url: url))
        let expected = makeContext()
        let subject = makeSubject(tabs: { [tab] }, content: { _ in
            tab.link = Link(title: "Other", url: URL(string: "https://example.com/other")!)
            return expected
        })
        let contexts = await subject.pageContexts(
            for: [.init(tabId: tab.uid, title: "Article", url: url)], currentTabId: nil)
        XCTAssertTrue(contexts.isEmpty)
    }

    func testWhenAttachmentBelongsToAnotherBrowsingModeThenItIsNotLoaded() async {
        let origin = Tab(link: Link(title: "Origin", url: url))
        let fireTab = Tab(link: Link(title: "Fire", url: url), fireTab: true)
        var didCollect = false
        let subject = makeSubject(tabs: { [origin, fireTab] }, content: { _ in
            didCollect = true
            return nil
        })
        let contexts = await subject.pageContexts(
            for: [.init(tabId: fireTab.uid, title: "Fire", url: url)], currentTabId: origin.uid)
        XCTAssertFalse(didCollect)
        XCTAssertTrue(contexts.isEmpty)
    }

    func testWhenMultipleTabsAreCollectedThenOrderAndCurrentPageDiscriminatorArePreserved() async {
        let first = Tab(link: Link(title: "First", url: url))
        let second = Tab(link: Link(title: "Second", url: url))
        let expected = makeContext()
        let subject = makeSubject(tabs: { [first, second] }, content: { _ in expected })
        let contexts = await subject.pageContexts(for: [
            .init(tabId: second.uid, title: "Second", url: url),
            .init(tabId: first.uid, title: "First", url: url)
        ], currentTabId: first.uid)
        XCTAssertEqual(contexts.map(\.tabId), [second.uid, nil])
    }

    func testWhenOperationCompletesSynchronouslyThenWaiterDoesNotMissResult() async {
        let publisher = PassthroughSubject<Int, Never>()
        let result = await MultiTabAttachmentWaiter.firstValue(
            from: publisher.eraseToAnyPublisher(), timeout: 1, start: { publisher.send(42) })
        XCTAssertEqual(result, 42)
    }

    func testWhenOperationNeverCompletesThenWaiterTimesOutAndUnsubscribes() async {
        let publisher = PassthroughSubject<Int, Never>()
        var didCancel = false
        let result = await MultiTabAttachmentWaiter.firstValue(
            from: publisher.handleEvents(receiveCancel: { didCancel = true }).eraseToAnyPublisher(), timeout: 0.01)
        XCTAssertNil(result)
        XCTAssertTrue(didCancel)
    }

    func testWhenWaitingTaskIsCancelledThenSubscriptionIsReleased() async {
        let started = expectation(description: "Wait started")
        let publisher = PassthroughSubject<Int, Never>()
        var didCancel = false
        let task = Task {
            await MultiTabAttachmentWaiter.firstValue(
                from: publisher.handleEvents(receiveCancel: { didCancel = true }).eraseToAnyPublisher(),
                timeout: 30, start: { started.fulfill() })
        }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertTrue(didCancel)
    }

    func testWhenTabCollectionIsPendingThenPromptWaitsBeforeConsumingAttachments() async {
        let script = makeTestUserScript()
        let webView = WKWebView()
        let broker = UserScriptMessageBroker(context: "aiChat")
        script.webView = webView
        script.broker = broker
        let started = expectation(description: "Collect started")
        let consumed = expectation(description: "Attachments consumed after push")
        let publisher = PassthroughSubject<[AIChatPageContextData], Never>()
        var didConsume = false
        script.attachedTabContextsProvider = {
            MultiTabAttachmentRequest(collect: {
                await MultiTabAttachmentWaiter.firstValue(
                    from: publisher.eraseToAnyPublisher(), timeout: 1, start: { started.fulfill() }) ?? []
            }, didConsume: {
                didConsume = true
                consumed.fulfill()
            })
        }

        script.submitPrompt("compare")
        await fulfillment(of: [started], timeout: 1)
        XCTAssertFalse(didConsume)
        publisher.send([makeContext().withTabId("other-tab")])
        await fulfillment(of: [consumed], timeout: 1)
        withExtendedLifetime((script, webView, broker)) {}
    }

    func testWhenNewChatStartsDuringCollectionThenOldPromptIsNotConsumed() async {
        let script = makeTestUserScript()
        let webView = WKWebView()
        let broker = UserScriptMessageBroker(context: "aiChat")
        script.webView = webView
        script.broker = broker
        let started = expectation(description: "Collect started")
        let completed = expectation(description: "Collect cancelled")
        let publisher = PassthroughSubject<[AIChatPageContextData], Never>()
        var didConsume = false
        script.attachedTabContextsProvider = {
            MultiTabAttachmentRequest(collect: {
                let result = await MultiTabAttachmentWaiter.firstValue(
                    from: publisher.eraseToAnyPublisher(), timeout: 30, start: { started.fulfill() })
                completed.fulfill()
                return result ?? []
            }, didConsume: { didConsume = true })
        }

        script.submitPrompt("compare")
        await fulfillment(of: [started], timeout: 1)
        script.submitStartChatAction()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertFalse(didConsume)
        withExtendedLifetime((script, webView, broker)) {}
    }
}
