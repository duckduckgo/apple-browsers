//
//  BarsAnimatorTests.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import PrivacyDashboard

@testable import DuckDuckGo

class BarsAnimatorTests: XCTestCase {

    func testDidStartScrollingUpdatesPositionCorrectly() {
        let (sut, delegate) = makeSUT()
        let scrollView = mockScrollView()
        let initialYposition = sut.draggingStartPosY

        scrollView.contentOffset.y = -100
        sut.didStartScrolling(in: scrollView)

        XCTAssertEqual(initialYposition, 0.0)
        XCTAssertEqual(sut.draggingStartPosY, -100)

        XCTAssertEqual(delegate.receivedMessages, [])
    }

    func testBarStateRevealedWhenScrollDownUpdatesToHiddenState() {
        let (sut, delegate) = makeSUT()
        let scrollView = mockScrollView()

        scrollView.contentOffset.y = 100
        sut.didStartScrolling(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        scrollView.contentOffset.y = 200
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .transitioning)

        scrollView.contentOffset.y = 300
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .hidden)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(0.0))

    }

    func testBarStateHiddenWhenScrollDownKeepsHiddenState() {
        let (sut, delegate) = makeSUT()
        let scrollView = mockScrollView()

        scrollView.contentOffset.y = 100
        sut.didStartScrolling(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        scrollView.contentOffset.y = 200
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .transitioning)

        scrollView.contentOffset.y = 300
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .hidden)

        scrollView.contentOffset.y = 100
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .hidden)

        XCTAssertEqual(delegate.receivedMessages.count, 2)
        XCTAssertLessThan(delegate.receivedMessages.first?.percent ?? 2.0, 1.0, "Message should be .setBarsVisibility(< 1.0), got \(delegate.receivedMessages)")
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(0.0), "Message should be .setBarsVisibility(0.0), got \(delegate.receivedMessages)")
    }

    func testBarStateHiddenWhenScrollUpUpdatesToRevealedState() throws {
        let (sut, delegate) = makeSUT()
        let scrollView = mockScrollView()

        scrollView.contentOffset.y = 100
        sut.didStartScrolling(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        scrollView.contentOffset.y = 200
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .transitioning)

        scrollView.contentOffset.y = 400
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .hidden)

        scrollView.contentOffset.y = -100
        sut.didStartScrolling(in: scrollView)
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .transitioning)

        scrollView.contentOffset.y = -150
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        // Verify message pattern: first some 0.0 values, then some 1.0 values
        XCTAssertTrue(delegate.receivedMessages.count >= 4, "Expected at least 4 messages, got \(delegate.receivedMessages.count)")

        // Find where the transition from 0.0 to 1.0 happens
        let transitionIndex = delegate.receivedMessages.firstIndex {
            if case .setBarsVisibility(1.0) = $0 { return true } else { return false }
        }

        let index = try XCTUnwrap(transitionIndex, "Expected to find at least one .setBarsVisibility(1.0) message")

        // Check that all messages before transition are 0.0
        let beforeTransition = delegate.receivedMessages[0..<index]
        XCTAssertTrue(beforeTransition.allSatisfy { $0.percent ?? 2.0 <= 1 },
                      "All messages before transition should be .setBarsVisibility(<= 1), got \(beforeTransition)")

        // Check that all messages after and including transition are 1.0
        let afterTransition = delegate.receivedMessages[index...]
        XCTAssertTrue(afterTransition.allSatisfy { $0 == .setBarsVisibility(1.0) },
                      "All messages after transition should be .setBarsVisibility(1.0), got \(afterTransition)")
    }

    func testBarStateRevealedWhenScrollUpDoNotChangeCurrentState() {
        let (sut, delegate) = makeSUT()
        let scrollView = mockScrollView()

        scrollView.contentOffset.y = 100
        sut.didStartScrolling(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        scrollView.contentOffset.y = 50
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        scrollView.contentOffset.y = -50
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        XCTAssertEqual(delegate.receivedMessages, [])
    }

    // Force-revealing must reset the state from .hidden back to .revealed. The error-page reveal
    // relies on this (routed through chromeManager.reset) so the bars can't get stuck hidden.
    func testRevealBarsResetsHiddenStateToRevealed() {
        let (sut, delegate) = makeSUT()
        let scrollView = mockScrollView()

        scrollView.contentOffset.y = 100
        sut.didStartScrolling(in: scrollView)
        scrollView.contentOffset.y = 200
        sut.didScroll(in: scrollView)
        scrollView.contentOffset.y = 300
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .hidden)

        sut.revealBars(animated: true)

        XCTAssertEqual(sut.barsState, .revealed)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(1.0))
    }

    // After a force-reveal a trailing scroll-end must not re-hide the bars (the stuck "no buttons" bug).
    func testRevealedBarsAreNotReHiddenByTrailingScrollEnd() {
        let (sut, delegate) = makeSUT()
        let scrollView = mockScrollView()

        scrollView.contentOffset.y = 100
        sut.didStartScrolling(in: scrollView)
        scrollView.contentOffset.y = 200
        sut.didScroll(in: scrollView)
        scrollView.contentOffset.y = 300
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .hidden)

        sut.revealBars(animated: true)
        XCTAssertEqual(sut.barsState, .revealed)

        scrollView.contentOffset.y = 100
        sut.didFinishScrolling(in: scrollView, velocity: 0)

        XCTAssertEqual(sut.barsState, .revealed)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(1.0))
    }
}

