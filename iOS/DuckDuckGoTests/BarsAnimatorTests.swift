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

/// The floating chrome uses a different gearing: an absolute 80pt of scroll for a full transition,
/// measured statelessly from the transition's anchor rather than compounded per frame.
class BarsAnimatorFloatingTests: XCTestCase {

    private let travel = BarsAnimator.Metrics.floatingTransitionTravel

    func testWhenScrollingTheFullTravelDistanceThenBarsAreFullyHidden() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)

        // Spread over enough frames that the collapse rate limiter never binds.
        scroll(sut, scrollView, clock, to: stride(from: 10.0, through: travel, by: 10.0))

        XCTAssertEqual(sut.barsState, .hidden)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(0.0))
    }

    func testWhenScrollingHalfTheTravelDistanceThenBarsAreHalfVisible() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        scroll(sut, scrollView, clock, to: stride(from: 10.0, through: travel / 2, by: 10.0))

        XCTAssertEqual(sut.barsState, .transitioning)
        XCTAssertEqual(try XCTUnwrap(delegate.receivedMessages.last?.percent), 0.5, accuracy: 0.001)
    }

    /// `combinedBarsHeight` is ~188pt with a bottom address bar but ~122pt with a top one, so gearing off
    /// it would collapse the two positions at different speeds. The travel is absolute precisely to avoid
    /// that, and this is the regression test for it.
    func testWhenBarHeightDiffersThenTravelDistanceIsUnchanged() throws {
        var finalPercents: [CGFloat] = []

        for toolbarHeight in [CGFloat(128), CGFloat(62)] {
            let (sut, delegate, clock) = makeFloatingSUT()
            delegate.toolbarHeight = toolbarHeight
            let scrollView = mockTallScrollView()

            scrollView.contentOffset.y = 0
            sut.didStartScrolling(in: scrollView)
            scroll(sut, scrollView, clock, to: stride(from: 10.0, through: travel / 2, by: 10.0))

            finalPercents.append(try XCTUnwrap(delegate.receivedMessages.last?.percent))
        }

        XCTAssertEqual(finalPercents[0], finalPercents[1], accuracy: 0.001)
    }

    /// Holds only while the per-frame scroll stays inside the collapse rate cap — above it the cap
    /// deliberately throttles, which `testWhenFlickIsFasterThanTheRateCapThenProgressIsLimited` covers.
    /// Both step sizes divide the half-travel exactly so the runs end on the same offset.
    func testWhenFrameStepSizeDiffersThenFinalProgressIsUnchanged() throws {
        var finalPercents: [CGFloat] = []

        for step in [CGFloat(5), CGFloat(10)] {
            let (sut, delegate, clock) = makeFloatingSUT()
            let scrollView = mockTallScrollView()

            scrollView.contentOffset.y = 0
            sut.didStartScrolling(in: scrollView)
            scroll(sut, scrollView, clock, to: stride(from: step, through: travel / 2, by: step))

            finalPercents.append(try XCTUnwrap(delegate.receivedMessages.last?.percent))
        }

        XCTAssertEqual(finalPercents[0], finalPercents[1], accuracy: 0.001)
    }

    /// The legacy formula re-seeded from `transitionSpeed * transitionProgress`, so a second drag resumed
    /// at half the progress it had visually reached.
    func testWhenDragIsInterruptedThenProgressResumesWhereItLeftOff() throws {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        scroll(sut, scrollView, clock, to: stride(from: 10.0, through: travel / 2, by: 10.0))
        let interruptedPercent = try XCTUnwrap(delegate.receivedMessages.last?.percent)

        // Lift and start a fresh drag from the same offset.
        sut.didStartScrolling(in: scrollView)
        clock.advance(by: 1.0 / 60.0)
        sut.didScroll(in: scrollView)

        XCTAssertEqual(try XCTUnwrap(delegate.receivedMessages.last?.percent), interruptedPercent, accuracy: 0.001)
    }

    /// Previously the first pixel of top overscroll yielded `0.5 * transitionProgress`, snapping the chrome
    /// to half visible in a single frame before it began tracking.
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

    func testWhenFlickIsFasterThanTheRateCapThenProgressIsLimited() throws {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)

        // Far past the full travel in a single frame — uncapped this would complete instantly.
        scrollView.contentOffset.y = 1000
        clock.advance(by: 1.0 / 60.0)
        sut.didScroll(in: scrollView)

        let maxStep = BarsAnimator.Metrics.maxCollapseProgressPerSecond * CGFloat(1.0 / 60.0)
        let percent = try XCTUnwrap(delegate.receivedMessages.last?.percent)
        XCTAssertEqual(percent, 1.0 - maxStep, accuracy: 0.001)
        XCTAssertNotEqual(sut.barsState, .hidden, "A single frame must not complete the collapse")
    }

    // MARK: - Release precision

    /// The bug this guards: gating the progress-based decision on `velocity == 0` means a real touch
    /// release (which is essentially never exactly zero) is decided by the sign of noise, not by how
    /// far the user actually dragged.
    func testWhenReleaseVelocityIsBelowCommitThresholdThenOutcomeIsDecidedByProgress() {
        let cases: [(progress: CGFloat, velocitySign: CGFloat, expected: BarsAnimator.State)] = [
            (0.6, 1, .hidden),    // past halfway, released with noise velocity in the "continue" direction
            (0.6, -1, .hidden),   // ...and in the "reverse" direction: progress wins either way
            (0.4, 1, .revealed),
            (0.4, -1, .revealed),
        ]

        for testCase in cases {
            let (sut, delegate, clock) = makeFloatingSUT()
            let scrollView = mockTallScrollView()
            let travel = BarsAnimator.Metrics.floatingTransitionTravel

            scrollView.contentOffset.y = 0
            sut.didStartScrolling(in: scrollView)
            advanceOffset(sut, scrollView, clock, to: travel * testCase.progress)
            XCTAssertEqual(sut.transitionProgressForTesting, testCase.progress, accuracy: 0.01)
            XCTAssertEqual(sut.barsState, .transitioning)

            let noiseVelocity = testCase.velocitySign * (BarsAnimator.Metrics.floatingVelocityCommitThreshold - 0.01)
            sut.didFinishScrolling(in: scrollView, velocity: noiseVelocity)

            XCTAssertEqual(sut.barsState, testCase.expected,
                          "progress \(testCase.progress), velocity sign \(testCase.velocitySign)")
            XCTAssertEqual(delegate.receivedMessages.last,
                          .setBarsVisibility(testCase.expected == .hidden ? 0.0 : 1.0))
        }
    }

    func testWhenReleaseVelocityIsAboveCommitThresholdThenDirectionWins() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let travel = BarsAnimator.Metrics.floatingTransitionTravel

        // Only 20% collapsed -- progress alone would reveal -- but a real flick still commits to hiding.
        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        sut.didScroll(in: scrollView) // primes lastProgressTimestamp
        scrollView.contentOffset.y = travel * 0.2
        clock.advance(by: 1.0)
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.transitionProgressForTesting, 0.2, accuracy: 0.01)

        sut.didFinishScrolling(in: scrollView, velocity: BarsAnimator.Metrics.floatingVelocityCommitThreshold + 0.1)

        XCTAssertEqual(sut.barsState, .hidden)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(0.0))
    }

    // MARK: - Velocity-scaled settle duration

    /// A release right at the commit threshold should feel continuous with a deliberate release: same
    /// duration as the unscaled default (which the deliberate branch always uses).
    func testWhenFlickVelocityIsAtTheCommitThresholdThenDurationMatchesTheBase() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let travel = BarsAnimator.Metrics.floatingTransitionTravel

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        sut.didScroll(in: scrollView) // primes lastProgressTimestamp
        scrollView.contentOffset.y = travel * 0.2
        clock.advance(by: 1.0)
        sut.didScroll(in: scrollView)

        sut.didFinishScrolling(in: scrollView, velocity: BarsAnimator.Metrics.floatingVelocityCommitThreshold)

        XCTAssertEqual(delegate.lastAnimationDuration ?? -1, CGFloat(delegate.floatingMorphCollapseDuration), accuracy: 0.001)
    }

    func testWhenFlickVelocityIsAtOrAboveTheReferenceThenDurationIsTheFastestFloor() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let travel = BarsAnimator.Metrics.floatingTransitionTravel

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        sut.didScroll(in: scrollView) // primes lastProgressTimestamp
        scrollView.contentOffset.y = travel * 0.2
        clock.advance(by: 1.0)
        sut.didScroll(in: scrollView)

        sut.didFinishScrolling(in: scrollView, velocity: BarsAnimator.Metrics.flickReferenceVelocity + 5)

        XCTAssertEqual(delegate.lastAnimationDuration ?? -1, CGFloat(BarsAnimator.Metrics.flickFastestCollapseDuration), accuracy: 0.001)
    }

    func testWhenFlickVelocityIsBetweenTheThresholdsThenDurationIsBetweenBaseAndFastest() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let travel = BarsAnimator.Metrics.floatingTransitionTravel

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        sut.didScroll(in: scrollView) // primes lastProgressTimestamp
        scrollView.contentOffset.y = travel * 0.2
        clock.advance(by: 1.0)
        sut.didScroll(in: scrollView)

        let midVelocity = (BarsAnimator.Metrics.floatingVelocityCommitThreshold + BarsAnimator.Metrics.flickReferenceVelocity) / 2
        sut.didFinishScrolling(in: scrollView, velocity: midVelocity)

        let duration = try? XCTUnwrap(delegate.lastAnimationDuration)
        XCTAssertNotNil(duration)
        if let duration {
            XCTAssertLessThan(duration, CGFloat(delegate.floatingMorphCollapseDuration))
            XCTAssertGreaterThan(duration, CGFloat(BarsAnimator.Metrics.flickFastestCollapseDuration))
        }
    }

    func testWhenFasterFlickThenDurationIsShorter() throws {
        func finishDrag(withVelocity velocity: CGFloat) -> CGFloat? {
            let (sut, delegate, clock) = makeFloatingSUT()
            let scrollView = mockTallScrollView()
            let travel = BarsAnimator.Metrics.floatingTransitionTravel

            scrollView.contentOffset.y = 0
            sut.didStartScrolling(in: scrollView)
            sut.didScroll(in: scrollView) // primes lastProgressTimestamp
            scrollView.contentOffset.y = travel * 0.2
            clock.advance(by: 1.0)
            sut.didScroll(in: scrollView)

            sut.didFinishScrolling(in: scrollView, velocity: velocity)
            return delegate.lastAnimationDuration
        }

        let slowDuration = try XCTUnwrap(finishDrag(withVelocity: BarsAnimator.Metrics.floatingVelocityCommitThreshold + 0.05))
        let fastDuration = try XCTUnwrap(finishDrag(withVelocity: BarsAnimator.Metrics.flickReferenceVelocity))

        XCTAssertLessThan(fastDuration, slowDuration, "A firmer flick should settle faster, matching how fast the content was already moving")
    }

    // MARK: - In-drag reveal (live, unified tracking)

    /// The core fix: reveal tracks live from the very first pixel of upward travel, exactly like
    /// collapse does -- no hard distance gate before anything visibly happens.
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

    /// Regression test for the "continuous gesture, transitions won't happen sometimes" report: with a
    /// single fixed anchor for the whole drag, reversing direction any number of times within one
    /// continuous touch must keep tracking live -- not fall through a re-entry guard that compares
    /// against a start position that's now stale after the first reversal.
    func testWhenReversingDirectionMultipleTimesWithinOneDragThenTrackingNeverStalls() throws {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let travel = BarsAnimator.Metrics.floatingTransitionTravel

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)

        // Down (collapsing)... each leg is stepped in small increments (see `advanceOffset`) so the
        // collapse-direction rate limiter -- tuned for realistic frame deltas, capped per call
        // regardless of how much wall-clock time a single big jump claims to cover -- never binds.
        // That cap is separate, already-covered behaviour, not what this test is checking.
        advanceOffset(sut, scrollView, clock, to: travel * 0.3)
        XCTAssertEqual(try XCTUnwrap(delegate.receivedMessages.last?.percent), 0.7, accuracy: 0.01)

        // ...up (revealing)...
        advanceOffset(sut, scrollView, clock, to: travel * 0.1)
        XCTAssertEqual(try XCTUnwrap(delegate.receivedMessages.last?.percent), 0.9, accuracy: 0.01,
                      "Must keep tracking after the first reversal, not stall")

        // ...down again (collapsing again)...
        advanceOffset(sut, scrollView, clock, to: travel * 0.5)
        XCTAssertEqual(try XCTUnwrap(delegate.receivedMessages.last?.percent), 0.5, accuracy: 0.01,
                      "Must keep tracking after the second reversal too")

        // ...up again (revealing again), never having lifted the finger.
        advanceOffset(sut, scrollView, clock, to: 0)
        XCTAssertEqual(sut.barsState, .revealed)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(1.0))
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

    // MARK: - Helpers

    private func scroll<Offsets: Sequence>(_ sut: BarsAnimator,
                                           _ scrollView: UIScrollView,
                                           _ clock: TestClock,
                                           to offsets: Offsets) where Offsets.Element == CGFloat {
        for offset in offsets {
            scrollView.contentOffset.y = offset
            clock.advance(by: BarsAnimator.Metrics.maxRateLimitTimeStep)
            sut.didScroll(in: scrollView)
        }
    }

    /// Steps the offset from its current value to `targetOffset` in small increments, each separated
    /// by a full `maxRateLimitTimeStep` frame, so the collapse-direction rate limiter (capped at
    /// `maxCollapseProgressPerSecond * maxRateLimitTimeStep` progress per call, regardless of how much
    /// wall-clock time a single big jump claims to cover) never binds, and the final progress lands
    /// exactly on what the offset implies.
    private func advanceOffset(_ sut: BarsAnimator,
                               _ scrollView: UIScrollView,
                               _ clock: TestClock,
                               to targetOffset: CGFloat,
                               steps: Int = 20) {
        let start = scrollView.contentOffset.y
        for step in 1...steps {
            scrollView.contentOffset.y = start + (targetOffset - start) * CGFloat(step) / CGFloat(steps)
            clock.advance(by: BarsAnimator.Metrics.maxRateLimitTimeStep)
            sut.didScroll(in: scrollView)
        }
    }
}

// MARK: - Helpers

/// Tall enough that `revealedAndScrolling`'s bottom-of-page guard (which reserves
/// `combinedBarsHeight` for the bottom-bounce gesture) never fires during these tests.
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
    let sut = BarsAnimator(currentTime: { clock.now })
    let delegate = BrowserChromeDelegateMock()
    delegate.isFloatingChromeEnabled = true
    // Bottom floating address bar metrics: the omnibar is embedded in the toolbar, so its height is
    // already inside `toolbarHeight`.
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
