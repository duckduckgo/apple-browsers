//
//  NewTabTransitionCoordinatorTests.swift
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

import XCTest
@testable import DuckDuckGo

@MainActor
final class NewTabTransitionCoordinatorTests: XCTestCase {

    private var host: FakeHost!
    private var nextTurn: [() -> Void] = []
    private var coordinator: NewTabTransitionCoordinator!
    private var buildCount = 0

    override func setUp() {
        super.setUp()
        host = FakeHost()
        nextTurn = []
        buildCount = 0
        coordinator = NewTabTransitionCoordinator(host: host, scheduleOnNextTurn: { [unowned self] in nextTurn.append($0) })
    }

    private func build() { buildCount += 1 }

    private func runNextTurn() {
        let work = nextTurn
        nextTurn = []
        work.forEach { $0() }
    }

    // MARK: - Opening

    func testWhenTransitionIsUnavailableThenOpenOnlyBuildsTheTab() {
        host.isTransitionAvailable = false

        let animated = coordinator.open(build)

        XCTAssertFalse(animated)
        XCTAssertEqual(buildCount, 1)
        XCTAssertFalse(coordinator.isOpeningNewTab)
    }

    func testWhenOpenedThenTheTabIsBuiltUnderATransitionFromThePage() {
        let animated = coordinator.open(build)

        XCTAssertTrue(animated)
        XCTAssertEqual(buildCount, 1)
        XCTAssertEqual(host.starts, [.page])
        XCTAssertTrue(host.transitions[0].revealedPage === host.newPageView)
        XCTAssertTrue(coordinator.isOpeningNewTab)
    }

    func testWhenOpenedWhileATransitionRunsThenTheTabIsBuiltWithoutASecondOne() {
        coordinator.open(build)

        let animated = coordinator.open(build)

        XCTAssertFalse(animated)
        XCTAssertEqual(buildCount, 2)
        XCTAssertEqual(host.transitions.count, 1)
    }

    func testWhenTheTransitionCompletesThenTheNextOpenGetsItsOwn() {
        coordinator.open(build)
        host.transitions[0].complete()

        XCTAssertFalse(coordinator.isOpeningNewTab)
        XCTAssertTrue(coordinator.open(build))
        XCTAssertEqual(host.transitions.count, 2)
    }

    // MARK: - Prepared transitions

    func testWhenPreparedThenTheNextOpenUsesThatTransition() {
        XCTAssertTrue(coordinator.prepare(from: .tabManager))

        coordinator.open(build)

        XCTAssertEqual(host.starts, [.tabManager])
        XCTAssertNotNil(host.transitions[0].revealedPage)
        runNextTurn()
        XCTAssertEqual(host.transitions[0].cancelCount, 0)
    }

    func testWhenPreparedButNothingOpensThisTurnThenItIsCancelled() {
        coordinator.prepare(from: .tabManager)

        runNextTurn()

        XCTAssertEqual(host.transitions[0].cancelCount, 1)
        XCTAssertFalse(coordinator.isOpeningNewTab)
    }

    func testWhenPreparedAgainThenTheEarlierOneIsCancelled() {
        coordinator.prepare(from: .tabManager)
        host.transitions[0].complete()

        coordinator.prepare(from: .tabManager)

        XCTAssertEqual(host.transitions.count, 2)
        XCTAssertEqual(host.transitions[1].cancelCount, 0)
    }

    // MARK: - Entrances

    func testWhenOpenedFromOutsideTheAppThenTheTabIsBuiltWithoutATransition() {
        let animated = coordinator.open(entrance: .fromOutsideTheApp, build)

        XCTAssertFalse(animated)
        XCTAssertEqual(buildCount, 1)
        XCTAssertTrue(host.transitions.isEmpty)
        XCTAssertFalse(coordinator.isOpeningNewTab)
    }

    func testWhenOpenedAfterASwipeThenTheTabIsBuiltWithoutATransition() {
        let animated = coordinator.open(entrance: .followsSwipe, build)

        XCTAssertFalse(animated)
        XCTAssertEqual(buildCount, 1)
        XCTAssertTrue(host.transitions.isEmpty)
    }

