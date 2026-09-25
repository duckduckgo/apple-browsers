//
//  MultiTabAttachmentTests.swift
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
import UIKit
import XCTest
import WebKit
@testable import DuckDuckGo

@MainActor
final class MultiTabAttachmentTests: XCTestCase {

    func test_policyCurrentPageAndTwoOthersReachLimit() {
        let policy = policy(attachments: [attachment(id: "one"), attachment(id: "two")], currentPageAttached: true)

        XCTAssertEqual(policy.selectedTabIDs.count, 3)
        XCTAssertFalse(policy.canAttachTab(withID: "three"))
    }

    func test_sourceScopesBothModesAndPreservesSameAddressTabs() {
        let tabs = [tab(id: "normal-one"), tab(id: "fire-one", fire: true), tab(id: "normal-two"), tab(id: "fire-two", fire: true)]
        let normal = MultiTabAttachmentSource(currentTabID: "normal-two", mode: .normal, tabsProvider: { tabs })
        let fire = MultiTabAttachmentSource(currentTabID: "fire-two", mode: .fire, tabsProvider: { tabs })

        XCTAssertEqual(normal.candidates().map(\.tabId), ["normal-two", "normal-one"])
        XCTAssertEqual(fire.candidates().map(\.tabId), ["fire-two", "fire-one"])
    }

    private func attachment(id: TabUID) -> UnifiedToggleInputTabAttachment {
        UnifiedToggleInputTabAttachment(tabId: id, title: "Page", url: URL(string: "https://example.com/page")!)
    }

    private func tab(id: TabUID, fire: Bool = false, lastViewed: Date? = nil) -> Tab {
        Tab(uid: id, link: Link(title: id, url: URL(string: "https://example.com/page")!), lastViewedDate: lastViewed, fireTab: fire)
    }

    private func policy(attachments: [UnifiedToggleInputTabAttachment], currentPageAttached: Bool = false, limit: Int = 3) -> UTIAttachmentPolicy {
        UTIAttachmentPolicy(attachmentLimits: nil, attachmentUsage: nil, pendingAttachments: attachments.map { .tab($0) }, model: nil,
                            maximumTabAttachmentCount: limit, currentPageTabID: "current", isCurrentPageAttached: currentPageAttached)
    }
}

@MainActor
final class MultiTabAttachmentPreparationTests: XCTestCase {
    func testCoordinatorTransfersPreparationBeforeClearingDraft() async throws {
        let fixture = AttachmentPreparationFixture()
        let coordinator = UnifiedToggleInputCoordinator(host: .contextualChat, isToggleEnabled: false,
                                                        preferences: AttachedTabPreferences(), contextualStart: .expandedPreSubmit)
        coordinator.configureTabAttachments(source: fixture.source, feature: fixture.feature)
        let started = expectation(description: "Attachment starts preparation")
        fixture.collect = { [unowned fixture] _ in
            let result = await MultiTabAttachmentWaiter.firstValue(
                from: fixture.results.eraseToAnyPublisher(),
                timeout: 1,
                afterSubscription: {
                    started.fulfill()
                }
            )
            if case .value(let value) = result { return value }
            return .cancelled
        }
        coordinator.viewController.addAttachment(.tab(.init(tabId: fixture.tab.uid, title: "Page", url: fixture.url)))
        await fulfillment(of: [started], timeout: 1)
        let request = try XCTUnwrap(coordinator.takeTabAttachmentRequest())
        coordinator.unifiedToggleInputVCDidChangeAttachments(coordinator.viewController)
        XCTAssertNil(coordinator.takeTabAttachmentRequest(), "A layout notification must not re-create transferred preparation")
        coordinator.clearAttachments()
        XCTAssertEqual(fixture.releaseCount, 0)
        let send = Task { await request.contexts() }
        fixture.results.send(.collected(fixture.pageContext()))
        let contexts = await send.value
        XCTAssertEqual(contexts.map(\.tabId), [fixture.tab.uid])
        XCTAssertEqual(fixture.collectionCount, 1)
        XCTAssertTrue(coordinator.viewController.currentAttachments.isEmpty)
        request.cancel()
        XCTAssertEqual(fixture.releaseCount, 1)
    }

