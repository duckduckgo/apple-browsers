//
//  WebScrollObserverTests.swift
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
import UIKit
import Core
@testable import DuckDuckGo

/// Drives `WebScrollObserver.classifyDrag` directly (the synchronous classification entry) to validate the
/// symptom-pixel logic — failure streak, the ≥2-region spatial-spread gate, the 30s streak window, and
/// eligibility — without simulating real touches or the post-gesture async recheck.
@MainActor
final class WebScrollObserverTests: XCTestCase {

    private var container: UIView!
    private var scrollView: UIScrollView!
    private var url: URL?
    private var currentDate: Date!
    private var firedPixels: [(event: Pixel.Event, params: [String: String])] = []

    override func setUp() {
        super.setUp()
        // Container height 600 → screen regions are thirds at y<200 / 200..<400 / ≥400.
        container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        // A genuinely scrollable page: 2000pt content in a 600pt viewport → ~1400pt of range.
        scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        scrollView.contentSize = CGSize(width: 390, height: 2000)
        scrollView.contentOffset = CGPoint(x: 0, y: 100)
        url = URL(string: "https://example.com")
        currentDate = Date(timeIntervalSince1970: 1_000_000)
        firedPixels = []
    }

    override func tearDown() {
        container = nil
        scrollView = nil
        url = nil
        currentDate = nil
        firedPixels = []
        super.tearDown()
    }

    private func makeObserver() -> WebScrollObserver {
        WebScrollObserver(container: container,
                          scrollView: { [weak self] in self?.scrollView },
                          currentURL: { [weak self] in self?.url },
                          firePixelDailyAndCount: { [weak self] event, params in
                              self?.firedPixels.append((event, params))
                          },
                          now: { [weak self] in self?.currentDate ?? Date() })
    }

    /// A failed (non-moving) upward drag starting at the given screen-Y. `contentOffset` is left at the
    /// start offset so the observer sees zero movement.
    private func failedDrag(at startScreenY: CGFloat, on observer: WebScrollObserver) {
        scrollView.contentOffset = CGPoint(x: 0, y: 100)
        observer.classifyDrag(dx: 0, dy: -100, startOffsetY: 100, startScreenY: startScreenY)
    }

    func testThreeFailedDragsAcrossTwoRegionsFiresSymptomPixel() {
        let observer = makeObserver()

        failedDrag(at: 100, on: observer) // region 0
        failedDrag(at: 300, on: observer) // region 1
        XCTAssertTrue(firedPixels.isEmpty, "Should not fire before the streak threshold")

        failedDrag(at: 500, on: observer) // region 2 → streak 3, spans 3 regions

        XCTAssertEqual(firedPixels.count, 1)
        XCTAssertEqual(firedPixels.first?.event, .debugInteractionRepeatedFailedScroll)
        XCTAssertEqual(firedPixels.first?.params["attempt_count_bucket"], "3")
        XCTAssertEqual(firedPixels.first?.params["direction"], "up")
        XCTAssertEqual(firedPixels.first?.params["mechanism"], "none_wedged")
    }

    func testFailedDragsInOneRegionDoNotFire() {
        let observer = makeObserver()

        failedDrag(at: 100, on: observer)
        failedDrag(at: 100, on: observer)
        failedDrag(at: 100, on: observer)
        failedDrag(at: 100, on: observer)

        XCTAssertTrue(firedPixels.isEmpty, "A single-region streak is benign and must not fire")
    }

    func testSuccessfulDragResetsTheStreak() {
        let observer = makeObserver()

        failedDrag(at: 100, on: observer) // region 0, streak 1
        failedDrag(at: 300, on: observer) // region 1, streak 2

        // A drag that actually scrolls (content moved well beyond the 3pt threshold) resets the streak.
        scrollView.contentOffset = CGPoint(x: 0, y: 100)
        observer.classifyDrag(dx: 0, dy: -100, startOffsetY: 0, startScreenY: 100)

        // Two more failures across two regions → only streak 2 again, so still below threshold.
        failedDrag(at: 100, on: observer)
        failedDrag(at: 300, on: observer)

        XCTAssertTrue(firedPixels.isEmpty, "A successful scroll must reset the failure streak")
    }