class BarsAnimatorFloatingTests: XCTestCase {

    private let travel = BarsAnimator.Metrics.floatingTransitionTravel

    func testWhenScrollingTheFullTravelDistanceThenBarsAreFullyHidden() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)

        scroll(sut, scrollView, clock, to: stride(from: 10.0, through: travel, by: 10.0))

        XCTAssertEqual(sut.barsState, .hidden)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(0.0))
    }

    func testWhenScrollingHalfTheTravelDistanceThenBarsAreHalfVisible() throws {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let halfTravel = travel / 2

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        scroll(sut, scrollView, clock, to: stride(from: halfTravel / 4, through: halfTravel, by: halfTravel / 4))

        XCTAssertEqual(sut.barsState, .transitioning)
        XCTAssertEqual(try XCTUnwrap(delegate.receivedMessages.last?.percent), 0.5, accuracy: 0.001)
    }

    func testWhenBarHeightDiffersThenTravelDistanceIsUnchanged() throws {
        var finalPercents: [CGFloat] = []
        let halfTravel = travel / 2

        for toolbarHeight in [CGFloat(128), CGFloat(62)] {
            let (sut, delegate, clock) = makeFloatingSUT()
            delegate.toolbarHeight = toolbarHeight
            let scrollView = mockTallScrollView()

            scrollView.contentOffset.y = 0
            sut.didStartScrolling(in: scrollView)
            scroll(sut, scrollView, clock, to: stride(from: halfTravel / 4, through: halfTravel, by: halfTravel / 4))

            finalPercents.append(try XCTUnwrap(delegate.receivedMessages.last?.percent))
        }

        XCTAssertEqual(finalPercents[0], finalPercents[1], accuracy: 0.001)
    }

    func testWhenFrameStepSizeDiffersThenFinalProgressIsUnchanged() throws {
        var finalPercents: [CGFloat] = []
        let halfTravel = travel / 2

        for step in [CGFloat(2), CGFloat(4)] {
            let (sut, delegate, clock) = makeFloatingSUT()
            let scrollView = mockTallScrollView()

            scrollView.contentOffset.y = 0
            sut.didStartScrolling(in: scrollView)
            scroll(sut, scrollView, clock, to: stride(from: step, through: halfTravel, by: step))

            finalPercents.append(try XCTUnwrap(delegate.receivedMessages.last?.percent))
        }

        XCTAssertEqual(finalPercents[0], finalPercents[1], accuracy: 0.001)
    }

    func testWhenDragIsInterruptedThenProgressResumesWhereItLeftOff() throws {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let halfTravel = travel / 2

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        scroll(sut, scrollView, clock, to: stride(from: halfTravel / 4, through: halfTravel, by: halfTravel / 4))
        let interruptedPercent = try XCTUnwrap(delegate.receivedMessages.last?.percent)

        sut.didStartScrolling(in: scrollView)
        clock.advance(by: 1.0 / 60.0)
        sut.didScroll(in: scrollView)

        XCTAssertEqual(try XCTUnwrap(delegate.receivedMessages.last?.percent), interruptedPercent, accuracy: 0.001)
    }

    func testWhenRevealingFromHiddenThenChromeDoesNotJumpToHalfVisible() throws {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()

        sut.hideBars(animated: false)
        XCTAssertEqual(sut.barsState, .hidden)

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        scrollView.contentOffset.y = -1
        clock.advance(by: 1.0 / 60.0)
        sut.didScroll(in: scrollView)

        let percent = try XCTUnwrap(delegate.receivedMessages.last?.percent)
        XCTAssertEqual(percent, 1.0 / travel, accuracy: 0.001)
        XCTAssertLessThan(percent, 0.1, "1pt of overscroll must not reveal a large slice of the chrome")
    }

    func testWhenScrollOffsetAdvancesFullTravelInOneUpdateThenBarsTrackItImmediately() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)

        scrollView.contentOffset.y = 1000
        clock.advance(by: 1.0 / 60.0)
        sut.didScroll(in: scrollView)

        XCTAssertEqual(sut.barsState, .hidden)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(0))
    }

    func testWhenNewDragInterruptsSettlingThenProgressStartsFromRenderedVisibility() throws {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        advanceOffset(sut, scrollView, clock, to: travel * 0.2)
        sut.didFinishScrolling(in: scrollView, velocity: BarsAnimator.Metrics.floatingVelocityCommitThreshold + 0.1)

        delegate.currentBarsVisibility = 0.6
        sut.didStartScrolling(in: scrollView)
        advanceOffset(sut, scrollView, clock, to: scrollView.contentOffset.y + travel * 0.1)

        XCTAssertEqual(try XCTUnwrap(delegate.receivedMessages.last?.percent), 0.5, accuracy: 0.001)
        XCTAssertEqual(sut.barsState, .transitioning)
    }

    func testWhenReversingDirectionMultipleTimesWithinOneDragThenTrackingNeverStalls() throws {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)

        advanceOffset(sut, scrollView, clock, to: travel * 0.3)
        let firstCollapsePercent = try XCTUnwrap(delegate.receivedMessages.last?.percent)
        advanceOffset(sut, scrollView, clock, to: travel * 0.1)
        let revealPercent = try XCTUnwrap(delegate.receivedMessages.last?.percent)
        advanceOffset(sut, scrollView, clock, to: travel * 0.5)
        let secondCollapsePercent = try XCTUnwrap(delegate.receivedMessages.last?.percent)

        XCTAssertGreaterThan(revealPercent, firstCollapsePercent)
        XCTAssertLessThan(secondCollapsePercent, revealPercent)
        XCTAssertEqual(sut.barsState, .transitioning)
    }

    func testWhenReleaseVelocityIsBelowCommitThresholdThenOutcomeIsDecidedByProgress() {
        for (progress, expectedState): (CGFloat, BarsAnimator.State) in [(0.4, .revealed), (0.6, .hidden)] {
            let (sut, delegate, clock) = makeFloatingSUT()
            let scrollView = mockTallScrollView()

            scrollView.contentOffset.y = 0
            sut.didStartScrolling(in: scrollView)
            advanceOffset(sut, scrollView, clock, to: travel * progress)
            XCTAssertEqual(sut.barsState, .transitioning)

            sut.didFinishScrolling(in: scrollView, velocity: BarsAnimator.Metrics.floatingVelocityCommitThreshold - 0.01)

            XCTAssertEqual(sut.barsState, expectedState, "progress \(progress)")
            XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(expectedState == .hidden ? 0 : 1))
        }
    }

    func testWhenReleaseVelocityIsAboveCommitThresholdThenDirectionWins() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let initialProgress = travel * 0.2

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        sut.didScroll(in: scrollView)
        scrollView.contentOffset.y = initialProgress
        clock.advance(by: 1.0)
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .transitioning)

        sut.didFinishScrolling(in: scrollView, velocity: BarsAnimator.Metrics.floatingVelocityCommitThreshold + 0.1)

        XCTAssertEqual(sut.barsState, .hidden)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(0.0))
    }

    func testWhenFastReleaseThenSettlingDoesNotOverrideTheMorphDuration() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let initialProgress = travel * 0.2

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        sut.didScroll(in: scrollView)
        scrollView.contentOffset.y = initialProgress
        clock.advance(by: 1.0)
        sut.didScroll(in: scrollView)

        sut.didFinishScrolling(in: scrollView, velocity: BarsAnimator.Metrics.floatingVelocityCommitThreshold + 5)

        XCTAssertNil(delegate.lastAnimationDuration)
    }

    func testWhenDraggingUpFromHiddenThenChromeStartsRevealingImmediately() throws {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let travel = BarsAnimator.Metrics.floatingTransitionTravel

        sut.hideBars(animated: false)
        delegate.receivedMessages.removeAll()
        scrollView.contentOffset.y = 500
        sut.didStartScrolling(in: scrollView)

        scrollView.contentOffset.y = 500 - (travel * 0.1)
        clock.advance(by: 1.0 / 60.0)
        sut.didScroll(in: scrollView)

        let percent = try XCTUnwrap(delegate.receivedMessages.last?.percent)
        XCTAssertEqual(percent, 0.1, accuracy: 0.01, "10% of the travel back up should show ~10% revealed")
        XCTAssertEqual(sut.barsState, .transitioning)
    }

    func testWhenDraggingUpTheFullTravelThenChromeEndsFullyRevealed() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let travel = BarsAnimator.Metrics.floatingTransitionTravel

        sut.hideBars(animated: false)
        scrollView.contentOffset.y = 500
        sut.didStartScrolling(in: scrollView)

        scrollView.contentOffset.y = 500 - travel
        clock.advance(by: 1.0 / 60.0)
        sut.didScroll(in: scrollView)

        XCTAssertEqual(sut.barsState, .revealed)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(1.0))
    }

    func testWhenReversingDirectionThenTrackingNeverStalls() throws {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)

        advanceOffset(sut, scrollView, clock, to: travel * 0.3)
        XCTAssertEqual(sut.barsState, .transitioning)
        let collapsingPercent = try XCTUnwrap(delegate.receivedMessages.last?.percent)

        advanceOffset(sut, scrollView, clock, to: travel * 0.1)
        let revealingPercent = try XCTUnwrap(delegate.receivedMessages.last?.percent)

        XCTAssertGreaterThan(revealingPercent, collapsingPercent, "Must keep tracking after the reversal, not stall")
        XCTAssertEqual(sut.barsState, .transitioning)
    }

    func testWhenLegacyChromeThenMidPageDragUpFromHiddenDoesNothing() {
        let (sut, delegate, clock) = makeFloatingSUT()
        delegate.isFloatingChromeEnabled = false
        let scrollView = mockTallScrollView()

        sut.hideBars(animated: false)
        delegate.receivedMessages.removeAll()
        scrollView.contentOffset.y = 500
        sut.didStartScrolling(in: scrollView)

        scrollView.contentOffset.y = 0
        clock.advance(by: 1.0 / 60.0)
        sut.didScroll(in: scrollView)

        XCTAssertEqual(sut.barsState, .hidden, "Legacy chrome keeps its historical behaviour: only top overscroll reveals")
        XCTAssertTrue(delegate.receivedMessages.isEmpty)
    }

    func testWhenRubberBandingAtTopThenChromeStaysRevealed() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        advanceOffset(sut, scrollView, clock, to: -travel * 0.25)

        XCTAssertEqual(sut.barsState, .revealed)

        advanceOffset(sut, scrollView, clock, to: 0)

        XCTAssertEqual(sut.barsState, .revealed)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(1.0))
    }

    private func scroll<Offsets: Sequence>(_ sut: BarsAnimator,
                                           _ scrollView: UIScrollView,
                                           _ clock: TestClock,
                                           to offsets: Offsets) where Offsets.Element == CGFloat {
        for offset in offsets {
            scrollView.contentOffset.y = offset
            clock.advance(by: 1.0 / 30.0)
            sut.didScroll(in: scrollView)
        }
    }

    private func advanceOffset(_ sut: BarsAnimator,
                               _ scrollView: UIScrollView,
                               _ clock: TestClock,
                               to targetOffset: CGFloat,
                               steps: Int = 20) {
        let start = scrollView.contentOffset.y
        for step in 1...steps {
            scrollView.contentOffset.y = start + (targetOffset - start) * CGFloat(step) / CGFloat(steps)
            clock.advance(by: 1.0 / 30.0)
            sut.didScroll(in: scrollView)
        }
    }
}