    func testCoordinatorRemovalCancelsWaitingPreparation() async throws {
        let fixture = AttachmentPreparationFixture()
        let coordinator = UnifiedToggleInputCoordinator(host: .contextualChat, isToggleEnabled: false,
                                                        preferences: AttachedTabPreferences(), contextualStart: .expandedPreSubmit)
        coordinator.configureTabAttachments(source: fixture.source, feature: fixture.feature)
        let started = expectation(description: "Preparation started")
        let cancelled = expectation(description: "Removed attachment cancelled")
        fixture.collect = { [unowned fixture] _ in
            let result = await MultiTabAttachmentWaiter.firstValue(
                from: fixture.results.eraseToAnyPublisher(),
                timeout: 1,
                afterSubscription: {
                    started.fulfill()
                }
            )
            if case .cancelled = result { cancelled.fulfill() }
            return .cancelled
        }
        let attachment = UnifiedToggleInputTabAttachment(tabId: fixture.tab.uid, title: "Page", url: fixture.url)
        coordinator.viewController.addAttachment(.tab(attachment))
        await fulfillment(of: [started], timeout: 1)
        coordinator.removeAttachment(id: attachment.id)
        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertNil(coordinator.takeTabAttachmentRequest())
    }

    func testErrorAndTimeoutRetryExactlyOnceAtSend() async throws {
        for outcome in [MultiTabAttachmentCollectionResult.failed, .timedOut] {
            let fixture = AttachmentPreparationFixture()
            fixture.collect = { _ in outcome }
            let preparation = try XCTUnwrap(fixture.prepare())
            let result = await preparation.value()
            XCTAssertNil(result)
            XCTAssertEqual(fixture.collectionCount, 2)
        }
    }

    func testWhenProcessTerminatesThenSendUsesOneRecoveryAttemptWithoutReusingSnapshot() async throws {
        for removesController in [true, false] {
            for failsRecovery in [false, true] {
                let fixture = AttachmentPreparationFixture()
                let preparation = try XCTUnwrap(fixture.prepare())
                defer { preparation.cancel() }
                let prepared = await preparation.value()
                let original = try XCTUnwrap(prepared)

                fixture.terminateProcess(removingPage: removesController)
                preparation.refresh()
                XCTAssertNil(preparation.validated(original))
                XCTAssertEqual(fixture.acquisitionCount, 1)
                XCTAssertEqual(fixture.loadCount, 0)

                fixture.onAcquire = { [unowned fixture] in
                    if !fixture.hasPage { fixture.restorePage() }
                }
                fixture.load = { [unowned fixture] in fixture.restorePage() }
                fixture.collect = { [unowned fixture] _ in
                    failsRecovery ? .failed : .collected(fixture.pageContext(content: "Recovered"))
                }
                let result = await preparation.value()
                XCTAssertEqual(result?.content, failsRecovery ? nil : "Recovered")
                XCTAssertEqual(fixture.acquisitionCount, 2)
                XCTAssertEqual(fixture.collectionCount, 2)
                XCTAssertEqual(fixture.releaseCount, 1)
            }
        }
    }

    func testBrowsingCandidatesDoesNotAcquireOrLoadPages() throws {
        let fixture = AttachmentPreparationFixture()
        fixture.hasPage = false
        let candidates = fixture.source.candidates()
        let picker = MultiTabAttachmentPickerViewModel(candidates: candidates, selectedTabIds: [], attachmentLimit: 3)
        picker.query = "Page"
        let item = try XCTUnwrap(picker.filteredItems.first)
        picker.toggleSelection(for: item)
        XCTAssertEqual(fixture.acquisitionCount, 0)
        XCTAssertEqual(fixture.loadCount, 0)
        XCTAssertEqual(fixture.collectionCount, 0)
    }

    func testUnloadedTabIsAcquiredOnceAndSendWaitsForInitialLoad() async throws {
        let fixture = AttachmentPreparationFixture()
        fixture.hasPage = false
        fixture.isLoaded = false
        fixture.hasPageURL = false
        fixture.onAcquire = { [unowned fixture] in
            fixture.hasPage = true
            fixture.isInitialRequestPending = true
        }
        let preparation = try XCTUnwrap(fixture.prepare())
        defer { preparation.cancel() }
        let waiting = expectation(description: "Waiting for initial request")
        fixture.onNavigationSubscription = { [unowned fixture] in
            fixture.onNavigationSubscription = nil
            waiting.fulfill()
        }
        let send = Task { await preparation.value() }
        await fulfillment(of: [waiting], timeout: 1)
        XCTAssertEqual(fixture.acquisitionCount, 1)
        XCTAssertEqual(fixture.loadCount, 0)
        XCTAssertEqual(fixture.collectionCount, 0)

        fixture.navigationID = UUID()
        fixture.isInitialRequestPending = false
        fixture.hasPageURL = true
        fixture.isLoaded = true
        fixture.changes.send()
        let result = await send.value
        XCTAssertEqual(result?.tabId, fixture.tab.uid)
        XCTAssertEqual(fixture.acquisitionCount, 1)
        XCTAssertEqual(fixture.collectionCount, 1)
        XCTAssertEqual(fixture.releaseCount, 0)
    }