    func testStreakWindowExpiryResetsBeforeFiring() {
        let observer = makeObserver()

        failedDrag(at: 100, on: observer) // region 0
        failedDrag(at: 300, on: observer) // region 1

        // More than the 30s streak window later, the next failure restarts the streak from 1.
        currentDate = currentDate.addingTimeInterval(31)
        failedDrag(at: 500, on: observer) // region 2, but streak reset to 1

        XCTAssertTrue(firedPixels.isEmpty, "A gap beyond the streak window must reset before firing")
    }

    func testNonHTTPPageIsIneligible() {
        url = URL(string: "duck://player")
        let observer = makeObserver()

        failedDrag(at: 100, on: observer)
        failedDrag(at: 300, on: observer)
        failedDrag(at: 500, on: observer)

        XCTAssertTrue(firedPixels.isEmpty, "Non-http(s) pages are not eligible for symptom detection")
    }

    func testShortOrHorizontalDragIsIgnored() {
        let observer = makeObserver()

        // Below the 48pt vertical threshold.
        observer.classifyDrag(dx: 0, dy: -20, startOffsetY: 100, startScreenY: 100)
        // Horizontally dominant.
        observer.classifyDrag(dx: -200, dy: -60, startOffsetY: 100, startScreenY: 300)
        observer.classifyDrag(dx: -200, dy: -60, startOffsetY: 100, startScreenY: 500)

        XCTAssertTrue(firedPixels.isEmpty, "Short or horizontal drags are not scroll attempts")
    }

    func testNormalScrollsNeverFirePixel() {
        let observer = makeObserver()

        // 20 successful scrolls across all three screen regions — content moves each time.
        for i in 0..<20 {
            let startY: CGFloat = 100
            scrollView.contentOffset = CGPoint(x: 0, y: startY + 100)
            let screenY = CGFloat([100, 300, 500][i % 3])
            observer.classifyDrag(dx: 0, dy: -100, startOffsetY: startY, startScreenY: screenY)
        }

        XCTAssertTrue(firedPixels.isEmpty,
                      "m_debug_interaction_repeated_failed_scroll must not fire for successful scrolls")
    }
}

// MARK: - Bucket helper tests

/// Tests for the classification/bucket helpers that are `internal` (visible via `@testable import`).
@MainActor
final class WebScrollObserverBucketTests: XCTestCase {

    // MARK: attemptBucket