// MARK: - Helpers

private func mockTallScrollView() -> UIScrollView {
    let scrollView = UIScrollView()
    scrollView.contentSize = .init(width: 300, height: 5000)
    scrollView.bounds = .init(x: 0, y: 0, width: 300, height: 300)

    return scrollView
}

private final class TestClock {
    private(set) var now: CFTimeInterval = 1_000

    func advance(by interval: CFTimeInterval) {
        now += interval
    }
}

private func makeFloatingSUT() -> (sut: BarsAnimator, delegate: BrowserChromeDelegateMock, clock: TestClock) {
    let clock = TestClock()
    let sut = BarsAnimator()
    let delegate = BrowserChromeDelegateMock()
    delegate.isFloatingChromeEnabled = true
    delegate.toolbarHeight = 128
    sut.delegate = delegate

    return (sut, delegate, clock)
}

private func makeSUT() -> (sut: BarsAnimator, delegate: BrowserChromeDelegateMock) {
    let sut = BarsAnimator()
    let delegate = BrowserChromeDelegateMock()
    sut.delegate = delegate

    return (sut, delegate)
}

private func mockScrollView() -> UIScrollView {
    let scrollView = UIScrollView()
    scrollView.contentSize = .init(width: 300, height: 600)
    scrollView.bounds = .init(x: 0, y: 0, width: 300, height: 300)

    return scrollView
}