    func testLateResultFromReplacedNavigationCannotReachSend() async throws {
        let fixture = AttachmentPreparationFixture()
        let oldStarted = expectation(description: "Old collection started")
        let replacementStarted = expectation(description: "Replacement collection started")
        var finishOld: CheckedContinuation<MultiTabAttachmentCollectionResult, Never>?
        fixture.collect = { [unowned fixture] _ in
            if fixture.collectionCount > 1 {
                replacementStarted.fulfill()
                return .collected(fixture.pageContext(content: "Replacement"))
            }
            return await withCheckedContinuation { continuation in
                finishOld = continuation
                oldStarted.fulfill()
            }
        }
        let preparation = try XCTUnwrap(fixture.prepare())
        let send = Task { await preparation.value() }
        await fulfillment(of: [oldStarted], timeout: 1)
        fixture.navigationID = UUID()
        fixture.changes.send()
        await fulfillment(of: [replacementStarted], timeout: 1)
        finishOld?.resume(returning: .collected(fixture.pageContext(content: "Old")))
        let context = await send.value
        XCTAssertEqual(context?.content, "Replacement")
        XCTAssertEqual(fixture.collectionCount, 2)
    }

    func testClosedTabRemovesChipAndCannotDeliverPreparedResult() async throws {
        let fixture = AttachmentPreparationFixture()
        let removed = expectation(description: "Closed tab removed")
        let preparation = try XCTUnwrap(fixture.prepare { if $0 == nil { removed.fulfill() } })
        let prepared = await preparation.value()
        let original = try XCTUnwrap(prepared)
        fixture.tabs.send([])
        await fulfillment(of: [removed], timeout: 1)
        XCTAssertNil(preparation.validated(original))
    }

    func testFeatureDisabledAtEntryDoesNotPrepare() {
        let fixture = AttachmentPreparationFixture()
        fixture.feature.state = .unavailable
        XCTAssertNil(fixture.prepare())
        XCTAssertEqual(fixture.acquisitionCount, 0)
        XCTAssertEqual(fixture.collectionCount, 0)
    }

    func testWrongBrowsingModeCannotPrepareEvenIfSourceReturnsTab() {
        let fixture = AttachmentPreparationFixture(mode: .fire)
        XCTAssertNil(fixture.prepare())
        XCTAssertEqual(fixture.collectionCount, 0)
    }

    func testWhenEarlierTabClosesWhileWaitingForLaterTabThenRequestOmitsItsContext() async throws {
        try await assertRequestAfterReceivingFirstContext(expectedContextCount: 1) { first, _ in
            first.tabs.send([])
        }
    }

    func testWhenEarlierPreparationIsCancelledWhileWaitingForLaterTabThenRequestOmitsItsContext() async throws {
        try await assertRequestAfterReceivingFirstContext(expectedContextCount: 1) { _, preparation in
            preparation.cancel()
        }
    }

