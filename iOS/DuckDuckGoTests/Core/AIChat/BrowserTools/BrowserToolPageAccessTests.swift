//
//  BrowserToolPageAccessTests.swift
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
import XCTest
@testable import DuckDuckGo

@MainActor
final class BrowserToolPageAccessTests: XCTestCase {
    func testSuccessfulReadReleasesReservationAndSubscriptions() async {
        let fixture = BrowserToolPageFixture()
        let result = await fixture.read()
        XCTAssertEqual(result?.content, "body")
        XCTAssertEqual(fixture.acquisitions, 1)
        XCTAssertEqual(fixture.releases, 1)
        XCTAssertEqual(fixture.subscriptions, 0)
    }

    func testMissingStateAndMissingPageReleaseReservation() async {
        for missingState in [false, true] {
            let fixture = BrowserToolPageFixture()
            fixture.hasPage = missingState
            fixture.hasState = false
            let result = await fixture.read()
            XCTAssertNil(result)
            XCTAssertEqual(fixture.releases, 1)
            XCTAssertEqual(fixture.collections, 0)
        }
    }

    func testMissingReservationNeverCollects() async {
        let fixture = BrowserToolPageFixture()
        fixture.canAcquire = false
        let result = await fixture.read()
        XCTAssertNil(result)
        XCTAssertEqual(fixture.collections, 0)
        XCTAssertEqual(fixture.releases, 0)
    }

    func testReadinessTimeoutReleasesWithoutCollecting() async {
        let fixture = BrowserToolPageFixture()
        fixture.loaded = false
        fixture.loading = true
        fixture.isInitialRequestPending = true
        let result = await fixture.read(timeout: 0.01)
        XCTAssertNil(result)
        XCTAssertEqual(fixture.collections, 0)
        XCTAssertEqual(fixture.releases, 1)
        XCTAssertEqual(fixture.subscriptions, 0)
    }

    func testColdAndRestoredPagesSucceedOnFirstReadIncludingRedirects() async {
        for initiallyHasURL in [false, true] {
            let fixture = BrowserToolPageFixture()
            fixture.loaded = false
            fixture.loading = !initiallyHasURL
            fixture.hasURL = initiallyHasURL
            fixture.isInitialRequestPending = true
            let finalURL = URL(string: "https://redirect.example/final")!
            fixture.onLoad = { [weak fixture] in
                guard let fixture else { return }
                fixture.navigation = UUID()
                fixture.target.link = Link(title: "Final", url: finalURL)
                fixture.context = AIChatPageContextData(title: "Final", favicon: [], url: finalURL.absoluteString,
                                                      content: "redirected", truncated: false, fullContentLength: 10)
                fixture.hasURL = true
                fixture.loaded = true
                fixture.loading = false
                fixture.isInitialRequestPending = false
                fixture.changes.send(())
            }
            let result = await fixture.read()
            XCTAssertEqual(result?.content, "redirected")
            XCTAssertEqual(result?.url, finalURL.absoluteString)
            XCTAssertEqual(fixture.acquisitions, 1)
            XCTAssertEqual(fixture.collections, 1)
            XCTAssertEqual(fixture.releases, 1)
            XCTAssertEqual(fixture.subscriptions, 0)
        }
    }

    func testColdPageWaitsForInitialNavigationToFinish() async {
        let fixture = BrowserToolPageFixture()
        fixture.loaded = false
        fixture.loading = true
        fixture.hasURL = false
        fixture.isInitialRequestPending = true
        let loading = expectation(description: "Page observation started")
        fixture.onSubscribe = { loading.fulfill() }
        let task = Task { await fixture.read() }
        await fulfillment(of: [loading], timeout: 1)
        XCTAssertEqual(fixture.collections, 0)
        fixture.navigation = UUID()
        fixture.isInitialRequestPending = false
        fixture.hasURL = true
        fixture.changes.send(())
        XCTAssertEqual(fixture.collections, 0)
        fixture.loading = false
        fixture.loaded = true
        fixture.changes.send(())
        let result = await task.value
        XCTAssertEqual(result?.content, "body")
        XCTAssertEqual(fixture.collections, 1)
        XCTAssertEqual(fixture.releases, 1)
        XCTAssertEqual(fixture.subscriptions, 0)
    }

