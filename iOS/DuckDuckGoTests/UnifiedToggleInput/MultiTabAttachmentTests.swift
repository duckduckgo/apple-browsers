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

    func test_tabModelKeepsAttachmentIdentitySeparateFromTabIdentity() {
        let first = attachment(id: "one")
        let reattached = attachment(id: "one")
        let other = attachment(id: "two")

        XCTAssertNotEqual(first.id, reattached.id)
        XCTAssertEqual(first.tabId, reattached.tabId)
        XCTAssertNotEqual(first.tabId, other.tabId)
        XCTAssertEqual(first.url, other.url)
    }

    func test_tabMetadataDoesNotBecomeAnImageOrFilePayload() {
        let tab = UnifiedToggleInputAttachment.tab(attachment(id: "one"))

        XCTAssertEqual(tab.fileName, "Page")
        XCTAssertEqual(tab.fileSizeBytes, 0)
        XCTAssertNil(tab.mimeType)
        XCTAssertFalse(tab.isImage)
        XCTAssertFalse(tab.isFile)
        XCTAssertNil(UnifiedToggleInputImageEncoder.encode([tab]))
        XCTAssertNil(UnifiedToggleInputFileEncoder.encode([tab]))
    }

    func test_policyCountsDistinctSourceTabsIncludingPendingCurrentPage() {
        let policy = policy(attachments: [attachment(id: "current"), attachment(id: "other"), attachment(id: "other")],
                            currentPageAttached: true)

        XCTAssertEqual(policy.selectedTabIDs, ["current", "other"])
        XCTAssertFalse(policy.canAttachTab(withID: "other"))
        XCTAssertTrue(policy.canAttachTab(withID: "third"))
    }

    func test_policyCurrentPageAndTwoOthersReachLimit() {
        let policy = policy(attachments: [attachment(id: "one"), attachment(id: "two")], currentPageAttached: true)

        XCTAssertEqual(policy.selectedTabIDs.count, 3)
        XCTAssertFalse(policy.canAttachTab(withID: "three"))
    }

    func test_policyDeliveredCurrentPageDoesNotReserveSlot() {
        let policy = policy(attachments: [attachment(id: "one"), attachment(id: "two")])

        XCTAssertEqual(policy.selectedTabIDs.count, 2)
        XCTAssertTrue(policy.canAttachTab(withID: "current"))
    }

    func test_policyUsesConfiguredLimitAndDisablesAddingWhenUnavailable() {
        var policy = policy(attachments: [attachment(id: "one")], limit: 1)
        XCTAssertFalse(policy.canAttachTab(withID: "two"))
        policy.maximumTabAttachmentCount = 2
        XCTAssertTrue(policy.canAttachTab(withID: "two"))
        policy.maximumTabAttachmentCount = nil
        XCTAssertFalse(policy.canAttachTab(withID: "two"))
    }

    func test_policyTabContextDoesNotRequireUploadCapability() {
        let policy = policy(attachments: [], limit: 3)
        XCTAssertTrue(policy.isAttachmentSupported(.tab(attachment(id: "one"))))
    }

    func test_sourceScopesBothModesAndPreservesSameAddressTabs() {
        let tabs = [tab(id: "normal-one"), tab(id: "fire-one", fire: true), tab(id: "normal-two"), tab(id: "fire-two", fire: true)]
        let normal = MultiTabAttachmentSource(currentTabID: "normal-two", mode: .normal, tabsProvider: { tabs })
        let fire = MultiTabAttachmentSource(currentTabID: "fire-two", mode: .fire, tabsProvider: { tabs })

        XCTAssertEqual(normal.candidates().map(\.tabId), ["normal-two", "normal-one"])
        XCTAssertEqual(fire.candidates().map(\.tabId), ["fire-two", "fire-one"])
    }

    func test_sourceFiltersIneligiblePagesAndDeduplicatesIdentity() {
        let page = tab(id: "page")
        let empty = Tab(uid: "empty", fireTab: false)
        let chat = Tab(uid: "chat", link: Link(title: "Duck.ai", url: URL(string: "https://duck.ai/")!), fireTab: false)
        let source = MultiTabAttachmentSource(currentTabID: "empty", mode: .normal, tabsProvider: { [empty, page, page, chat] })

        XCTAssertEqual(source.candidates().map(\.tabId), ["page"])
    }

    func test_sourcePinsCurrentTabThenSortsByRecencyWithStableTies() {
        let current = tab(id: "current", lastViewed: Date(timeIntervalSince1970: 1))
        let recent = tab(id: "recent", lastViewed: Date(timeIntervalSince1970: 20))
        let tied = tab(id: "tied", lastViewed: Date(timeIntervalSince1970: 20))
        let unknown = tab(id: "unknown")
        let source = MultiTabAttachmentSource(currentTabID: "current", mode: .normal, tabsProvider: { [unknown, recent, tied, current] })

        XCTAssertEqual(source.candidates().map(\.tabId), ["current", "recent", "tied", "unknown"])
    }

    func test_sourceRereadsModelsWhenTabsAreClosed() {
        var tabs = [tab(id: "one"), tab(id: "two")]
        let source = MultiTabAttachmentSource(currentTabID: "one", mode: .normal, tabsProvider: { tabs })
        XCTAssertEqual(source.candidates().count, 2)
        tabs.removeFirst()
        XCTAssertEqual(source.candidates().map(\.tabId), ["two"])
    }

    func test_pickerStagesSelectionAndAllowsReplacementAtCapacity() throws {
        let source = MultiTabAttachmentSource(currentTabID: "current", mode: .normal,
                                              tabsProvider: { [self.tab(id: "current"), self.tab(id: "other")] })
        let initial: Set<TabUID> = ["current"]
        let picker = MultiTabAttachmentPickerViewModel(candidates: source.candidates(), selectedTabIds: initial, attachmentLimit: 1)
        let current = try XCTUnwrap(picker.items.first { $0.id == "current" })
        let other = try XCTUnwrap(picker.items.first { $0.id == "other" })

        XCTAssertTrue(picker.isEnabled(current))
        XCTAssertFalse(picker.isEnabled(other))
        picker.toggleSelection(for: other)
        XCTAssertEqual(picker.selectedTabIds, initial)
        picker.toggleSelection(for: current)
        XCTAssertTrue(picker.isEnabled(other))
        picker.toggleSelection(for: other)
        XCTAssertEqual(picker.selectedTabIds, ["other"])
    }

    func test_pickerSearchRetainsSelectionOutsideResults() {
        let candidate = MultiTabAttachmentCandidate(tabId: "one", title: "Selected page", url: URL(string: "https://example.com")!)
        let picker = MultiTabAttachmentPickerViewModel(candidates: [candidate], selectedTabIds: ["one"], attachmentLimit: 3)
        picker.query = "no matching page"

        XCTAssertTrue(picker.filteredItems.isEmpty)
        XCTAssertEqual(picker.selectedTabIds, ["one"])
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
final class MultiTabAttachmentWaiterTests: XCTestCase {
    func testWhenStartEmitsSynchronouslyThenReturnsFirstValue() async {
        let subject = PassthroughSubject<Int, Never>()

        let result = await MultiTabAttachmentWaiter.firstValue(
            from: subject.eraseToAnyPublisher(),
            timeout: 1,
            afterSubscription: {
                subject.send(42)
                subject.send(99)
            }
        )

        guard case .value(let value) = result else {
            XCTFail("Expected the first published value")
            return
        }
        XCTAssertEqual(value, 42)
    }

    func testWhenPublisherCompletesWithoutValueThenReturnsFinished() async {
        let publisher = Empty<Int, Never>().eraseToAnyPublisher()

        let result = await MultiTabAttachmentWaiter.firstValue(from: publisher, timeout: 1)

        guard case .finished = result else {
            XCTFail("Expected publisher completion without a value")
            return
        }
    }

    func testWhenTimeoutExpiresThenReturnsTimedOutAndCancelsSubscription() async {
        let subject = PassthroughSubject<Int, Never>()
        let cancelled = expectation(description: "Subscription cancelled on timeout")
        let publisher = subject.handleEvents(receiveCancel: { cancelled.fulfill() }).eraseToAnyPublisher()

        let result = await MultiTabAttachmentWaiter.firstValue(from: publisher, timeout: 0)

        guard case .timedOut = result else {
            XCTFail("Expected timeout")
            return
        }
        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testWhenTaskIsCancelledThenReturnsCancelledAndCancelsSubscription() async {
        let subject = PassthroughSubject<Int, Never>()
        let started = expectation(description: "Collection started")
        let cancelled = expectation(description: "Subscription cancelled with task")
        let publisher = subject.handleEvents(receiveCancel: { cancelled.fulfill() }).eraseToAnyPublisher()
        let task = Task { @MainActor in
            await MultiTabAttachmentWaiter.firstValue(
                from: publisher,
                timeout: 60,
                afterSubscription: {
                    started.fulfill()
                }
            )
        }
        defer { task.cancel() }
        await fulfillment(of: [started], timeout: 1)

        task.cancel()
        let result = await task.value

        guard case .cancelled = result else {
            XCTFail("Expected cancellation")
            return
        }
        await fulfillment(of: [cancelled], timeout: 1)
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

    func testPreparedResultIsReusedAtSend() async throws {
        let fixture = AttachmentPreparationFixture()
        let preparation = try XCTUnwrap(fixture.prepare())
        let prepared = await preparation.value()
        let request = try XCTUnwrap(fixture.context.makeRequest(preparations: [preparation]))
        let sent = await request.contexts()
        XCTAssertEqual(sent, [try XCTUnwrap(prepared)])
        XCTAssertEqual(fixture.collectionCount, 1)
        request.didConsume()
        let cancelledResult = await preparation.value()
        XCTAssertNil(cancelledResult)
    }

    func testSendWaitsForExistingPreparationWithoutDuplicatingCollection() async throws {
        let fixture = AttachmentPreparationFixture()
        let started = expectation(description: "Preparation started")
        fixture.collect = { [unowned fixture] _ in
            let result = await MultiTabAttachmentWaiter.firstValue(
                from: fixture.results.eraseToAnyPublisher(),
                timeout: 1,
                afterSubscription: {
                    started.fulfill()
                }
            )
            if case .value(let context) = result { return context }
            return .cancelled
        }
        let preparation = try XCTUnwrap(fixture.prepare())
        await fulfillment(of: [started], timeout: 1)
        let send = Task { await preparation.value() }
        fixture.results.send(.collected(fixture.pageContext()))
        let result = await send.value
        XCTAssertEqual(result?.tabId, fixture.tab.uid)
        XCTAssertEqual(fixture.collectionCount, 1)
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

    func testSendRetriesFailureOfPreparationItWasAwaiting() async throws {
        let fixture = AttachmentPreparationFixture()
        let started = expectation(description: "First collection started")
        fixture.collect = { [unowned fixture] _ in
            if fixture.collectionCount > 1 { return .collected(fixture.pageContext()) }
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
        let preparation = try XCTUnwrap(fixture.prepare())
        let send = Task { await preparation.value() }
        await fulfillment(of: [started], timeout: 1)
        fixture.results.send(.failed)
        let result = await send.value
        XCTAssertEqual(result?.tabId, fixture.tab.uid)
        XCTAssertEqual(fixture.collectionCount, 2)
    }

    func testEmptyUnavailableAndCancelledDoNotRetry() async throws {
        for outcome in [MultiTabAttachmentCollectionResult.empty, .unavailable, .cancelled] {
            let fixture = AttachmentPreparationFixture()
            fixture.collect = { _ in outcome }
            let preparation = try XCTUnwrap(fixture.prepare())
            let result = await preparation.value()
            XCTAssertNil(result)
            XCTAssertEqual(fixture.collectionCount, 1)
        }
    }

    func testSourceWithoutPageKeepsChipWithoutCollectingOrRetrying() async throws {
        let fixture = AttachmentPreparationFixture()
        fixture.hasPage = false
        var removed = false
        let preparation = try XCTUnwrap(fixture.prepare { removed = $0 == nil })
        let result = await preparation.value()
        XCTAssertNil(result)
        XCTAssertFalse(removed)
        XCTAssertEqual(fixture.collectionCount, 0)
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

    func testWhenProcessTerminatesDuringExtractionRetryThenNoAdditionalRecoveryStarts() async throws {
        let fixture = AttachmentPreparationFixture()
        let preparation = try XCTUnwrap(fixture.prepare())
        defer { preparation.cancel() }
        fixture.collect = { [unowned fixture] _ in
            if fixture.collectionCount == 1 { return .failed }
            fixture.terminateProcess()
            return .collected(fixture.pageContext(content: "Invalidated"))
        }
        let result = await preparation.value()
        XCTAssertNil(result)
        XCTAssertEqual(fixture.collectionCount, 2)
        XCTAssertEqual(fixture.acquisitionCount, 1)
    }

    func testWhenSourceIsRemovedDuringRecoveryThenLateContextIsNotDelivered() async throws {
        for mode in [BrowsingMode.normal, .fire] {
            let fixture = AttachmentPreparationFixture(mode: mode, fireTab: mode == .fire)
            let preparation = try XCTUnwrap(fixture.prepare())
            _ = await preparation.value()
            fixture.terminateProcess()
            preparation.refresh()
            fixture.onAcquire = { [unowned fixture] in fixture.restorePage() }
            let started = expectation(description: "Recovery collection started")
            var finish: CheckedContinuation<MultiTabAttachmentCollectionResult, Never>?
            fixture.collect = { _ in
                await withCheckedContinuation { continuation in
                    finish = continuation
                    started.fulfill()
                }
            }
            let request = try XCTUnwrap(fixture.context.makeRequest(preparations: [preparation]))
            defer { request.cancel() }
            let send = Task { await request.contexts() }
            await fulfillment(of: [started], timeout: 1)
            fixture.tabs.send([])
            finish?.resume(returning: .collected(fixture.pageContext()))
            let contexts = await send.value
            XCTAssertTrue(contexts.isEmpty)
            XCTAssertTrue(request.validate([fixture.pageContext().withTabId(fixture.tab.uid)]).isEmpty)
            XCTAssertEqual(fixture.acquisitionCount, 2)
        }
    }

    func testWhenBrowserRestoresPageThenObserverResumesPreparationWithNewBudgetAndProtection() async throws {
        let fixture = AttachmentPreparationFixture()
        fixture.isLoading = true
        fixture.isLoaded = false
        var time: TimeInterval = 0
        let preparation = MultiTabAttachmentPreparation(
            attachment: .init(tabId: fixture.tab.uid, title: "Page", url: fixture.url),
            tab: fixture.tab, source: fixture.source, now: { time }, isEnabled: { true }, onChange: { _ in })
        defer { preparation.cancel() }
        fixture.terminateProcess()
        preparation.refresh()
        time = 10

        let collected = expectation(description: "Browser recovery prepares context before Send")
        fixture.collect = { [unowned fixture] _ in
            collected.fulfill()
            return .collected(fixture.pageContext(content: "Restored"))
        }
        fixture.restorePage()
        fixture.tab.viewed = true
        await fulfillment(of: [collected], timeout: 1)
        XCTAssertEqual(fixture.acquisitionCount, 2)
        XCTAssertEqual(fixture.releaseCount, 1)
        let result = await preparation.value()
        XCTAssertEqual(result?.content, "Restored")
        XCTAssertEqual(fixture.collectionCount, 1)
        XCTAssertEqual(fixture.loadCount, 0)
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

    func testRestoredIdlePageStartsLoadingOnceAfterSubscription() async throws {
        let fixture = AttachmentPreparationFixture()
        fixture.isLoaded = false
        var subscribed = false
        fixture.onNavigationSubscription = { subscribed = true }
        fixture.load = { [unowned fixture] in
            XCTAssertTrue(subscribed)
            fixture.isLoading = true
            fixture.navigationID = UUID()
            fixture.changes.send()
        }
        let preparation = try XCTUnwrap(fixture.prepare())
        defer { preparation.cancel() }
        preparation.refresh()
        XCTAssertEqual(fixture.loadCount, 1)
        fixture.isLoading = false
        fixture.isLoaded = true
        fixture.changes.send()
        let result = await preparation.value()
        XCTAssertNotNil(result)
        XCTAssertEqual(fixture.loadCount, 1)
        XCTAssertEqual(fixture.collectionCount, 1)
    }

    func testAcquisitionTimeConsumesInitialNavigationBudget() async {
        let fixture = AttachmentPreparationFixture()
        var time: TimeInterval = 0
        fixture.onAcquire = { time = 6 }
        fixture.collect = { _ in .failed }
        let preparation = MultiTabAttachmentPreparation(
            attachment: .init(tabId: fixture.tab.uid, title: "Page", url: fixture.url),
            tab: fixture.tab, source: fixture.source, now: { time }, isEnabled: { true }, onChange: { _ in })
        defer { preparation.cancel() }
        let result = await preparation.value()
        XCTAssertNil(result)
        // Initial preparation timed out before extraction; only the existing Send retry collects.
        XCTAssertEqual(fixture.collectionCount, 1)
        XCTAssertEqual(fixture.acquisitionCount, 1)
    }

    func testFirstNavigationDoesNotResetInitialBudget() async throws {
        let fixture = AttachmentPreparationFixture()
        fixture.isInitialRequestPending = true
        fixture.isLoaded = false
        var time: TimeInterval = 0
        fixture.collect = { _ in .failed }
        let preparation = MultiTabAttachmentPreparation(
            attachment: .init(tabId: fixture.tab.uid, title: "Page", url: fixture.url),
            tab: fixture.tab, source: fixture.source, now: { time }, isEnabled: { true }, onChange: { _ in })
        defer { preparation.cancel() }
        time = 6
        fixture.navigationID = UUID()
        fixture.isInitialRequestPending = false
        fixture.isLoaded = true
        preparation.refresh()
        let result = await preparation.value()
        XCTAssertNil(result)
        XCTAssertEqual(fixture.collectionCount, 1, "Only the Send retry may collect after the initial budget expired")
    }

    func testReadyPreparationRetainsReservationUntilCancelled() async throws {
        let fixture = AttachmentPreparationFixture()
        let preparation = try XCTUnwrap(fixture.prepare())
        _ = await preparation.value()
        XCTAssertEqual(fixture.acquisitionCount, 1)
        XCTAssertEqual(fixture.releaseCount, 0)
        preparation.cancel()
        preparation.cancel()
        XCTAssertEqual(fixture.releaseCount, 1)
    }

    func testOwnerTeardownReleasesReservation() async throws {
        let fixture = AttachmentPreparationFixture()
        let released = expectation(description: "Reservation released after owner teardown")
        fixture.onRelease = { released.fulfill() }
        var preparation = fixture.prepare()
        XCTAssertNotNil(preparation)
        _ = await preparation?.value()
        preparation = nil
        await fulfillment(of: [released], timeout: 1)
        XCTAssertEqual(fixture.releaseCount, 1)
    }

    func testCancellingInitialLoadReleasesReservationWithoutAnotherLoad() throws {
        let fixture = AttachmentPreparationFixture()
        fixture.isLoaded = false
        fixture.isInitialRequestPending = true
        let preparation = try XCTUnwrap(fixture.prepare())
        preparation.cancel()
        XCTAssertEqual(fixture.releaseCount, 1)
        XCTAssertEqual(fixture.loadCount, 0)
        XCTAssertEqual(fixture.collectionCount, 0)
    }

    func testExistingNavigationFinishesBeforeCollectionStarts() async throws {
        let fixture = AttachmentPreparationFixture()
        fixture.isLoading = true
        fixture.isLoaded = false
        let preparation = try XCTUnwrap(fixture.prepare())
        let waiting = expectation(description: "Waiting for navigation")
        fixture.onNavigationSubscription = { waiting.fulfill() }
        let send = Task { await preparation.value() }
        await fulfillment(of: [waiting], timeout: 1)
        XCTAssertEqual(fixture.collectionCount, 0)
        fixture.isLoading = false
        fixture.isLoaded = true
        fixture.changes.send()
        let result = await send.value
        XCTAssertNotNil(result)
        XCTAssertEqual(fixture.collectionCount, 1)
    }

    func testSameAddressNavigationInvalidatesPreparedResult() async throws {
        let fixture = AttachmentPreparationFixture()
        let preparation = try XCTUnwrap(fixture.prepare())
        let prepared = await preparation.value()
        let original = try XCTUnwrap(prepared)
        let operation = preparation.operationID
        fixture.navigationID = UUID()
        fixture.collect = { [unowned fixture] _ in .collected(fixture.pageContext(content: "Replacement")) }
        XCTAssertNil(preparation.validated(original))
        preparation.refresh()
        let replacement = await preparation.value()
        XCTAssertNotEqual(preparation.operationID, operation)
        XCTAssertEqual(replacement?.content, "Replacement")
        XCTAssertEqual(fixture.collectionCount, 2)
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

    func testEligibleNavigationUpdatesChipWithoutDependingOnAutoAttachSetting() async throws {
        let fixture = AttachmentPreparationFixture()
        let changed = expectation(description: "Attachment metadata follows source")
        let nextURL = URL(string: "https://example.com/next")!
        let preparation = try XCTUnwrap(fixture.prepare { updated in
            if updated?.url == nextURL { changed.fulfill() }
        })
        _ = await preparation.value()
        fixture.url = nextURL
        fixture.navigationID = UUID()
        fixture.tab.link = Link(title: "Next page", url: nextURL)
        await fulfillment(of: [changed], timeout: 1)
        let context = await preparation.value()
        XCTAssertEqual(preparation.attachment.title, "Next page")
        XCTAssertEqual(context?.url, nextURL.absoluteString)
        XCTAssertEqual(fixture.collectionCount, 2)
    }

    func testNavigationTimeoutDoesNotStartExtraction() async {
        let fixture = AttachmentPreparationFixture()
        fixture.isLoading = true
        fixture.isLoaded = false
        let preparation = MultiTabAttachmentPreparation(attachment: .init(tabId: fixture.tab.uid, title: "Page", url: fixture.url),
                                                         tab: fixture.tab, source: fixture.source, navigationTimeout: 0,
                                                         isEnabled: { true }, onChange: { _ in })
        let result = await preparation.value()
        XCTAssertNil(result)
        XCTAssertEqual(fixture.collectionCount, 0)
    }

    func testFlagDisabledWhileCollectingPreventsRetryAndDelivery() async throws {
        let fixture = AttachmentPreparationFixture()
        let started = expectation(description: "Collection started")
        fixture.collect = { [unowned fixture] _ in
            let result = await MultiTabAttachmentWaiter.firstValue(
                from: fixture.results.eraseToAnyPublisher(),
                timeout: 1,
                afterSubscription: {
                    started.fulfill()
                }
            )
            if case .value(let result) = result { return result }
            return .cancelled
        }
        let preparation = try XCTUnwrap(fixture.prepare())
        let request = try XCTUnwrap(fixture.context.makeRequest(preparations: [preparation]))
        let send = Task { await request.contexts() }
        await fulfillment(of: [started], timeout: 1)
        fixture.feature.state = .unavailable
        fixture.results.send(.failed)
        let contexts = await send.value
        XCTAssertTrue(contexts.isEmpty)
        XCTAssertEqual(fixture.collectionCount, 1)
        request.cancel()
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

    func testNavigationToIneligibleDestinationRemovesChip() async throws {
        let fixture = AttachmentPreparationFixture()
        var removed = false
        let preparation = try XCTUnwrap(fixture.prepare { removed = $0 == nil })
        fixture.url = URL(string: "https://duck.ai/")!
        preparation.refresh()
        XCTAssertTrue(removed)
        let cancelledResult = await preparation.value()
        XCTAssertNil(cancelledResult)
    }

    func testRemovingAndReattachingDoesNotReuseOldOperation() async throws {
        let fixture = AttachmentPreparationFixture()
        let oldStarted = expectation(description: "Old collection started")
        let replacementStarted = expectation(description: "Reattached collection started")
        var finishOld: CheckedContinuation<MultiTabAttachmentCollectionResult, Never>?
        var finishReplacement: CheckedContinuation<MultiTabAttachmentCollectionResult, Never>?
        fixture.collect = { [unowned fixture] _ in
            await withCheckedContinuation { continuation in
                if fixture.collectionCount == 1 {
                    finishOld = continuation
                    oldStarted.fulfill()
                } else {
                    finishReplacement = continuation
                    replacementStarted.fulfill()
                }
            }
        }
        let first = try XCTUnwrap(fixture.prepare())
        let oldResult = Task { await first.value() }
        await fulfillment(of: [oldStarted], timeout: 1)
        first.cancel()
        let second = try XCTUnwrap(fixture.prepare())
        await fulfillment(of: [replacementStarted], timeout: 1)

        // Ignore cancellation in the collector so the old native operation can finish after reattachment.
        finishOld?.resume(returning: .collected(fixture.pageContext(content: "Removed")))
        let removedContext = await oldResult.value
        XCTAssertNil(removedContext)

        finishReplacement?.resume(returning: .collected(fixture.pageContext(content: "Reattached")))
        let request = try XCTUnwrap(fixture.context.makeRequest(preparations: [second]))
        defer { request.cancel() }
        let contexts = await request.contexts()
        XCTAssertEqual(contexts, [fixture.pageContext(content: "Reattached").withTabId(fixture.tab.uid)])
        XCTAssertNotEqual(first.attachment.id, second.attachment.id)
        XCTAssertEqual(fixture.collectionCount, 2)
    }

    func testFeatureDisabledAtEntryDoesNotPrepare() {
        let fixture = AttachmentPreparationFixture()
        fixture.feature.state = .unavailable
        XCTAssertNil(fixture.prepare())
        XCTAssertEqual(fixture.acquisitionCount, 0)
        XCTAssertEqual(fixture.collectionCount, 0)
    }

    func testFireSourceCollectsItsOwnFireTab() async throws {
        let fixture = AttachmentPreparationFixture(mode: .fire, fireTab: true)
        let preparation = try XCTUnwrap(fixture.prepare())
        let context = await preparation.value()
        XCTAssertEqual(context?.tabId, fixture.tab.uid)
        XCTAssertEqual(fixture.collectionCount, 1)
    }

    func testWrongBrowsingModeCannotPrepareEvenIfSourceReturnsTab() {
        let fixture = AttachmentPreparationFixture(mode: .fire)
        XCTAssertNil(fixture.prepare())
        XCTAssertEqual(fixture.collectionCount, 0)
    }

    func testWhenEarlierTabReloadsWhileWaitingForLaterTabThenRequestKeepsReceivedContext() async throws {
        try await assertRequestAfterReceivingFirstContext { first, preparation in
            first.navigationID = UUID()
            first.isLoading = true
            first.isLoaded = false
            preparation.refresh()
        }
    }

    func testWhenEarlierTabNavigatesWhileWaitingForLaterTabThenRequestKeepsReceivedContext() async throws {
        try await assertRequestAfterReceivingFirstContext { first, preparation in
            first.navigationID = UUID()
            first.url = try XCTUnwrap(URL(string: "https://example.com/another-article"))
            first.tab.link = Link(title: "Another article", url: first.url)
            first.isLoading = true
            first.isLoaded = false
            preparation.refresh()
        }
    }

    func testWhenReplacementContextFinishesWhileWaitingForLaterTabThenRequestKeepsReceivedContext() async throws {
        try await assertRequestAfterReceivingFirstContext { first, preparation in
            first.navigationID = UUID()
            first.url = try XCTUnwrap(URL(string: "https://example.com/another-article"))
            first.tab.link = Link(title: "Another article", url: first.url)
            first.collect = { [unowned first] _ in .collected(first.pageContext(content: "Replacement")) }
            preparation.refresh()
            let replacement = await preparation.value()
            XCTAssertEqual(replacement?.content, "Replacement")
        }
    }

    func testWhenEarlierTabClosesWhileWaitingForLaterTabThenRequestOmitsItsContext() async throws {
        try await assertRequestAfterReceivingFirstContext(expectedContextCount: 1) { first, _ in
            first.tabs.send([])
        }
    }

    func testWhenEarlierProcessTerminatesWhileWaitingForLaterTabThenRequestKeepsReceivedContext() async throws {
        try await assertRequestAfterReceivingFirstContext { first, preparation in
            first.terminateProcess()
            preparation.refresh()
            XCTAssertEqual(first.acquisitionCount, 1)
        }
    }

    func testWhenEarlierTabBecomesIneligibleWhileWaitingForLaterTabThenRequestOmitsItsContext() async throws {
        try await assertRequestAfterReceivingFirstContext(expectedContextCount: 1) { first, _ in
            first.url = try XCTUnwrap(URL(string: "https://duck.ai/"))
        }
    }

    func testWhenEarlierPreparationIsCancelledWhileWaitingForLaterTabThenRequestOmitsItsContext() async throws {
        try await assertRequestAfterReceivingFirstContext(expectedContextCount: 1) { _, preparation in
            preparation.cancel()
        }
    }

    func testWhenFeatureIsDisabledWhileWaitingForLaterTabThenRequestOmitsAllContexts() async throws {
        try await assertRequestAfterReceivingFirstContext(expectedContextCount: 0) { first, _ in
            first.feature.state = .unavailable
        }
    }

    func testWhenTabIsReattachedWhileWaitingForLaterTabThenRequestKeepsItsOriginalPreparation() async throws {
        try await assertRequestAfterReceivingFirstContext { first, preparation in
            first.collect = { [unowned first] _ in .collected(first.pageContext(content: "Reattached")) }
            let reattached = try XCTUnwrap(first.prepare())
            defer { reattached.cancel() }
            XCTAssertNotEqual(reattached.attachment.id, preparation.attachment.id)
            let replacement = await reattached.value()
            XCTAssertEqual(replacement?.content, "Reattached")
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

    func testRestoredDocumentReloadsOnlyOnce() throws {
        let controller = makeController(restored: true)
        let webView = try XCTUnwrap(controller.webView as? AttachmentLoadingWebView)
        let page = try XCTUnwrap(controller.makeMultiTabAttachmentPage())
        XCTAssertEqual(page.state()?.isLoaded, false)
        page.loadIfNeeded()
        page.loadIfNeeded()
        XCTAssertEqual(webView.reloadCount, 1)
        XCTAssertEqual(webView.stopCount, 0)
    }

    func testRestoredDocumentAlreadyLoadingIsNotReloaded() throws {
        let controller = makeController(restored: true)
        let webView = try XCTUnwrap(controller.webView as? AttachmentLoadingWebView)
        webView.simulatedLoading = true
        let page = try XCTUnwrap(controller.makeMultiTabAttachmentPage())
        page.loadIfNeeded()
        XCTAssertEqual(page.state()?.isLoading, true)
        XCTAssertEqual(webView.reloadCount, 0)
    }

    func testPendingInitialRequestCountsAsLoadingBeforeWebKitStarts() throws {
        let controller = makeController(restored: false, initialRequest: true)
        let webView = try XCTUnwrap(controller.webView as? AttachmentLoadingWebView)
        let page = try XCTUnwrap(controller.makeMultiTabAttachmentPage())
        XCTAssertNil(webView.url)
        XCTAssertFalse(webView.isLoading)
        XCTAssertEqual(page.state()?.isLoading, true)
        page.loadIfNeeded()
        XCTAssertEqual(webView.reloadCount, 0)
    }

    func testReadingRestoredPageDoesNotStartLoading() throws {
        let controller = makeController(restored: true)
        let webView = try XCTUnwrap(controller.webView as? AttachmentLoadingWebView)
        _ = controller.makeMultiTabAttachmentPage()?.state()
        _ = controller.makeMultiTabAttachmentPage()?.state()
        XCTAssertEqual(webView.reloadCount, 0)
        XCTAssertEqual(webView.loadCount, 0)
    }

    func testPreparationCancellationDoesNotStopBrowserLoad() throws {
        let controller = makeController(restored: true)
        let webView = try XCTUnwrap(controller.webView as? AttachmentLoadingWebView)
        webView.simulatedLoading = true
        let tab = controller.tabModel
        let source = MultiTabAttachmentSource(currentTabID: "other", mode: .normal, tabsProvider: { [tab] },
                                               pageProvider: { _ in controller.makeMultiTabAttachmentPage() })
        let context = MultiTabAttachmentContext(source: source, feature: MutableAttachmentFeature())
        let preparation = try XCTUnwrap(context.prepare(.init(tabId: tab.uid, title: "Page", url: try XCTUnwrap(tab.link?.url)),
                                                       onChange: { _ in }))
        preparation.cancel()
        XCTAssertEqual(webView.stopCount, 0)
        XCTAssertTrue(webView.isLoading)
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