    private func assertRequestAfterReceivingFirstContext(
        expectedContextCount: Int = 2,
        file: StaticString = #filePath,
        line: UInt = #line,
        change: (AttachmentPreparationFixture, MultiTabAttachmentPreparation) async throws -> Void
    ) async throws {
        let first = AttachmentPreparationFixture()
        let second = AttachmentPreparationFixture()
        let firstPreparation = try XCTUnwrap(first.prepare())
        let prepared = await firstPreparation.value()
        let original = try XCTUnwrap(prepared)
        // Avoid the initial tab-list replay being mistaken for the request reading the second preparation.
        second.source.tabsPublisher = nil
        let secondStarted = expectation(description: "Second collection waiting")
        second.collect = { [unowned second] _ in
            let result = await MultiTabAttachmentWaiter.firstValue(
                from: second.results.eraseToAnyPublisher(),
                timeout: 1,
                afterSubscription: {
                    secondStarted.fulfill()
                }
            )
            if case .value(let context) = result { return context }
            return .cancelled
        }
        let secondPreparation = try XCTUnwrap(second.prepare())
        let request = try XCTUnwrap(first.context.makeRequest(preparations: [firstPreparation, secondPreparation]))
        defer { request.cancel() }
        await fulfillment(of: [secondStarted], timeout: 1)

        // Reading the second preparation's state at Send means the request has already received the first result.
        let receivingSecond = expectation(description: "Request received first context and is waiting for second")
        second.onStateRead = { [unowned second] in
            second.onStateRead = nil
            receivingSecond.fulfill()
        }
        let send = Task { await request.contexts() }
        defer { send.cancel() }
        await fulfillment(of: [receivingSecond], timeout: 1)
        try await change(first, firstPreparation)
        let secondContext = second.pageContext()
        second.results.send(.collected(secondContext))
        let results = await send.value
        let expected = Array([original, secondContext.withTabId(second.tab.uid)].suffix(expectedContextCount))
        XCTAssertEqual(results, expected, file: file, line: line)
        XCTAssertEqual(request.validate(results), expected, file: file, line: line)
    }
}

@MainActor
final class MultiTabAttachmentPageTests: XCTestCase {
    func testWhenProcessTerminatesThenPageInvalidatesBeforeBrowserRecovery() throws {
        let controller = makeController(restored: true)
        let webView = try XCTUnwrap(controller.webView as? AttachmentLoadingWebView)
        let page = try XCTUnwrap(controller.makeMultiTabAttachmentPage())
        let originalIdentity = try XCTUnwrap(page.state()?.identity)
        var notified = false
        let subscription = page.processTerminations.sink {
            notified = true
            XCTAssertEqual(page.state()?.hasTerminatedProcess, true)
            XCTAssertEqual(page.state()?.isLoaded, false)
        }
        defer { subscription.cancel() }

        controller.webViewWebContentProcessDidTerminate(webView)
        XCTAssertTrue(notified)
        XCTAssertNotEqual(page.state()?.identity, originalIdentity)
        XCTAssertEqual(webView.reloadCount, 0)
        page.loadIfNeeded()
        page.loadIfNeeded()
        XCTAssertEqual(webView.reloadCount, 1)
        XCTAssertEqual(webView.stopCount, 0)
    }

    func testReadingRestoredPageDoesNotStartLoading() throws {
        let controller = makeController(restored: true)
        let webView = try XCTUnwrap(controller.webView as? AttachmentLoadingWebView)
        _ = controller.makeMultiTabAttachmentPage()?.state()
        _ = controller.makeMultiTabAttachmentPage()?.state()
        XCTAssertEqual(webView.reloadCount, 0)
        XCTAssertEqual(webView.loadCount, 0)
    }

    private func makeController(restored: Bool, initialRequest: Bool = false) -> TabViewController {
        let url = URL(string: "https://example.com/page")!
        return TabViewController.fake(customWebView: { configuration in
            let webView = AttachmentLoadingWebView(frame: .zero, configuration: configuration)
            webView.restoredURL = restored ? url : nil
            return webView
        }, link: Link(title: "Page", url: url), interactionStateData: restored ? Data() : nil,
        initialRequest: initialRequest ? URLRequest.userInitiated(url) : nil, consumeCookies: initialRequest)
    }
}

private final class AttachmentLoadingWebView: WKWebView {
    var restoredURL: URL?
    private var currentURL: URL?
    var simulatedLoading = false
    private(set) var reloadCount = 0
    private(set) var loadCount = 0
    private(set) var stopCount = 0

    override var url: URL? { currentURL }
    override var isLoading: Bool { simulatedLoading }
    override var interactionState: Any? {
        get { Data() }
        set { currentURL = restoredURL }
    }

    override func reload() -> WKNavigation? {
        reloadCount += 1
        return nil
    }

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadCount += 1
        return nil
    }

    override func stopLoading() {
        stopCount += 1
    }
}