    func testInvalidationDuringPreparationReleasesWithoutCollecting() async {
        for change in BrowserToolPageFixture.Invalidation.allCases where change != .loading && change != .unattachable {
            let fixture = BrowserToolPageFixture()
            fixture.loaded = false
            fixture.loading = true
            let loading = expectation(description: "Page observation started")
            fixture.onSubscribe = { loading.fulfill() }
            let task = Task { await fixture.read() }
            await fulfillment(of: [loading], timeout: 1)
            fixture.invalidate(change)
            let result = await task.value
            XCTAssertNil(result, "\(change)")
            XCTAssertEqual(fixture.collections, 0, "\(change)")
            XCTAssertEqual(fixture.releases, 1, "\(change)")
            XCTAssertEqual(fixture.subscriptions, 0, "\(change)")
        }
    }

    func testCancellationDuringPreparationReleasesWithoutCollecting() async {
        let fixture = BrowserToolPageFixture()
        fixture.loaded = false
        fixture.loading = true
        fixture.isInitialRequestPending = true
        let loading = expectation(description: "Page observation started")
        fixture.onSubscribe = { loading.fulfill() }
        let task = Task { await fixture.read() }
        await fulfillment(of: [loading], timeout: 1)
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(fixture.collections, 0)
        XCTAssertEqual(fixture.releases, 1)
        XCTAssertEqual(fixture.subscriptions, 0)
    }

    func testUncooperativeCollectorTimeoutReleasesReservation() async {
        let fixture = BrowserToolPageFixture()
        fixture.uncooperative = true
        let task = Task { await fixture.read(timeout: 0.05) }
        await fulfillment(of: [fixture.started], timeout: 1)
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(fixture.releases, 1)
        XCTAssertEqual(fixture.subscriptions, 0)
        fixture.continuation?.resume(returning: .collected(fixture.context))
        fixture.continuation = nil
        await fulfillment(of: [fixture.lateFinished], timeout: 1)
    }

    func testChangesDuringExtractionCancelCollectorAndReleaseExactlyOnce() async {
        for change in BrowserToolPageFixture.Invalidation.allCases {
            let fixture = BrowserToolPageFixture()
            fixture.deferred = true
            let task = Task { await fixture.read() }
            await fulfillment(of: [fixture.started], timeout: 1)
            fixture.invalidate(change)
            let result = await task.value
            XCTAssertNil(result, "\(change)")
            await fulfillment(of: [fixture.cancelled], timeout: 1)
            XCTAssertEqual(fixture.releases, 1, "\(change)")
            XCTAssertEqual(fixture.subscriptions, 0, "\(change)")
            fixture.completion.send(fixture.context)
            XCTAssertEqual(fixture.releases, 1)
        }
    }

    func testOuterCancellationCancelsCollectorAndReleasesReservation() async {
        let fixture = BrowserToolPageFixture()
        fixture.deferred = true
        let task = Task { await fixture.read() }
        await fulfillment(of: [fixture.started], timeout: 1)
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
        await fulfillment(of: [fixture.cancelled], timeout: 1)
        XCTAssertEqual(fixture.releases, 1)
        XCTAssertEqual(fixture.subscriptions, 0)
    }

    func testUncooperativeLateCollectorDoesNotDelayReleaseOrReturnStaleContent() async {
        let fixture = BrowserToolPageFixture()
        fixture.uncooperative = true
        let task = Task { await fixture.read() }
        await fulfillment(of: [fixture.started], timeout: 1)
        fixture.scope.revoke()
        let result = await task.value
        XCTAssertNil(result)
        XCTAssertEqual(fixture.releases, 1)
        XCTAssertEqual(fixture.subscriptions, 0)
        fixture.continuation?.resume(returning: .collected(fixture.context))
        fixture.continuation = nil
        await fulfillment(of: [fixture.lateFinished], timeout: 1)
        XCTAssertEqual(fixture.releases, 1)
    }

