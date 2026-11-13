//
//  DefaultBrowserWinBackPromoDelegateTests.swift
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

import Combine
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DefaultBrowserWinBackPromoDelegateTests: XCTestCase {

    private var actionPerformer: MockDefaultBrowserAndDockActionPerformer!
    private var churnState: MockUserChurnStateProvider!
    private var promptStore: MockDefaultBrowserAndDockPromptStore!
    private var uiHosting: MockDefaultBrowserAndDockPromptUIHosting!
    private var modal: MockDefaultBrowserAndDockPromptModal!
    private var confirmationMonitor: MockDefaultBrowserConfirmationMonitor!
    private var isFeatureEnabled = true
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var capturedTypes: [DefaultBrowserAndDockPromptType] = []
    private var onConfirm: (() -> Void)?
    private var onDismiss: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        actionPerformer = MockDefaultBrowserAndDockActionPerformer()
        actionPerformer.pendingPromptType = .bothDefaultBrowserAndDockPrompt
        churnState = MockUserChurnStateProvider()
        churnState.hasChurnedFromDefault = true
        promptStore = MockDefaultBrowserAndDockPromptStore()
        uiHosting = MockDefaultBrowserAndDockPromptUIHosting()
        uiHosting.modalAnchor = NSWindow()
        modal = MockDefaultBrowserAndDockPromptModal()
        confirmationMonitor = MockDefaultBrowserConfirmationMonitor()
        isFeatureEnabled = true
        capturedTypes = []
        onConfirm = nil
        onDismiss = nil
    }

    override func tearDown() {
        cancellables.removeAll()
        actionPerformer = nil
        churnState = nil
        promptStore = nil
        uiHosting = nil
        modal = nil
        confirmationMonitor = nil
        capturedTypes = []
        onConfirm = nil
        onDismiss = nil
        super.tearDown()
    }

    private func makeDelegate() -> DefaultBrowserWinBackPromoDelegate {
        DefaultBrowserWinBackPromoDelegate(
            actionPerformer: actionPerformer,
            churnState: churnState,
            promptStore: promptStore,
            confirmationMonitor: confirmationMonitor,
            isFeatureEnabled: { [unowned self] in isFeatureEnabled },
            uiHosting: { [unowned self] in uiHosting },
            modalFactory: { [unowned self] type, onConfirm, onDismiss in
                capturedTypes.append(type)
                self.onConfirm = onConfirm
                self.onDismiss = onDismiss
                return modal
            },
            dateProvider: { [unowned self] in now })
    }

    private func isEligibleAfterRefresh() -> Bool {
        let delegate = makeDelegate()
        delegate.refreshEligibility()
        return delegate.isEligible
    }

    private func startShow(_ delegate: DefaultBrowserWinBackPromoDelegate) async -> Task<PromoResult, Never> {
        let presented = expectation(description: "modal presented")
        modal.didPresent = { presented.fulfill() }
        let task = Task { await delegate.show(history: PromoHistoryRecord(id: "test"), force: false) }
        await fulfillment(of: [presented], timeout: 1)
        return task
    }

    // MARK: - Eligibility

    func testWhenAllConditionsMetThenEligible() {
        XCTAssertTrue(isEligibleAfterRefresh())
    }

    func testWhenFlagOffThenNotEligible() {
        isFeatureEnabled = false
        XCTAssertFalse(isEligibleAfterRefresh())
    }

    func testWhenNotChurnedThenNotEligible() {
        churnState.hasChurnedFromDefault = false
        XCTAssertFalse(isEligibleAfterRefresh())
    }

    func testWhenChurnDetectedDuringRefreshThenEligible() {
        churnState.hasChurnedFromDefault = false
        churnState.shouldDetectChurnOnNextCheck = true
        XCTAssertTrue(isEligibleAfterRefresh())
    }

    func testWhenBannerPermanentlyDismissedThenNotEligible() {
        promptStore.isBannerPermanentlyDismissed = true
        XCTAssertFalse(isEligibleAfterRefresh())
    }

    func testWhenInactiveUserModalSeenThenNotEligible() {
        promptStore.inactiveUserModalShownDate = 1
        XCTAssertFalse(isEligibleAfterRefresh())
    }

    func testEligibilityRequiresSetAsDefaultPending() {
        let expected: [(DefaultBrowserAndDockPromptType?, Bool)] = [
            (nil, false),
            (.addToDockPrompt, false),
            (.setAsDefaultPrompt, true),
            (.bothDefaultBrowserAndDockPrompt, true)
        ]
        for (pendingType, isEligible) in expected {
            actionPerformer.pendingPromptType = pendingType
            XCTAssertEqual(isEligibleAfterRefresh(), isEligible, "pending type: \(String(describing: pendingType))")
        }
    }

    func testWhenFlagTurnsOffWhileRunningThenEligibilityPublishesFalse() {
        let delegate = makeDelegate()
        delegate.refreshEligibility()
        var received: [Bool] = []
        delegate.isEligiblePublisher.sink { received.append($0) }.store(in: &cancellables)

        isFeatureEnabled = false
        delegate.refreshEligibility()

        XCTAssertEqual(received, [true, false])
        XCTAssertFalse(delegate.isEligible)
    }

    // MARK: - Show

    func testWhenInPopUpWindowThenNoChange() async {
        uiHosting.isInPopUpWindow = true
        let delegate = makeDelegate()

        let result = await delegate.show(history: PromoHistoryRecord(id: "test"), force: false)

        XCTAssertEqual(result, .noChange)
        XCTAssertTrue(capturedTypes.isEmpty)
    }

    func testWhenNoModalAnchorThenNoChange() async {
        uiHosting.modalAnchor = nil
        let delegate = makeDelegate()

        let result = await delegate.show(history: PromoHistoryRecord(id: "test"), force: false)

        XCTAssertEqual(result, .noChange)
        XCTAssertTrue(capturedTypes.isEmpty)
    }

    func testWhenShownThenModalPresentedOverAnchorWithPendingType() async {
        actionPerformer.pendingPromptType = .setAsDefaultPrompt
        let delegate = makeDelegate()

        let task = await startShow(delegate)

        XCTAssertEqual(capturedTypes, [.setAsDefaultPrompt])
        XCTAssertTrue(modal.presentedWindow === uiHosting.modalAnchor)
        delegate.hide()
        _ = await task.value
    }

    func testWhenConfirmThenActionsAndActioned() async throws {
        let delegate = makeDelegate()
        let task = await startShow(delegate)

        try XCTUnwrap(onConfirm)()
        let result = await task.value

        XCTAssertEqual(result, .actioned())
        XCTAssertEqual(actionPerformer.performPendingActionsCallCount, 1)
        XCTAssertEqual(confirmationMonitor.startClickDates, [now])
        XCTAssertEqual(promptStore.inactiveUserModalShownDate, now.timeIntervalSince1970)
        XCTAssertEqual(modal.dismissCallCount, 0)
    }

    func testWhenDismissThenIgnored() async throws {
        let delegate = makeDelegate()
        let task = await startShow(delegate)

        try XCTUnwrap(onDismiss)()
        let result = await task.value

        XCTAssertEqual(result, .ignored())
        XCTAssertEqual(actionPerformer.performPendingActionsCallCount, 0)
        XCTAssertTrue(confirmationMonitor.startClickDates.isEmpty)
        XCTAssertEqual(promptStore.inactiveUserModalShownDate, now.timeIntervalSince1970)
        XCTAssertEqual(modal.dismissCallCount, 0)
    }

    func testWhenHideThenNoChangeAndModalDismissed() async {
        let delegate = makeDelegate()
        let task = await startShow(delegate)
        let dismissed = expectation(description: "modal dismissed")
        modal.didDismiss = { dismissed.fulfill() }

        delegate.hide()
        let result = await task.value
        await fulfillment(of: [dismissed], timeout: 1)

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(modal.dismissCallCount, 1)
        XCTAssertNil(promptStore.inactiveUserModalShownDate)
    }

    func testWhenButtonTappedAfterHideThenNothingHappens() async throws {
        let delegate = makeDelegate()
        let task = await startShow(delegate)
        delegate.hide()
        _ = await task.value

        try XCTUnwrap(onConfirm)()

        XCTAssertEqual(actionPerformer.performPendingActionsCallCount, 0)
        XCTAssertTrue(confirmationMonitor.startClickDates.isEmpty)
        XCTAssertNil(promptStore.inactiveUserModalShownDate)
    }
}