private class BrowserChromeDelegateMock: BrowserChromeDelegate {
    func setBarsHidden(_ hidden: Bool, animated: Bool, customAnimationDuration: CGFloat?) {
        setBarsHidden(hidden, animated: animated)
    }

    var lastAnimationDuration: CGFloat?

    func setBarsVisibility(_ percent: CGFloat, animated: Bool, animationDuration: CGFloat?) {
        lastAnimationDuration = animationDuration
        setBarsVisibility(percent, animated: animated)
    }

    enum Message: Equatable {
        case setBarsHidden(Bool)
        case resetBars
        case setNavigationBarHidden(Bool)
        case setBarsVisibility(CGFloat)
        case setRefreshControlEnabled(Bool)

        var percent: CGFloat? {
            switch self {
            case .setBarsVisibility(let value):
                return value
            default:
                return nil
            }
        }
    }

    var receivedMessages: [Message] = []

    func setBarsHidden(_ hidden: Bool, animated: Bool) {
        receivedMessages.append(.setBarsHidden(hidden))
    }

    func resetBars(animated: Bool) {
        receivedMessages.append(.resetBars)
    }

    func setNavigationBarHidden(_ hidden: Bool) {
        receivedMessages.append(.setNavigationBarHidden(hidden))
    }

    func setBarsVisibility(_ percent: CGFloat, animated: Bool) {
        receivedMessages.append(.setBarsVisibility(percent))
        if !animated {
            currentBarsVisibility = percent
        }
    }

    func setRefreshControlEnabled(_ isEnabled: Bool) {
        receivedMessages.append(.setRefreshControlEnabled(isEnabled))
    }

    func setUnifiedInputContentOverlaySuppressed(_ suppressed: Bool) {
        // no-op
    }

    var canHideBars: Bool = false

    var isChromeScrollInteractionDisabled: Bool = false

    var isToolbarHidden: Bool = false

    var currentBarsVisibility: CGFloat = 1

    var toolbarHeight: CGFloat = 0

    var barsMaxHeight: CGFloat = 0

    var isInMinimalChromeLayout: Bool = false

    var isFloatingChromeEnabled: Bool = false

    func floatingWebViewBottomObscuredHeight(for barsVisibilityPercent: CGFloat) -> CGFloat { 0 }

    func floatingWebViewObscuredInsets(for barsVisibilityPercent: CGFloat) -> UIEdgeInsets { .zero }

    var omniBar: OmniBar = {
        let omniBar = MockOmniBar()
        omniBar.mockBarView.expectedHeight = 52
        return omniBar
    }()

    var tabBarContainer: UIView = UIView()
}