    func testAlreadyTerminatedProcessIsNotCollected() async {
        let fixture = BrowserToolPageFixture()
        fixture.terminated = true
        let result = await fixture.read()
        XCTAssertNil(result)
        XCTAssertEqual(fixture.collections, 0)
        XCTAssertEqual(fixture.releases, 1)
    }

    func testWrongURLMetadataOnlyAndUnattachableResultsAreRejected() async {
        for context in [
            AIChatPageContextData(title: "t", favicon: [], url: "https://other.example", content: "body", truncated: false, fullContentLength: 4),
            AIChatPageContextData(title: "t", favicon: [], url: "https://target.example", content: "", truncated: false, fullContentLength: 0),
            AIChatPageContextData(title: "t", favicon: [], url: "https://target.example", content: "body", truncated: false, fullContentLength: 4, attachable: false)
        ] {
            let fixture = BrowserToolPageFixture()
            fixture.context = context
            let result = await fixture.read()
            XCTAssertNil(result)
            XCTAssertEqual(fixture.releases, 1)
        }
    }

    func testDuckAIAndUnattachableOwnerNeverFallBackToSelectedTab() async {
        for url in ["https://duck.ai/chat", "about:blank"] {
            let fixture = BrowserToolPageFixture(ownerURL: url)
            let result = await fixture.reader().pageContext(for: fixture.owner, in: fixture.scope)
            XCTAssertNil(result)
            XCTAssertEqual(fixture.acquisitions, 0)
        }
    }

    func testTargetDefaultsToOwnerAndRejectsForeignContextAndTypes() {
        let fixture = BrowserToolPageFixture()
        let context = BrowserToolCallContext(ownerTabID: fixture.owner.uid, ownerWindowToken: fixture.scope.token, isBurner: false)
        for argument: JSONValue? in [nil, .null, " "] {
            guard case .resolved(let tab) = BrowserToolTargetTab.resolve(tabIDArgument: argument, context: context, scope: fixture.scope) else {
                return XCTFail("Expected owner")
            }
            XCTAssertTrue(tab === fixture.owner)
        }
        let foreign = BrowserToolCallContext(ownerTabID: fixture.owner.uid, ownerWindowToken: "foreign", isBurner: false)
        if case .failure(.unavailable) = BrowserToolTargetTab.resolve(tabIDArgument: nil, context: foreign, scope: fixture.scope) {} else {
            XCTFail("Foreign window accepted")
        }
        if case .failure(.invalidArguments) = BrowserToolTargetTab.resolve(tabIDArgument: true, context: context, scope: fixture.scope) {} else {
            XCTFail("Invalid type accepted")
        }
    }
}

@MainActor
private final class BrowserToolPageFixture {
    enum Invalidation: CaseIterable {
        case navigation, webView, removedTarget, replacedTarget, removedOwner, revoked, terminated, loading, unattachable
    }

    let owner: Tab
    let target = Tab(uid: "target", link: Link(title: "Target", url: URL(string: "https://target.example")!), fireTab: false)
    var tabs: [Tab] = []
    var webView = NSObject()
    var navigation = UUID()
    var isInitialRequestPending = false
    var hasURL = true
    var loaded = true
    var loading = false
    var attachable = true
    var terminated = false
    var hasPage = true
    var hasState = true
    var canAcquire = true
    var deferred = false
    var uncooperative = false
    var continuation: CheckedContinuation<MultiTabAttachmentCollectionResult, Never>?
    let lateFinished = XCTestExpectation(description: "Late collector finished")
    var onLoad: (() -> Void)?
    var onSubscribe: (() -> Void)?
    var acquisitions = 0
    var releases = 0
    var collections = 0
    var subscriptions = 0
    let changes = PassthroughSubject<Void, Never>()
    let terminations = PassthroughSubject<Void, Never>()
    let tabsChanged = PassthroughSubject<[Tab], Never>()
    let completion = PassthroughSubject<AIChatPageContextData, Never>()
    let started = XCTestExpectation(description: "Collection started")
    let cancelled = XCTestExpectation(description: "Collection cancelled")
    var context = AIChatPageContextData(title: "Target", favicon: [], url: "https://target.example", content: "body", truncated: false, fullContentLength: 4)