    func testAttemptBucket_threeReturnsThree() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let scrollView = UIScrollView()
        let observer = WebScrollObserver(container: container,
                                         scrollView: { scrollView },
                                         currentURL: { nil })
        XCTAssertEqual(observer.attemptBucket(3), "3")
    }

    func testAttemptBucket_belowThresholdAlsoReturnsThree() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let observer = WebScrollObserver(container: container,
                                         scrollView: { nil },
                                         currentURL: { nil })
        // The method uses `..<4` — values 1, 2, 3 all map to "3".
        XCTAssertEqual(observer.attemptBucket(1), "3")
        XCTAssertEqual(observer.attemptBucket(2), "3")
    }

    func testAttemptBucket_fourAndFiveReturnFourFive() {
        let observer = WebScrollObserver(container: UIView(),
                                         scrollView: { nil },
                                         currentURL: { nil })
        XCTAssertEqual(observer.attemptBucket(4), "4_5")
        XCTAssertEqual(observer.attemptBucket(5), "4_5")
    }

    func testAttemptBucket_sixAndAboveReturnSixPlus() {
        let observer = WebScrollObserver(container: UIView(),
                                         scrollView: { nil },
                                         currentURL: { nil })
        XCTAssertEqual(observer.attemptBucket(6), "6_plus")
        XCTAssertEqual(observer.attemptBucket(100), "6_plus")
    }

    // MARK: screenRegion(forY:)

    func testScreenRegion_topThirdIsRegionZero() {
        // Container height 600 → thirds at [0,200), [200,400), [400,600].
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let observer = WebScrollObserver(container: container,
                                         scrollView: { nil },
                                         currentURL: { nil })
        XCTAssertEqual(observer.screenRegion(forY: 0), 0)
        XCTAssertEqual(observer.screenRegion(forY: 100), 0)
        XCTAssertEqual(observer.screenRegion(forY: 199), 0)
    }

    func testScreenRegion_middleThirdIsRegionOne() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let observer = WebScrollObserver(container: container,
                                         scrollView: { nil },
                                         currentURL: { nil })
        XCTAssertEqual(observer.screenRegion(forY: 200), 1)
        XCTAssertEqual(observer.screenRegion(forY: 300), 1)
        XCTAssertEqual(observer.screenRegion(forY: 399), 1)
    }

    func testScreenRegion_bottomThirdIsRegionTwo() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let observer = WebScrollObserver(container: container,
                                         scrollView: { nil },
                                         currentURL: { nil })
        XCTAssertEqual(observer.screenRegion(forY: 400), 2)
        XCTAssertEqual(observer.screenRegion(forY: 500), 2)
        XCTAssertEqual(observer.screenRegion(forY: 600), 2)
    }

    func testScreenRegion_clampsBelowZero() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let observer = WebScrollObserver(container: container,
                                         scrollView: { nil },
                                         currentURL: { nil })
        // Negative Y is possible on a rubber-band bounce — must not produce a region below 0.
        XCTAssertEqual(observer.screenRegion(forY: -50), 0)
    }

    func testScreenRegion_clampsAboveTwo() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let observer = WebScrollObserver(container: container,
                                         scrollView: { nil },
                                         currentURL: { nil })
        XCTAssertEqual(observer.screenRegion(forY: 1000), 2)
    }

    // MARK: webScrollPanState

    func testWebScrollPanState_nilScrollViewReturnsNone() {
        let observer = WebScrollObserver(container: UIView(),
                                         scrollView: { nil },
                                         currentURL: { nil })
        XCTAssertEqual(observer.webScrollPanState(nil), "none")
    }

    func testWebScrollPanState_freshScrollViewReturnsPossible() {
        let sv = UIScrollView()
        let observer = WebScrollObserver(container: UIView(),
                                         scrollView: { sv },
                                         currentURL: { nil })
        // A freshly-created UIScrollView's pan recognizer starts in .possible.
        XCTAssertEqual(observer.webScrollPanState(sv), "possible")
    }

    // MARK: webScrollPanTouches

    func testWebScrollPanTouches_nilScrollViewReturnsZero() {
        let observer = WebScrollObserver(container: UIView(),
                                         scrollView: { nil },
                                         currentURL: { nil })
        XCTAssertEqual(observer.webScrollPanTouches(nil), "0")
    }

    func testWebScrollPanTouches_idleScrollViewReturnsZero() {
        let sv = UIScrollView()
        let observer = WebScrollObserver(container: UIView(),
                                         scrollView: { sv },
                                         currentURL: { nil })
        // A pan recognizer with no active touches reports numberOfTouches == 0.
        XCTAssertEqual(observer.webScrollPanTouches(sv), "0")
    }

    // MARK: count → bucket mapping (possibleZeroTouchCountBucket / windowActiveNoTouchBucket)
    // The live scans behind these params walk UIApplication.shared.connectedScenes, whose recognizer
    // state isn't controllable in a test host (the app host has real WebKit recognizers), so we test the
    // pure count→bucket mapping directly rather than asserting a host-dependent live count.

    func testCountBucket3PlusThresholds() {
        XCTAssertEqual(WebScrollObserver.countBucket3Plus(0), "0")
        XCTAssertEqual(WebScrollObserver.countBucket3Plus(1), "1")
        XCTAssertEqual(WebScrollObserver.countBucket3Plus(2), "2")
        XCTAssertEqual(WebScrollObserver.countBucket3Plus(3), "3_plus")
        XCTAssertEqual(WebScrollObserver.countBucket3Plus(99), "3_plus")
    }

    func testCountBucket2PlusThresholds() {
        XCTAssertEqual(WebScrollObserver.countBucket2Plus(0), "0")
        XCTAssertEqual(WebScrollObserver.countBucket2Plus(1), "1")
        XCTAssertEqual(WebScrollObserver.countBucket2Plus(2), "2_plus")
        XCTAssertEqual(WebScrollObserver.countBucket2Plus(5), "2_plus")
    }

    // MARK: static bucket(for:)

    func testBucket_tapRecognizerReturnsTap() {
        let tap = UITapGestureRecognizer()
        XCTAssertEqual(WebScrollObserver.bucket(for: tap), "tap")
    }

    func testBucket_longPressReturnsLongPress() {
        let lp = UILongPressGestureRecognizer()
        XCTAssertEqual(WebScrollObserver.bucket(for: lp), "long_press")
    }

    func testBucket_screenEdgePanReturnsEdgePan() {
        let edge = UIScreenEdgePanGestureRecognizer()
        XCTAssertEqual(WebScrollObserver.bucket(for: edge), "edge_pan")
    }

    func testBucket_scrollViewOwnPanReturnsWebScrollPan() {
        let sv = UIScrollView()
        XCTAssertEqual(WebScrollObserver.bucket(for: sv.panGestureRecognizer), "web_scroll_pan")
    }

    func testBucket_plainPanReturnsOtherPan() {
        let pan = UIPanGestureRecognizer()
        XCTAssertEqual(WebScrollObserver.bucket(for: pan), "other_pan")
    }

    func testBucket_unknownRecognizerReturnsOther() {
        // A bare UIGestureRecognizer is not a pan, tap, long-press, or edge-pan — falls through to "other".
        let r = UIGestureRecognizer()
        XCTAssertEqual(WebScrollObserver.bucket(for: r), "other")
    }
}