@MainActor
private final class AttachmentPreparationFixture {
    let tab: Tab
    lazy var tabs = CurrentValueSubject<[Tab], Never>([tab])
    let changes = PassthroughSubject<Void, Never>()
    let processTerminations = PassthroughSubject<Void, Never>()
    let results = PassthroughSubject<MultiTabAttachmentCollectionResult, Never>()
    let feature = MutableAttachmentFeature()
    private let pageObject = NSObject()
    var navigationID = UUID()
    var url = URL(string: "https://example.com/page")!
    var isLoading = false
    var isInitialRequestPending = false
    var hasPageURL = true
    var isLoaded = true
    var hasPage = true
    var hasTerminatedProcess = false
    var collectionCount = 0
    var acquisitionCount = 0
    var releaseCount = 0
    var loadCount = 0
    var onAcquire: (() -> Void)?
    var onRelease: (() -> Void)?
    var load: (() -> Void)?
    var collect: ((URL) async -> MultiTabAttachmentCollectionResult)?
    var onNavigationSubscription: (() -> Void)?
    var onStateRead: (() -> Void)?
    let mode: BrowsingMode

    init(mode: BrowsingMode = .normal, fireTab: Bool = false) {
        self.mode = mode
        tab = Tab(uid: UUID().uuidString, link: Link(title: "Page", url: URL(string: "https://example.com/page")!), fireTab: fireTab)
    }

    lazy var source = MultiTabAttachmentSource(currentTabID: "current", mode: mode, tabsProvider: { [unowned self] in self.tabs.value },
                                               tabsPublisher: tabs.eraseToAnyPublisher(), pageProvider: { [unowned self] _ in
        guard self.hasPage else { return nil }
        return MultiTabAttachmentPage(state: { [unowned self] in
            self.onStateRead?()
            return .init(identity: .init(webView: ObjectIdentifier(self.pageObject), navigation: self.navigationID),
                         url: self.hasPageURL ? self.url : nil,
                         isLoading: self.isLoading || self.isInitialRequestPending, isLoaded: self.isLoaded, isAttachable: true,
                         hasTerminatedProcess: self.hasTerminatedProcess)
        }, changes: self.changes.handleEvents(receiveSubscription: { [unowned self] _ in
            self.onNavigationSubscription?()
        }).eraseToAnyPublisher(), collect: { [unowned self] url, isValid in
            guard isValid() else { return .unavailable }
            self.collectionCount += 1
            if let collect = self.collect { return await collect(url) }
            return .collected(self.pageContext())
        }, loadIfNeeded: { [unowned self] in
            guard !self.isLoaded, !self.isLoading, !self.isInitialRequestPending, let load = self.load else { return }
            self.loadCount += 1
            load()
        }, processTerminations: self.processTerminations.eraseToAnyPublisher())
    }, acquirePage: { [unowned self] _ in
        self.acquisitionCount += 1
        self.onAcquire?()
        guard self.hasPage else { return nil }
        return MultiTabAttachmentPage.Reservation { [weak self] in
            self?.releaseCount += 1
            self?.onRelease?()
        }
    })

    lazy var context = MultiTabAttachmentContext(source: source, feature: feature)

    func terminateProcess(removingPage: Bool = true) {
        hasTerminatedProcess = true
        isLoaded = false
        isLoading = false
        isInitialRequestPending = false
        navigationID = UUID()
        processTerminations.send()
        hasPage = !removingPage
        changes.send()
    }

    func restorePage() {
        hasPage = true
        hasTerminatedProcess = false
        isLoaded = true
        isLoading = false
        isInitialRequestPending = false
        navigationID = UUID()
    }

    func prepare(onChange: @escaping (UnifiedToggleInputTabAttachment?) -> Void = { _ in }) -> MultiTabAttachmentPreparation? {
        context.prepare(.init(tabId: tab.uid, title: "Page", url: url), onChange: onChange)
    }

    func pageContext(content: String = "Content") -> AIChatPageContextData {
        AIChatPageContextData(title: "Page", favicon: [], url: url.absoluteString, content: content,
                              truncated: false, fullContentLength: content.count)
    }
}

private final class MutableAttachmentFeature: AIChatContextualAttachMoreTabsFeatureProviding {
    var state: AIChatContextualAttachMoreTabsState = .available(maximumTabAttachmentCount: 3)
}

private final class AttachedTabPreferences: AIChatPreferencesPersisting {
    var selectedReasoningEffort: String?
    var selectedModelId: String?
    var selectedModelShortName: String?
    var selectedReasoningMode: AIChatReasoningMode?
    var selectedTool: AIChatRAGTool?
    var selectedModelIdPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
    var selectedReasoningEffortPublisher: AnyPublisher<String?, Never> { Empty().eraseToAnyPublisher() }
}
