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

    /// Below `Metrics.floatingSnapCommitDistance` the chrome still tracks the finger live, exactly like
    /// before -- the commit-and-snap behaviour (covered separately below) only kicks in once a drag
    /// crosses that distance.
    func testWhenScrollingBelowTheCommitThresholdThenBarsTrackProportionally() throws {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let subThreshold = BarsAnimator.Metrics.floatingSnapCommitDistance / 2

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        scroll(sut, scrollView, clock, to: stride(from: subThreshold / 4, through: subThreshold, by: subThreshold / 4))

        XCTAssertEqual(sut.barsState, .transitioning)
        XCTAssertEqual(try XCTUnwrap(delegate.receivedMessages.last?.percent), 1.0 - (subThreshold / travel), accuracy: 0.001)
    }

    /// `combinedBarsHeight` is ~188pt with a bottom address bar but ~122pt with a top one, so gearing off
    /// it would collapse the two positions at different speeds. The travel is absolute precisely to avoid
    /// that, and this is the regression test for it. Kept below the commit threshold so it's still
    /// exercising live tracking rather than the snap.
    func testWhenBarHeightDiffersThenTravelDistanceIsUnchanged() throws {
        var finalPercents: [CGFloat] = []
        let subThreshold = BarsAnimator.Metrics.floatingSnapCommitDistance / 2

        for toolbarHeight in [CGFloat(128), CGFloat(62)] {
            let (sut, delegate, clock) = makeFloatingSUT()
            delegate.toolbarHeight = toolbarHeight
            let scrollView = mockTallScrollView()

            scrollView.contentOffset.y = 0
            sut.didStartScrolling(in: scrollView)
            scroll(sut, scrollView, clock, to: stride(from: subThreshold / 4, through: subThreshold, by: subThreshold / 4))

            finalPercents.append(try XCTUnwrap(delegate.receivedMessages.last?.percent))
        }

        XCTAssertEqual(finalPercents[0], finalPercents[1], accuracy: 0.001)
    }

    /// Holds only while the per-frame scroll stays inside the collapse rate cap — above it the cap
    /// deliberately throttles, superseded once a drag crosses the commit distance (see
    /// `testWhenScrollJumpsFarPastTheCommitThresholdInASingleFrameThenChromeSnapsImmediately`). Both step
    /// sizes divide the sub-threshold distance exactly so the runs end on the same offset.
    func testWhenFrameStepSizeDiffersThenFinalProgressIsUnchanged() throws {
        var finalPercents: [CGFloat] = []
        let subThreshold = BarsAnimator.Metrics.floatingSnapCommitDistance / 2

        for step in [CGFloat(2), CGFloat(4)] {
            let (sut, delegate, clock) = makeFloatingSUT()
            let scrollView = mockTallScrollView()

            scrollView.contentOffset.y = 0
            sut.didStartScrolling(in: scrollView)
            scroll(sut, scrollView, clock, to: stride(from: step, through: subThreshold, by: step))

            finalPercents.append(try XCTUnwrap(delegate.receivedMessages.last?.percent))
        }

        XCTAssertEqual(finalPercents[0], finalPercents[1], accuracy: 0.001)
    }

    /// The legacy formula re-seeded from `transitionSpeed * transitionProgress`, so a second drag resumed
    /// at half the progress it had visually reached. Kept below the commit threshold so the drag is still
    /// live-tracking, not already snapped, when it's interrupted.
    func testWhenDragIsInterruptedThenProgressResumesWhereItLeftOff() throws {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let subThreshold = BarsAnimator.Metrics.floatingSnapCommitDistance / 2

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        scroll(sut, scrollView, clock, to: stride(from: subThreshold / 4, through: subThreshold, by: subThreshold / 4))
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

    /// The core of the "snap once you start scrolling" feature: a drag doesn't need to reach the full
    /// travel distance, or even a second frame, before the chrome fully commits. This is what stops the
    /// bar from ever parking at a half-transitioned position if the user holds the scroll steady mid-drag
    /// without lifting -- by the time they could hold anything, the commit (and its animation) already
    /// fired.
    func testWhenScrollJumpsFarPastTheCommitThresholdInASingleFrameThenChromeSnapsImmediately() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)

        // Far past the commit threshold in a single frame, as a real fast flick would be.
        scrollView.contentOffset.y = 1000
        clock.advance(by: 1.0 / 60.0)
        sut.didScroll(in: scrollView)

        XCTAssertEqual(sut.barsState, .hidden, "Crossing the commit threshold, even within one frame, must snap immediately rather than waiting for release")
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(0.0))
    }

    /// Symmetric case: revealing from hidden also snaps immediately once the drag crosses the commit
    /// threshold, without needing `didFinishScrolling` to ever be called.
    func testWhenScrollJumpsFarPastTheCommitThresholdWhileHiddenThenChromeRevealsImmediately() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()

        sut.hideBars(animated: false)
        delegate.receivedMessages.removeAll()
        scrollView.contentOffset.y = 500
        sut.didStartScrolling(in: scrollView)

        scrollView.contentOffset.y = 0
        clock.advance(by: 1.0 / 60.0)
        sut.didScroll(in: scrollView)

        XCTAssertEqual(sut.barsState, .revealed)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(1.0))
    }

    /// Once committed, holding the scroll steady (no further `didScroll` calls, finger still down) must
    /// not undo or re-litigate the commit -- this is the exact "held mid-way" scenario the feature exists
    /// to fix, just expressed as "nothing changes" rather than "something animates," since the commit
    /// animation itself already ran to completion independent of further scroll events.
    func testWhenScrollHoldsSteadyAfterCommitThenStateStaysCommitted() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let commit = BarsAnimator.Metrics.floatingSnapCommitDistance

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        advanceOffset(sut, scrollView, clock, to: commit + 4)
        XCTAssertEqual(sut.barsState, .hidden)

        let messageCountAtCommit = delegate.receivedMessages.count
        clock.advance(by: 1.0 / 60.0)
        sut.didScroll(in: scrollView) // offset unchanged: finger held steady mid-drag

        XCTAssertEqual(sut.barsState, .hidden)
        XCTAssertEqual(delegate.receivedMessages.count, messageCountAtCommit, "A held, unmoving scroll must not re-trigger the commit")
    }

    /// Reversing far enough past the point of commit flips the commitment, and this must keep working
    /// across any number of reversals within one continuous drag (finger never lifted) -- the scenario
    /// that used to defeat the legacy re-anchoring formula for live tracking, now replayed against the
    /// commit/snap model.
    func testWhenReversingPastTheCommitThresholdMultipleTimesThenFinalStateMatchesLastDirection() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let commit = BarsAnimator.Metrics.floatingSnapCommitDistance

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)

        // Down past the commit threshold: collapses immediately, without waiting for release.
        advanceOffset(sut, scrollView, clock, to: commit + 4)
        XCTAssertEqual(sut.barsState, .hidden)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(0.0))

        // ...reverse far enough past the commit point to flip to revealing...
        advanceOffset(sut, scrollView, clock, to: 0)
        XCTAssertEqual(sut.barsState, .revealed)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(1.0))

        // ...and back down again, never having lifted the finger.
        advanceOffset(sut, scrollView, clock, to: commit + 4)
        XCTAssertEqual(sut.barsState, .hidden)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(0.0))
    }

    // MARK: - Release precision

    /// The bug this guards: gating the progress-based decision on `velocity == 0` means a real touch
    /// release (which is essentially never exactly zero) is decided by the sign of noise, not by how
    /// far the user actually dragged. Now that a real drag commits well before halfway (see the snap
    /// tests above), a release that's still `.transitioning` can only be at a small progress -- so with
    /// noise velocity in either direction, it should always reveal.
    func testWhenReleaseVelocityIsBelowCommitThresholdWhileStillUncommittedThenBarsReveal() {
        let subThreshold = BarsAnimator.Metrics.floatingSnapCommitDistance / 2

        for velocitySign: CGFloat in [1, -1] {
            let (sut, delegate, clock) = makeFloatingSUT()
            let scrollView = mockTallScrollView()

            scrollView.contentOffset.y = 0
            sut.didStartScrolling(in: scrollView)
            advanceOffset(sut, scrollView, clock, to: subThreshold)
            XCTAssertEqual(sut.barsState, .transitioning)

            let noiseVelocity = velocitySign * (BarsAnimator.Metrics.floatingVelocityCommitThreshold - 0.01)
            sut.didFinishScrolling(in: scrollView, velocity: noiseVelocity)

            XCTAssertEqual(sut.barsState, .revealed, "velocity sign \(velocitySign)")
            XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(1.0))
        }
    }

    func testWhenReleaseVelocityIsAboveCommitThresholdThenDirectionWins() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let subThreshold = BarsAnimator.Metrics.floatingSnapCommitDistance / 2

        // Only a small fraction collapsed -- progress alone would reveal -- but a real flick still commits to hiding.
        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        sut.didScroll(in: scrollView) // primes lastProgressTimestamp
        scrollView.contentOffset.y = subThreshold
        clock.advance(by: 1.0)
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .transitioning, "Must still be below the commit threshold for this test to be meaningful")

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
        let subThreshold = BarsAnimator.Metrics.floatingSnapCommitDistance / 2

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        sut.didScroll(in: scrollView) // primes lastProgressTimestamp
        scrollView.contentOffset.y = subThreshold
        clock.advance(by: 1.0)
        sut.didScroll(in: scrollView)

        sut.didFinishScrolling(in: scrollView, velocity: BarsAnimator.Metrics.floatingVelocityCommitThreshold)

        XCTAssertEqual(delegate.lastAnimationDuration ?? -1, CGFloat(delegate.floatingMorphCollapseDuration), accuracy: 0.001)
    }

    func testWhenFlickVelocityIsAtOrAboveTheReferenceThenDurationIsTheFastestFloor() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let subThreshold = BarsAnimator.Metrics.floatingSnapCommitDistance / 2

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        sut.didScroll(in: scrollView) // primes lastProgressTimestamp
        scrollView.contentOffset.y = subThreshold
        clock.advance(by: 1.0)
        sut.didScroll(in: scrollView)

        sut.didFinishScrolling(in: scrollView, velocity: BarsAnimator.Metrics.flickReferenceVelocity + 5)

        XCTAssertEqual(delegate.lastAnimationDuration ?? -1, CGFloat(BarsAnimator.Metrics.flickFastestCollapseDuration), accuracy: 0.001)
    }

    func testWhenFlickVelocityIsBetweenTheThresholdsThenDurationIsBetweenBaseAndFastest() {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let subThreshold = BarsAnimator.Metrics.floatingSnapCommitDistance / 2

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)
        sut.didScroll(in: scrollView) // primes lastProgressTimestamp
        scrollView.contentOffset.y = subThreshold
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
            let subThreshold = BarsAnimator.Metrics.floatingSnapCommitDistance / 2

            scrollView.contentOffset.y = 0
            sut.didStartScrolling(in: scrollView)
            sut.didScroll(in: scrollView) // primes lastProgressTimestamp
            scrollView.contentOffset.y = subThreshold
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
    /// single fixed anchor for the whole drag, reversing direction within one continuous touch must keep
    /// tracking live below the commit threshold -- not fall through a re-entry guard that compares against
    /// a start position that's now stale after the first reversal. (Reversal *after* commit is covered by
    /// `testWhenReversingPastTheCommitThresholdMultipleTimesThenFinalStateMatchesLastDirection` above.)
    func testWhenReversingDirectionBelowTheCommitThresholdThenTrackingNeverStalls() throws {
        let (sut, delegate, clock) = makeFloatingSUT()
        let scrollView = mockTallScrollView()
        let subThreshold = BarsAnimator.Metrics.floatingSnapCommitDistance / 2

        scrollView.contentOffset.y = 0
        sut.didStartScrolling(in: scrollView)

        // Down (collapsing)...
        advanceOffset(sut, scrollView, clock, to: subThreshold)
        XCTAssertEqual(sut.barsState, .transitioning)
        let collapsingPercent = try XCTUnwrap(delegate.receivedMessages.last?.percent)

        // ...up (revealing), never having lifted the finger.
        advanceOffset(sut, scrollView, clock, to: subThreshold / 4)
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