    init(ownerURL: String = "https://owner.example") {
        owner = Tab(uid: "owner", link: Link(title: "Owner", url: URL(string: ownerURL)!), fireTab: false)
        tabs = [owner, target]
    }

    lazy var scope: BrowserToolScope = {
        let source = MultiTabAttachmentSource(currentTabID: owner.uid, mode: .normal, tabsProvider: { [weak self] in self?.tabs ?? [] },
                                              tabsPublisher: tabsChanged.eraseToAnyPublisher(), pageProvider: { [weak self] _ in
            guard let self, self.hasPage else { return nil }
            return self.page
        }, acquirePage: { [weak self] _ in
            guard let self else { return nil }
            self.acquisitions += 1
            guard self.canAcquire else { return nil }
            return MultiTabAttachmentPage.Reservation { [weak self] in self?.releases += 1 }
        })
        return BrowserToolScope(owner: owner, source: source, selectedTabID: { [weak self] in self?.target.uid })
    }()

    var page: MultiTabAttachmentPage {
        MultiTabAttachmentPage(state: { [self] in
            guard hasState else { return nil }
            return .init(identity: .init(webView: ObjectIdentifier(webView), navigation: navigation), url: hasURL ? target.link?.url : nil,
                         isLoading: loading, isLoaded: loaded, isAttachable: attachable, hasTerminatedProcess: terminated,
                         isInitialRequestPending: isInitialRequestPending)
        }, changes: changes.handleEvents(receiveSubscription: { [self] _ in
            subscriptions += 1
            onSubscribe?()
        },
                                         receiveCancel: { [self] in subscriptions -= 1 }).eraseToAnyPublisher(), collect: { [self] _, isValid in
            collections += 1
            if uncooperative {
                let result = await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    self.started.fulfill()
                }
                lateFinished.fulfill()
                return result
            }
            guard deferred else { return .collected(context) }
            let outcome = await MultiTabAttachmentWaiter.firstValue(from: completion.eraseToAnyPublisher(), timeout: 30) {
                self.started.fulfill()
            }
            if Task.isCancelled { cancelled.fulfill(); return .cancelled }
            guard isValid(), case .value(let value) = outcome else { return .unavailable }
            return .collected(value)
        }, loadIfNeeded: { [self] in onLoad?() }, processTerminations: terminations.eraseToAnyPublisher())
    }

    func reader(timeout: TimeInterval = 1) -> BrowserToolPageContentReader {
        BrowserToolPageContentReader(timeout: timeout)
    }

    func read(timeout: TimeInterval = 1) async -> AIChatPageContextData? {
        await reader(timeout: timeout).pageContext(for: target, in: scope)
    }

    func invalidate(_ change: Invalidation) {
        switch change {
        case .navigation: navigation = UUID(); changes.send(())
        case .webView: webView = NSObject(); changes.send(())
        case .removedTarget: tabs = [owner]; tabsChanged.send(tabs)
        case .replacedTarget:
            tabs = [owner, Tab(uid: target.uid, link: target.link, fireTab: false)]
            tabsChanged.send(tabs)
        case .removedOwner: tabs = [target]; tabsChanged.send(tabs)
        case .revoked: scope.revoke()
        case .terminated: terminated = true; terminations.send(())
        case .loading: loading = true; changes.send(())
        case .unattachable: attachable = false; changes.send(())
        }
    }
}
