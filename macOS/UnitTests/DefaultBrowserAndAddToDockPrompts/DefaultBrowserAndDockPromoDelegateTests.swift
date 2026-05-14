//
//  DefaultBrowserAndDockPromoDelegateTests.swift
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
import PersistenceTestingUtils
import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DefaultBrowserAndDockPromoDelegateTests: XCTestCase {

    private var coordinator: MockDefaultBrowserAndDockPromptCoordinator!
    private var presenter: DefaultBrowserAndDockPromptPresentingMock!
    private var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        try super.setUpWithError()
        coordinator = MockDefaultBrowserAndDockPromptCoordinator()
        presenter = DefaultBrowserAndDockPromptPresentingMock()
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
        coordinator = nil
        presenter = nil
        try super.tearDownWithError()
    }

    private func makeDelegate(type: DefaultBrowserAndDockPromptPresentationType,
                              uiHosting: DefaultBrowserAndDockPromptUIHosting? = MockDefaultBrowserAndDockPromptUIHosting()) -> DefaultBrowserAndDockPromoDelegate {
        DefaultBrowserAndDockPromoDelegate(type: type, coordinator: coordinator, presenter: presenter, uiHosting: { uiHosting })
    }

    // MARK: - Eligibility tests

    func testWhenPromptEligibilityMatchesTypeThenIsEligibleIsTrue() {
        // GIVEN
        let delegate = makeDelegate(type: .active(.banner))
        coordinator.eligiblePrompt.send(.active(.banner))

        // THEN
        XCTAssertTrue(delegate.isEligible)
    }

    func testWhenPromptEligibilityDoesNotMatchTypeThenIsEligibleIsFalse() {
        // GIVEN
        let delegate = makeDelegate(type: .active(.banner))
        coordinator.eligiblePrompt.send(.active(.popover))

        // THEN
        XCTAssertFalse(delegate.isEligible)
    }

    func testWhenPromptEligibilityIsNilThenIsEligibleIsFalse() {
        // GIVEN
        let delegate = makeDelegate(type: .active(.banner))
        coordinator.eligiblePrompt.send(nil)

        // THEN
        XCTAssertFalse(delegate.isEligible)
    }

    func testWhenPromptEligibilityChangesToMatchingTypeThenPublisherEmitsTrue() {
        // GIVEN
        let delegate = makeDelegate(type: .active(.banner))
        var received: [Bool] = []
        let expectation = expectation(description: "Eligibility changed")
        delegate.isEligiblePublisher
            .dropFirst()
            .sink { value in
                received.append(value)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // WHEN
        coordinator.eligiblePrompt.send(.active(.banner))

        // THEN
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(received, [true])
    }

    func testWhenPromptEligibilityChangesToNonMatchingTypeThenPublisherEmitsFalse() {
        // GIVEN
        let delegate = makeDelegate(type: .active(.banner))
        coordinator.eligiblePrompt.send(.active(.banner)) // Start eligible
        var received: [Bool] = []
        let expectation = expectation(description: "Eligibility changed")
        delegate.isEligiblePublisher
            .dropFirst()
            .sink { value in
                received.append(value)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // WHEN
        coordinator.eligiblePrompt.send(.active(.popover))

        // THEN
        wait(for: [expectation], timeout: 1)
        XCTAssertEqual(received, [false])
    }

    func testWhenPromptEligibilityEmitsSameValueThenPublisherDeduplicates() {
        // GIVEN
        let delegate = makeDelegate(type: .active(.banner))
        coordinator.eligiblePrompt.send(.active(.popover)) // Start with non-matching
        var received: [Bool] = []
        delegate.isEligiblePublisher
            .dropFirst()
            .sink {
                received.append($0)
            }
            .store(in: &cancellables)

        // WHEN - change to matching, then send same matching value again (removeDuplicates should suppress)
        coordinator.eligiblePrompt.send(.active(.banner))
        coordinator.eligiblePrompt.send(.active(.banner))

        // THEN - received should have [true] only; second banner is deduplicated
        XCTAssertEqual(received, [true])
    }

    // MARK: - refreshEligibility tests

    func testWhenRefreshEligibilityCalledThenCoordinatorEvaluateEligibilityCalled() {
        // GIVEN
        coordinator.evaluateEligibilityType = .active(.banner)
        let delegate = makeDelegate(type: .active(.banner))
        coordinator.eligiblePrompt.send(nil) // Clear to test refresh

        // WHEN
        delegate.refreshEligibility()

        // THEN
        XCTAssertEqual(coordinator.eligiblePrompt.value, .active(.banner))
    }

    // MARK: - show() tests

    func testWhenShowCalledAndNotEligibleThenReturnsNoChange() async {
        // GIVEN
        let delegate = makeDelegate(type: .active(.banner))
        coordinator.eligiblePrompt.send(.active(.popover)) // Different type

        // WHEN
        let result = await delegate.show(history: PromoHistoryRecord(id: "test"))

        // THEN
        XCTAssertEqual(result, .noChange)
    }

    func testWhenShowCalledAndUIHostingIsNilThenReturnsNoChange() async {
        // GIVEN
        let delegate = makeDelegate(type: .active(.banner), uiHosting: nil)
        coordinator.eligiblePrompt.send(.active(.banner))

        // WHEN
        let result = await delegate.show(history: PromoHistoryRecord(id: "test"))

        // THEN
        XCTAssertEqual(result, .noChange)
    }

    func testWhenShowCalledAndUIHostingIsInPopUpWindowThenReturnsNoChangeWithoutShowing() async {
        // GIVEN - eligible delegate but hosting is in a popup window
        let popupHosting = MockDefaultBrowserAndDockPromptUIHosting()
        popupHosting.isInPopUpWindow = true
        let delegate = makeDelegate(type: .active(.banner), uiHosting: popupHosting)
        coordinator.eligiblePrompt.send(.active(.banner))

        // WHEN
        let result = await delegate.show(history: PromoHistoryRecord(id: "test"))

        // THEN
        XCTAssertEqual(presenter.tryToShowPromptCallCount, 0)
        XCTAssertEqual(result, .noChange)
    }

    func testWhenShowCalledAndPromptDismissedThenReturnsExpectedResult() async {
        // GIVEN
        let expectedType = DefaultBrowserAndDockPromptPresentationType.active(.banner)
        coordinator.eligiblePrompt.send(expectedType)
        let delegate = makeDelegate(type: expectedType)

        // WHEN
        let showTask = Task { await delegate.show(history: PromoHistoryRecord(id: "test")) }
        await Task.yield() // Allow show() to run and set up the prompt
        coordinator.promptDismissed.send((expectedType, .ignored(cooldown: 1)))
        let result = await showTask.value

        // THEN
        XCTAssertEqual(presenter.tryToShowPromptCallCount, 1)
        XCTAssertEqual(result, .ignored(cooldown: 1))
    }

    func testWhenShowCalledAndPresenterReturnsEarlyWithoutShowingThenReturnsNoChange() async {
        // GIVEN - delegate is "eligible" (cached) but presenter returns early (e.g. coordinator.getPromptType() returns nil)
        let expectedType = DefaultBrowserAndDockPromptPresentationType.active(.banner)
        coordinator.eligiblePrompt.send(expectedType)
        let delegate = makeDelegate(type: expectedType)
        presenter.shouldCallOnNoShow = true

        // WHEN
        let result = await delegate.show(history: PromoHistoryRecord(id: "test"))

        // THEN - continuation is resumed with .noChange, no hang
        XCTAssertEqual(presenter.tryToShowPromptCallCount, 1)
        XCTAssertEqual(result, .noChange)
    }

    func testWhenShowCalledAndDifferentPromptTypeDismissedThenShowDoesNotReturn() async {
        // GIVEN - banner delegate waiting
        let expectedType = DefaultBrowserAndDockPromptPresentationType.active(.banner)
        coordinator.eligiblePrompt.send(expectedType)
        let delegate = makeDelegate(type: expectedType)

        // WHEN - dismiss popover (different type)
        var didComplete = false
        let showTask = Task {
            let result = await delegate.show(history: PromoHistoryRecord(id: "test"))
            didComplete = true
            return result
        }
        await Task.yield() // Allow show() to run and set up the prompt
        coordinator.promptDismissed.send((.active(.popover), .actioned))

        // THEN - show should still be suspended
        XCTAssertFalse(didComplete, "Banner delegate should not receive popover dismiss")

        // Clean up: dismiss banner so the continuation can complete
        coordinator.promptDismissed.send((expectedType, .actioned))
        _ = await showTask.value
    }

    // MARK: - hide() tests

    func testWhenHideCalledThenPresenterDismissesMatchingPromptType() async {
        // GIVEN
        let expectedType = DefaultBrowserAndDockPromptPresentationType.active(.banner)
        coordinator.eligiblePrompt.send(expectedType)
        let delegate = makeDelegate(type: expectedType)

        let showTask = Task { await delegate.show(history: PromoHistoryRecord(id: "test")) }
        await Task.yield() // Allow show() to run and set up the prompt
        XCTAssertEqual(presenter.tryToShowPromptCallCount, 1)

        // WHEN
        delegate.hide()
        await Task.yield() // Allow hide() to run

        // THEN
        XCTAssertEqual(presenter.dismissedPromptType, expectedType)

        _ = await showTask.value
    }

    func testWhenHideCalledWithPendingContinuationThenReturnsNoChange() async {
        // GIVEN
        let expectedType = DefaultBrowserAndDockPromptPresentationType.active(.banner)
        let delegate = makeDelegate(type: expectedType)

        // WHEN - start show (suspends), then hide
        let showTask = Task { await delegate.show(history: PromoHistoryRecord(id: "test")) }
        await Task.yield() // Allow show() to run and set up the prompt
        delegate.hide()

        let result = await showTask.value

        // THEN
        XCTAssertEqual(result, .noChange)
    }
}

private final class MockDefaultBrowserAndDockPromptUIHosting: DefaultBrowserAndDockPromptUIHosting {
    var isInPopUpWindow: Bool = false

    func providePopoverAnchor() -> NSView? {
        return nil
    }

    func addSetAsDefaultBanner(_ banner: BannerMessageViewController) { }

    func provideModalAnchor() -> NSWindow? {
        return nil
    }
}