// MARK: - Deferring-gate collection tests

/// Tests for `WebScrollFreezeDebugProbe.deferringGates(in:)`.
/// The filter is purely by runtime class name — any recognizer whose type name contains "Deferring"
/// is collected; all others are skipped. We use a custom subclass name that satisfies that check
/// without requiring any private WebKit types.
@MainActor
final class DeferringGateCollectionTests: XCTestCase {

    /// A `UIGestureRecognizer` whose type name contains "Deferring", simulating a
    /// `WKDeferringGestureRecognizer` without using private API.
    private final class SimulatedDeferringGestureRecognizer: UIGestureRecognizer {}

    func testDeferringGates_findsSubclassWhoseNameContainsDeferring() {
        let view = UIView()
        let deferring = SimulatedDeferringGestureRecognizer()
        let plain = UITapGestureRecognizer()
        view.addGestureRecognizer(deferring)
        view.addGestureRecognizer(plain)

        let gates = WebScrollFreezeDebugProbe.deferringGates(in: view)

        XCTAssertEqual(gates.count, 1)
        XCTAssertTrue(gates.first === deferring)
    }

    func testDeferringGates_ignoresRecognizersThatDoNotContainDeferring() {
        let view = UIView()
        view.addGestureRecognizer(UITapGestureRecognizer())
        view.addGestureRecognizer(UIPanGestureRecognizer())
        view.addGestureRecognizer(UILongPressGestureRecognizer())

        let gates = WebScrollFreezeDebugProbe.deferringGates(in: view)

        XCTAssertTrue(gates.isEmpty)
    }

    func testDeferringGates_descendsIntoSubviews() {
        let root = UIView()
        let child = UIView()
        root.addSubview(child)
        let grandchild = UIView()
        child.addSubview(grandchild)

        // Only the grandchild has the deferring recognizer.
        let deferring = SimulatedDeferringGestureRecognizer()
        grandchild.addGestureRecognizer(deferring)

        let gates = WebScrollFreezeDebugProbe.deferringGates(in: root)

        XCTAssertEqual(gates.count, 1)
        XCTAssertTrue(gates.first === deferring)
    }

    func testDeferringGates_emptyViewTreeReturnsEmptyArray() {
        let view = UIView()
        XCTAssertTrue(WebScrollFreezeDebugProbe.deferringGates(in: view).isEmpty)
    }

