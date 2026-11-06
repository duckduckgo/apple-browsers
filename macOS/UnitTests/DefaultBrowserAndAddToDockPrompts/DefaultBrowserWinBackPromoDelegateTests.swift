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
    private var isFeatureEnabled = true
    private var now = Date(timeIntervalSince1970: 1_700_000_000)
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
        capturedTypes = []
        onConfirm = nil
        onDismiss = nil
        super.tearDown()
    }

    private func makeDelegate(uiHosting hostProvider: (() -> DefaultBrowserAndDockPromptUIHosting?)? = nil) -> DefaultBrowserWinBackPromoDelegate {
        let hostProvider = hostProvider ?? { [unowned self] in uiHosting }
        let delegate = DefaultBrowserWinBackPromoDelegate(
            actionPerformer: actionPerformer,
            churnState: churnState,
            promptStore: promptStore,
            isFeatureEnabled: { [unowned self] in isFeatureEnabled },
            uiHosting: hostProvider,
            modalFactory: { [unowned self] type, confirm, dismiss in
                capturedTypes.append(type)
                onConfirm = confirm
                onDismiss = dismiss
                return modal
            },
            dateProvider: { [unowned self] in now })
        delegate.refreshEligibility()
        return delegate
    }

    private func startShow(_ delegate: DefaultBrowserWinBackPromoDelegate, force: Bool = false) async -> Task<PromoResult, Never> {
        let task = Task { await delegate.show(history: PromoHistoryRecord(id: "test"), force: force) }
        for _ in 0..<50 where onConfirm == nil { await Task.yield() }
        return task
    }

    // MARK: - Eligibility

    func testWhenAllConditionsMetThenEligible() {
        XCTAssertTrue(makeDelegate().isEligible)
    }

    func testWhenFlagOffThenNotEligible() {
        isFeatureEnabled = false
        XCTAssertFalse(makeDelegate().isEligible)
    }

    func testWhenNotChurnedThenNotEligible() {
        churnState.hasChurnedFromDefault = false
        XCTAssertFalse(makeDelegate().isEligible)
    }

    func testWhenBannerPermanentlyDismissedThenNotEligible() {
        promptStore.isBannerPermanentlyDismissed = true
        XCTAssertFalse(makeDelegate().isEligible)
    }

    func testWhenInactiveUserModalSeenThenNotEligible() {
        promptStore.inactiveUserModalShownDate = 1
        XCTAssertFalse(makeDelegate().isEligible)
    }

    func testWhenNothingPendingThenNotEligible() {
        actionPerformer.pendingPromptType = nil
        XCTAssertFalse(makeDelegate().isEligible)
    }

    func testWhenChurnedButDefaultAndNotInDockThenNotEligible() {
        actionPerformer.pendingPromptType = .addToDockPrompt
        XCTAssertFalse(makeDelegate().isEligible)
    }

    func testWhenOnlySetAsDefaultPendingThenEligible() {
        actionPerformer.pendingPromptType = .setAsDefaultPrompt
        XCTAssertTrue(makeDelegate().isEligible)
    }

    func testWhenFlagTurnsOffWhileRunningThenEligibilityPublishesFalse() {
        let delegate = makeDelegate()
        var received: [Bool] = []
        delegate.isEligiblePublisher.sink { received.append($0) }.store(in: &cancellables)

        isFeatureEnabled = false
        delegate.refreshEligibility()

        XCTAssertEqual(received, [true, false])
        XCTAssertFalse(delegate.isEligible)
    }

    func testRefreshEligibilityChecksForDefaultBrowserChangeEvenWhenFlagIsOff() {
        isFeatureEnabled = false
        let delegate = makeDelegate()
        let before = churnState.checkForDefaultBrowserChangeCallCount

        delegate.refreshEligibility()

        XCTAssertEqual(churnState.checkForDefaultBrowserChangeCallCount, before + 1)
    }

    // MARK: - Show

    func testWhenNoHostThenNoChange() async {
        let delegate = makeDelegate(uiHosting: { nil })

        let result = await delegate.show(history: PromoHistoryRecord(id: "test"), force: false)

        XCTAssertEqual(result, .noChange)
        XCTAssertTrue(capturedTypes.isEmpty)
    }

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

    func testWhenNotEligibleThenNoChange() async {
        churnState.hasChurnedFromDefault = false
        let delegate = makeDelegate()

        let result = await delegate.show(history: PromoHistoryRecord(id: "test"), force: false)

        XCTAssertEqual(result, .noChange)
        XCTAssertTrue(capturedTypes.isEmpty)
    }

    func testWhenNotEligibleAndForcedThenPresents() async {
        churnState.hasChurnedFromDefault = false
        let delegate = makeDelegate()

        let task = await startShow(delegate, force: true)

        XCTAssertEqual(capturedTypes, [.bothDefaultBrowserAndDockPrompt])
        XCTAssertEqual(modal.presentedWindows.count, 1)
        delegate.hide()
        _ = await task.value
    }

    func testWhenShownThenModalPresentedOverAnchorWithPendingType() async {
        actionPerformer.pendingPromptType = .setAsDefaultPrompt
        let delegate = makeDelegate()

        let task = await startShow(delegate)

        XCTAssertEqual(capturedTypes, [.setAsDefaultPrompt])
        XCTAssertTrue(modal.presentedWindows.first === uiHosting.modalAnchor)
        delegate.hide()
        _ = await task.value
    }

    func testWhenConfirmThenActionsAndActioned() async {
        let delegate = makeDelegate()
        let task = await startShow(delegate)

        XCTAssertNotNil(onConfirm)
        onConfirm?()
        let result = await task.value

        XCTAssertEqual(result, .actioned())
        XCTAssertEqual(actionPerformer.performPendingActionsCallCount, 1)
        XCTAssertEqual(promptStore.inactiveUserModalShownDate, now.timeIntervalSince1970)
        XCTAssertEqual(modal.dismissCallCount, 0)
    }

    func testWhenDismissThenIgnored() async {
        let delegate = makeDelegate()
        let task = await startShow(delegate)

        XCTAssertNotNil(onDismiss)
        onDismiss?()
        let result = await task.value

        XCTAssertEqual(result, .ignored())
        XCTAssertEqual(actionPerformer.performPendingActionsCallCount, 0)
        XCTAssertEqual(promptStore.inactiveUserModalShownDate, now.timeIntervalSince1970)
        XCTAssertEqual(modal.dismissCallCount, 0)
    }

    func testWhenRefreshedWhileShownAndNowDefaultThenEligibilityPublishesFalse() async {
        let delegate = makeDelegate()
        let task = await startShow(delegate)
        var received: [Bool] = []
        delegate.isEligiblePublisher.sink { received.append($0) }.store(in: &cancellables)

        actionPerformer.pendingPromptType = .addToDockPrompt
        delegate.refreshEligibility()

        XCTAssertEqual(received, [true, false])
        XCTAssertNil(promptStore.inactiveUserModalShownDate)
        delegate.hide()
        _ = await task.value
    }

    func testWhenRefreshedWhileShownAndOnlyAddedToDockThenStillEligible() async {
        let delegate = makeDelegate()
        let task = await startShow(delegate)
        var received: [Bool] = []
        delegate.isEligiblePublisher.sink { received.append($0) }.store(in: &cancellables)

        actionPerformer.pendingPromptType = .setAsDefaultPrompt
        delegate.refreshEligibility()

        XCTAssertEqual(received, [true])
        XCTAssertEqual(modal.dismissCallCount, 0)
        delegate.hide()
        _ = await task.value
    }

    func testWhenHideThenNoChangeAndModalDismissed() async {
        let delegate = makeDelegate()
        let task = await startShow(delegate)

        delegate.hide()
        let result = await task.value
        for _ in 0..<10 where modal.dismissCallCount == 0 { await Task.yield() }

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(modal.dismissCallCount, 1)
        XCTAssertNil(promptStore.inactiveUserModalShownDate)
    }
}