    func testWhenOpenedWithoutGrowingThenAPreparedTransitionIsLeftForItsTab() {
        coordinator.prepare(from: .tabManager)

        coordinator.open(entrance: .fromOutsideTheApp, build)

        XCTAssertEqual(buildCount, 1)
        XCTAssertEqual(host.transitions.count, 1)
        XCTAssertNil(host.transitions[0].revealedPage)

        let animated = coordinator.open(build)

        XCTAssertTrue(animated)
        XCTAssertTrue(host.transitions[0].revealedPage === host.newPageView)
    }

    // MARK: - Presented screens

    func testWhenTransitionIsUnavailableThenThePresentedScreenDismissesBeforeTheTabIsBuilt() {
        host.isTransitionAvailable = false

        coordinator.openClosingPresentedScreen { [unowned self] in build() }
        XCTAssertEqual(buildCount, 0)

        host.dismissals.forEach { $0() }
        XCTAssertEqual(buildCount, 1)
    }

    func testWhenOpeningOverAPresentedScreenThenTheTabIsBuiltOnceTheScreenHasClosed() {
        coordinator.openClosingPresentedScreen { [unowned self] in build() }

        XCTAssertEqual(host.starts, [.presentedScreen])
        XCTAssertEqual(buildCount, 0)
        XCTAssertNil(host.transitions[0].revealedPage)

        host.unseenCloses.forEach { $0() }

        XCTAssertEqual(buildCount, 1)
        XCTAssertTrue(host.transitions[0].revealedPage === host.newPageView)
    }

    // MARK: - Keyboard focus

    func testWhenNoTransitionRunsThenFocusRunsOnTheNextTurn() {
        var focusCount = 0

        coordinator.scheduleInputFocus { focusCount += 1 }
        XCTAssertEqual(focusCount, 0)

        runNextTurn()
        XCTAssertEqual(focusCount, 1)
    }

    func testWhenATransitionRunsThenFocusWaitsForItsKeyboardGate() {
        var focusCount = 0
        coordinator.open(build)

        coordinator.scheduleInputFocus { focusCount += 1 }
        runNextTurn()
        XCTAssertEqual(focusCount, 0)

        host.transitions[0].keyboardGate.reachMoment()
        runNextTurn()
        XCTAssertEqual(focusCount, 1)
    }

    // MARK: - Shared chrome

    func testWhenNoTabIsOpeningThenActionsAfterItRunRightAway() {
        var ran = false

        coordinator.afterNewTabOpens { ran = true }

        XCTAssertTrue(ran)
    }

    func testWhenATabIsOpeningThenActionsAfterItWaitForTheTransition() {
        var ran = false
        coordinator.open(build)

        coordinator.afterNewTabOpens { ran = true }
        XCTAssertFalse(ran)

        host.transitions[0].complete()
        XCTAssertTrue(ran)
    }
}

@MainActor
private final class FakeTransition: NewTabTransitioning {

    let keyboardGate = NewTabKeyboardGate()
    private var completions: [() -> Void] = []
    private(set) var revealedPage: UIView?
    private(set) var cancelCount = 0

    func revealNewPage(_ page: UIView, builtBy build: () -> Void) {
        revealedPage = page
        build()
    }

    func addCompletion(_ completion: @escaping () -> Void) {
        completions.append(completion)
    }

    func cancel() {
        cancelCount += 1
        complete()
    }

    func complete() {
        keyboardGate.open()
        let finished = completions
        completions = []
        finished.forEach { $0() }
    }
}

@MainActor
private final class FakeHost: NewTabTransitionHost {

    let newPageView = UIView()
    var isTransitionAvailable = true
    private(set) var starts: [NewTabTransitionCoordinator.Start] = []
    private(set) var transitions: [FakeTransition] = []
    private(set) var unseenCloses: [() -> Void] = []
    private(set) var dismissals: [() -> Void] = []

    func makeNewTabTransition(from start: NewTabTransitionCoordinator.Start, raisesKeyboard: Bool) -> NewTabTransitioning? {
        guard isTransitionAvailable else { return nil }
        let transition = FakeTransition()
        starts.append(start)
        transitions.append(transition)
        return transition
    }

    func closePresentedScreenUnseen(then completion: @escaping () -> Void) {
        unseenCloses.append(completion)
    }

    func dismissPresentedScreen(then completion: @escaping () -> Void) {
        dismissals.append(completion)
    }
}