    func testDeferringGates_collectsMultipleDeferringRecognizersAcrossTree() {
        let root = UIView()
        let child = UIView()
        root.addSubview(child)

        let d1 = SimulatedDeferringGestureRecognizer()
        let d2 = SimulatedDeferringGestureRecognizer()
        root.addGestureRecognizer(d1)
        child.addGestureRecognizer(d2)

        let gates = WebScrollFreezeDebugProbe.deferringGates(in: root)

        XCTAssertEqual(gates.count, 2)
        XCTAssertTrue(gates.contains { $0 === d1 })
        XCTAssertTrue(gates.contains { $0 === d2 })
    }

}

// MARK: - Non-scrollable probe tests

/// Tests for the "not scrollable" guard in `InteractionDiagnosticsModel.probeProgrammaticScroll`.
///
/// `probeProgrammaticScroll` calls `WebScrollFreezeDebugProbe.findMainViewController()` to locate the
/// web scroll view. That method walks `UIApplication.shared.connectedScenes` looking for a
/// `MainViewController`, which does not exist in the XCTest host process. The method therefore
/// returns `nil` and sets `actionResult = "Scroll probe: no web scroll view found"` — the scroll
/// view is never reached, so the ≤64pt guard cannot be exercised through the public API without a
/// full app fixture.
///
/// The logic under test (the guard: `maxY - minY > 64`) is a two-liner inside
/// `probeProgrammaticScroll` that is not extracted into a separately-testable helper; exercising it
/// requires a live `MainViewController` → `TabViewController` → `WKWebView` chain. That chain is not
/// set up by the test host, so the guard is not unit-testable without an integration fixture.
final class ProbeProgrammaticScrollTests: XCTestCase {

    @MainActor
    func testProbeProgrammaticScroll_noWebViewFoundMessage() {
        // In the test host there is no MainViewController, so the probe reports "no web scroll view found"
        // rather than running the scrollability check. This test confirms the "no view" path returns a
        // sensible message that does NOT contain "DID NOT MOVE" (which would be a false failure signal).
        let model = InteractionDiagnosticsModel()
        model.probeProgrammaticScroll()
        XCTAssertFalse(model.actionResult.isEmpty)
        XCTAssertFalse(model.actionResult.contains("DID NOT MOVE"),
                       "The 'no scroll view' path must not emit the failure message")
    }
}

// MARK: - Recovery wording / hypothesis-language tests

/// Asserts that the static result strings emitted by `WebScrollFreezeRecovery` use suspect/hypothesis
/// wording and do NOT make definitive causal claims.
final class RecoveryWordingTests: XCTestCase {

    /// Recovery result strings must never claim a proven cause. Exercises the LIVE return values — in the
    /// test host there is no MainViewController, so each rung returns its non-causal "no web view" status.
    @MainActor
    func testRecoveryResultStringsMakeNoCausalClaim() {
        let results = [
            WebScrollFreezeRecovery.runRung(.resetScrollPan),
            WebScrollFreezeRecovery.runRung(.resetDeferringGates)
        ]
        for result in results {
            XCTAssertFalse(result.contains("WAS the cause"),
                           "Recovery result must not claim a proven cause: \"\(result)\"")
            XCTAssertFalse(result.contains("proven"),
                           "Recovery result must not use 'proven': \"\(result)\"")
        }
    }

    /// autoRecover returns Bool — true only if it actually ran the scoped resets. With no scroll view it
    /// returns false (never a false success), which is also what happens in the test host.
    @MainActor
    func testAutoRecoverWithNoScrollViewReturnsFalse() {
        XCTAssertFalse(WebScrollFreezeRecovery.autoRecover(scrollView: nil),
                       "autoRecover must return false when there is no scroll view to recover.")
    }

    // Scoped recovery skips when a recognizer has touches:
    //
    // `WebScrollFreezeRecovery.anyTouchInFlight()` iterates `UIApplication.shared.connectedScenes`
    // exactly like the deferring-gate scanner. There is no public API to inject an artificial touch
    // count into a recognizer (numberOfTouches is read-only and backed by UIKit internal state), and
    // the scene/window hierarchy that `anyTouchInFlight` walks is not set up in the test host.
    // Verifying the "touch in flight → skip" guard therefore requires a live app window with a real
    // UITouch in-flight — it is not unit-testable without an integration fixture.
}
